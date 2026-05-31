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

  String _baseUrl = '';
  String _jwt = '';

  bool _stopped = false;
  int _nextNotificationId = 1000;

  /// Окно дедупа по `notification_uuid`. SSE может слать один и тот же
  /// upsert повторно (особенно на ре-коннекте) — без дедупа получаются
  /// дубликаты пушей.
  static const int _dedupeWindow = 200;
  final LinkedHashSet<String> _seenUuids = LinkedHashSet<String>();

  final SseLineParser _sseParser = SseLineParser();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _baseUrl = (await FlutterForegroundTask.getData<String>(
                key: 'sse_base_url') ??
            '')
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
    // Если main isolate жив — он сам сделает GoRouter навигацию.
    try {
      FlutterForegroundTask.sendDataToMain({'type': 'push_tap'});
    } catch (_) {}
    // Подстраховка для cold-start: ставим персистентный флаг, который main
    // при `init()` подхватит и инициирует переход на /notifications даже
    // если активити пришлось запускать через launchApp (а не через
    // contentIntent самого пуша).
    try {
      FlutterForegroundTask.saveData(key: 'push_tap_pending', value: true);
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

    final request = http.Request('GET',
        Uri.parse('$_baseUrl/v1/company/notifications/mobile/stream'));
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
      _sseSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) => _sseParser.handleLine(line, _dispatchEvent),
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

  Future<void> _dispatchEvent(String event, String dataStr) async {
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

    // Дедуп по uuid: тот же upsert может прилететь снова (re-connect SSE,
    // сетевой ретрай и т. п.) — пуш показываем максимум один раз.
    final notificationUuid = data['notification_uuid'] as String?;
    if (notificationUuid != null && notificationUuid.isNotEmpty) {
      if (_seenUuids.contains(notificationUuid)) {
        debugPrint('[NotifTask] duplicate upsert $notificationUuid — skip');
        FlutterForegroundTask.sendDataToMain(
            {'type': 'sse_event', 'data': data});
        return;
      }
      _seenUuids.add(notificationUuid);
      while (_seenUuids.length > _dedupeWindow) {
        _seenUuids.remove(_seenUuids.first);
      }
    }

    // Подтягиваем детали и показываем уведомление.
    final detail = await _fetchNotificationDetail(notificationUuid);
    if (detail != null) {
      await _showLocalNotification(detail);
    } else {
      // Фоллбэк: показать общее уведомление с типом.
      await _showLocalNotification({
        'uuid': notificationUuid,
        'title': 'Новое уведомление',
        'description': data['notification_type']?.toString() ?? '',
      });
    }

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
    final title = (item['title'] as String?)?.trim().isNotEmpty == true
        ? item['title'] as String
        : 'Уведомление';
    final body = (item['description'] as String?) ?? '';
    final uuid = item['uuid']?.toString();
    // Детерминированный id из uuid → если по какой-то причине пуш всё же
    // покажется повторно, Android заменит существующее уведомление,
    // а не выложит второе сверху.
    final id = (uuid != null && uuid.isNotEmpty)
        ? uuid.hashCode & 0x7FFFFFFF
        : _nextNotificationId++;
    final payload = jsonEncode({
      'uuid': item['uuid'],
      'notification_type': item['notification_type'],
      'equipment_uuid': item['equipment_uuid'],
      'inspection_uuid': item['inspection_uuid'],
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
