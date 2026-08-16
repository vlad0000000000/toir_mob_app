import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../sse_line_parser.dart';

/// Точка входа для изолята foreground-сервиса.
/// Должна быть top-level + `vm:entry-point`.
@pragma('vm:entry-point')
void notificationsForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(NotificationsTaskHandler());
}

/// Обработчик тапа по локальному пушу, который вызывается из background-изолята
/// (когда основное приложение убито/в фоне). Должен быть top-level и
/// помечен `vm:entry-point`.
@pragma('vm:entry-point')
void onLocalNotificationBackgroundTap(NotificationResponse response) {
  // Ставим персистентный флаг — main isolate подхватит его в
  // `PushNotificationRouter.init()` и сделает редирект на /notifications,
  // даже если активити запустилась через launchApp (не через contentIntent).
  try {
    FlutterForegroundTask.saveData(key: 'push_tap_pending', value: true);
  } catch (_) {}
  // Поднимаем активити на экран уведомлений.
  try {
    FlutterForegroundTask.launchApp('/notifications');
  } catch (_) {}
}

class NotificationsTaskHandler extends TaskHandler {
  static const String _eventsChannelId = 'notifications_events';
  static const String _eventsChannelName = 'Уведомления';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  http.Client? _client;
  StreamSubscription<String>? _sseSub;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  DateTime _lastSseActivity = DateTime.now();

  /// Если на SSE-потоке ничего не приходило дольше, чем этот порог —
  /// считаем соединение «тихо умершим» (TCP-сокет не отдал FIN) и
  /// перезапускаем подключение. Покрывает доза-режим и силовое
  /// убиение сокетов сетью оператора.
  static const Duration _silentDropThreshold = Duration(minutes: 3);
  static const Duration _keepaliveCheckInterval = Duration(seconds: 60);

  String _baseUrl = '';
  String _jwt = '';

  bool _stopped = false;
  int _nextNotificationId = 1000;

  /// Окно дедупа по ключу `notification_uuid|status`. SSE может слать один и
  /// тот же upsert повторно (особенно на ре-коннекте) — без дедупа получаются
  /// дубликаты пушей. Ключ включает `status`, а не только uuid: смена
  /// состояния на ТОМ ЖЕ уведомлении (напр. снятие исполнителя с осмотра —
  /// сервер апсертит тот же uuid со `status: unassigned`) должна давать новый
  /// пуш, иначе старый исполнитель его не получал.
  static const int _dedupeWindow = 200;
  final LinkedHashSet<String> _seenKeys = LinkedHashSet<String>();

  final SseLineParser _sseParser = SseLineParser();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _baseUrl =
        (await FlutterForegroundTask.getData<String>(key: 'sse_base_url') ?? '')
            .trim();
    _jwt = (await FlutterForegroundTask.getData<String>(key: 'sse_jwt') ?? '')
        .trim();

    if (_baseUrl.isEmpty || _jwt.isEmpty) {
      debugPrint('[NotifTask] missing base url or jwt — abort');
      await FlutterForegroundTask.stopService();
      return;
    }

    await _initLocalNotifications();
    _connectSse();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // не используем — eventAction = nothing
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  @override
  void onReceiveData(Object data) {
    // Зарезервировано: можно прокинуть смену токена/baseUrl без рестарта.
    if (data is Map) {
      final token = data['jwt'];
      final url = data['base_url'];
      var needReconnect = false;
      if (token is String && token.isNotEmpty && token != _jwt) {
        _jwt = token;
        needReconnect = true;
      }
      if (url is String && url.isNotEmpty && url != _baseUrl) {
        _baseUrl = url;
        needReconnect = true;
      }
      if (needReconnect) {
        _disconnectSse();
        _connectSse();
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/notifications');
  }

  @override
  void onNotificationDismissed() {}

  // ---------- internals ----------

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    // ВАЖНО: background-изолят сервиса инициализирует плагин позже main-изолята,
    // поэтому его initialize() ПЕРЕЗАПИСЫВАЕТ tap-callback, выставленный в
    // main (PushNotificationRouter.init). Чтобы тап по пушу всё равно
    // открывал экран уведомлений, регистрируем callback и здесь.
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalTap,
      onDidReceiveBackgroundNotificationResponse:
          onLocalNotificationBackgroundTap,
    );

    const channel = AndroidNotificationChannel(
      _eventsChannelId,
      _eventsChannelName,
      description: 'Push-like уведомления о событиях',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _onLocalTap(NotificationResponse response) {
    // Ремонт открываем адресно; всё остальное — как раньше, общим экраном
    // уведомлений.
    String? repairUuid;
    try {
      final payload = jsonDecode(response.payload ?? '{}');
      if (payload is Map && payload['repair_uuid'] is String) {
        repairUuid = payload['repair_uuid'] as String;
      }
    } catch (_) {}

    // Если main isolate жив — он сам сделает GoRouter навигацию.
    try {
      FlutterForegroundTask.sendDataToMain({
        'type': 'push_tap',
        if (repairUuid != null) 'repair_uuid': repairUuid,
      });
    } catch (_) {}
    // Подстраховка для cold-start: ставим персистентный флаг, который main
    // при `init()` подхватит и инициирует переход даже если активити пришлось
    // запускать через launchApp (а не через contentIntent самого пуша).
    try {
      FlutterForegroundTask.saveData(key: 'push_tap_pending', value: true);
      if (repairUuid != null) {
        FlutterForegroundTask.saveData(
            key: 'push_tap_repair', value: repairUuid);
      }
    } catch (_) {}
    try {
      FlutterForegroundTask.launchApp('/notifications');
    } catch (_) {}
  }

  void _connectSse() {
    if (_stopped) return;
    if (_sseSub != null) return;

    final client = http.Client();
    _client = client;

    final request = http.Request(
        'GET', Uri.parse('$_baseUrl/v1/company/notifications/mobile/stream'));
    request.headers['Authorization'] = 'Bearer $_jwt';
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    client.send(request).then((response) {
      if (_stopped) {
        client.close();
        return;
      }
      if (response.statusCode != 200) {
        debugPrint('[NotifTask] SSE bad status: ${response.statusCode}');
        client.close();
        _client = null;
        _scheduleReconnect();
        return;
      }
      _lastSseActivity = DateTime.now();
      _ensureKeepalive();
      _sseSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _lastSseActivity = DateTime.now();
          _sseParser.handleLine(line, _dispatchEvent);
        },
        onError: (Object e) {
          debugPrint('[NotifTask] SSE error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[NotifTask] SSE done');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    }).catchError((Object e) {
      debugPrint('[NotifTask] SSE connect failed: $e');
      try {
        client.close();
      } catch (_) {}
      _client = null;
      _scheduleReconnect();
    });
  }

  void _disconnectSse() {
    _sseSub?.cancel();
    _sseSub = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _sseParser.reset();
  }

  void _scheduleReconnect() {
    _disconnectSse();
    if (_stopped) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_stopped) return;
      _connectSse();
    });
  }

  /// Сторож: SSE-сокет может «тихо умереть» (TCP keep-alive не успел
  /// отвалиться по таймауту → ни onError, ни onDone). Раз в минуту проверяем,
  /// что хоть что-то прилетало за последние [_silentDropThreshold]; если нет —
  /// форсируем reconnect. Сервер обычно шлёт `event: ping` каждые 30-60с,
  /// поэтому 3 минуты тишины — это уже точно мёртвое соединение.
  void _ensureKeepalive() {
    if (_keepaliveTimer != null) return;
    _keepaliveTimer = Timer.periodic(_keepaliveCheckInterval, (_) {
      if (_stopped) return;
      final silentFor = DateTime.now().difference(_lastSseActivity);
      if (silentFor > _silentDropThreshold) {
        debugPrint(
            '[NotifTask] SSE silent for ${silentFor.inSeconds}s — force reconnect');
        _scheduleReconnect();
      }
    });
  }

  Future<void> _dispatchEvent(String event, String dataStr) async {
    // `repair_changed` — сигнал перечитать ремонты, а не запись центра
    // уведомлений: пуш по нему не показываем, только будим main-изолят.
    // Раньше сервер слал его под именем `notification`, и он приходил сюда
    // же; теперь у события собственное имя, и без этой ветки сигнал бы
    // отбрасывался.
    if (event == 'repair_changed') {
      try {
        FlutterForegroundTask.sendDataToMain({
          'type': 'repair_changed',
          'data': jsonDecode(dataStr),
        });
      } catch (_) {}
      return;
    }
    if (event != 'notification') return;
    Map<String, dynamic> data = const {};
    try {
      data = jsonDecode(dataStr) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final action = data['action'] as String?;
    if (action != 'upsert') {
      // Сообщаем main isolate, что список изменился (если приложение открыто).
      FlutterForegroundTask.sendDataToMain({'type': 'sse_event', 'data': data});
      return;
    }

    final notificationUuid = data['notification_uuid'] as String?;
    final notificationType = data['notification_type']?.toString();

    // Деталь тянем ДО дедупа: она нужна и для текста пуша, и для ключа
    // дедупа (`uuid|status`). Без детали пуш не показываем — лучше пропустить
    // один кадр, чем светить системное имя типа («new_task» и т. п.).
    final detail = await _fetchNotificationDetail(notificationUuid);
    if (detail == null) {
      debugPrint(
          '[NotifTask] detail not found for $notificationUuid ($notificationType) — skip push');
      FlutterForegroundTask.sendDataToMain({'type': 'sse_event', 'data': data});
      return;
    }

    // Дедуп по `uuid|status`: тот же upsert может прилететь снова (re-connect
    // SSE, сетевой ретрай, двойная эмиссия сервера) — пуш показываем максимум
    // один раз. Но смена `status` на том же uuid (assigned -> unassigned) даёт
    // новый ключ и, как следствие, новый пуш.
    if (notificationUuid != null && notificationUuid.isNotEmpty) {
      final status = detail['status']?.toString() ?? '';
      final dedupeKey = '$notificationUuid|$status';
      if (_seenKeys.contains(dedupeKey)) {
        debugPrint('[NotifTask] duplicate upsert $dedupeKey — skip');
        FlutterForegroundTask.sendDataToMain(
            {'type': 'sse_event', 'data': data});
        return;
      }
      _seenKeys.add(dedupeKey);
      while (_seenKeys.length > _dedupeWindow) {
        _seenKeys.remove(_seenKeys.first);
      }
    }

    // Summary task — это агрегатный дайджест, его не нужно показывать
    // пушем (только в списке внутри приложения). Без этого фильтра
    // пользователь получал две нотификации: одну с cryptic-текстом
    // «summary_task» (когда деталь ещё не успела проиндексироваться на
    // бэке), и вторую — нормальную.
    //
    // Проверка стоит после дедупа намеренно: ключ сводки при этом попадает
    // в окно, и повторный upsert по нему не пойдёт дальше по коду.
    if (notificationType == 'summary_task') {
      debugPrint('[NotifTask] summary_task — skip push, only update list');
      FlutterForegroundTask.sendDataToMain({'type': 'sse_event', 'data': data});
      return;
    }

    await _showLocalNotification(detail);

    FlutterForegroundTask.sendDataToMain({'type': 'sse_event', 'data': data});
  }

  /// Тянем `GET /mobile?limit=20` и ищем уведомление по uuid.
  /// Если бэк отдаст несколько свежих — берём нужное.
  Future<Map<String, dynamic>?> _fetchNotificationDetail(String? uuid) async {
    if (uuid == null || uuid.isEmpty) return null;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/company/notifications/mobile?limit=20'),
        headers: {
          'Authorization': 'Bearer $_jwt',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      const decoder = Utf8Decoder(allowMalformed: true);
      final body = jsonDecode(decoder.convert(response.bodyBytes))
          as Map<String, dynamic>;
      final items = (body['items'] as List?) ?? const [];
      for (final raw in items) {
        if (raw is Map<String, dynamic> && raw['uuid'] == uuid) {
          return raw;
        }
      }
    } catch (e) {
      debugPrint('[NotifTask] fetch detail failed: $e');
    }
    return null;
  }

  Future<void> _showLocalNotification(Map<String, dynamic> item) async {
    final type = item['notification_type']?.toString();
    final isSummary = type == 'summary_task';

    final title = (item['title'] as String?)?.trim().isNotEmpty == true
        ? item['title'] as String
        : (isSummary ? 'Сводка по задачам' : 'Уведомление');

    var body = (item['description'] as String?) ?? '';
    // Для сводки сервер часто не кладёт description — собираем текст из
    // payload.summary.
    if (isSummary) {
      final summary = item['payload'] is Map
          ? (item['payload'] as Map)['summary']
          : null;
      if (summary is Map) {
        final newTasks = (summary['new_tasks'] ?? 0);
        final assigned = (summary['assigned_inspections'] ?? 0);
        final overdue = (summary['overdue_tasks'] ?? 0);
        body = 'Новых: $newTasks, Назначенных: $assigned, Просроченных: $overdue';
      } else if (body.isEmpty) {
        body = 'Есть новые задачи и осмотры';
      }
    }
    final uuid = item['uuid']?.toString();
    // Детерминированный id из uuid → если по какой-то причине пуш всё же
    // покажется повторно, Android заменит существующее уведомление,
    // а не выложит второе сверху.
    final id = (uuid != null && uuid.isNotEmpty)
        ? uuid.hashCode & 0x7FFFFFFF
        : _nextNotificationId++;
    // repair_uuid кладём отдельным полем: тап по пушу должен открывать саму
    // карточку ремонта, а не общий экран уведомлений. Наверху ответа его нет,
    // он лежит в payload.repair.uuid.
    String? repairUuid;
    final itemPayload = item['payload'];
    if (itemPayload is Map) {
      final repair = itemPayload['repair'];
      if (repair is Map && repair['uuid'] is String) {
        repairUuid = repair['uuid'] as String;
      }
    }

    final payload = jsonEncode({
      'uuid': item['uuid'],
      'notification_type': item['notification_type'],
      'equipment_uuid': item['equipment_uuid'],
      'inspection_uuid': item['inspection_uuid'],
      'repair_uuid': repairUuid,
    });

    const androidDetails = AndroidNotificationDetails(
      _eventsChannelId,
      _eventsChannelName,
      channelDescription: 'Push-like уведомления о событиях',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'notification',
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(id, title, body, details, payload: payload);
  }
}
