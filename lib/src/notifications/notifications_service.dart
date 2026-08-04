import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../global_state.dart';
import '../http/api.dart';
import '../model/notification.dart';
import '../model/notification_settings.dart';
import 'push/push_notifications_controller.dart';
import 'sse_line_parser.dart';

class NotificationsService {
  NotificationsService._();

  static final NotificationsService instance = NotificationsService._();

  static const int pageSize = 30;

  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final ValueNotifier<NotificationSettings> settings =
      ValueNotifier<NotificationSettings>(NotificationSettings.defaults());
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingMore = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hasMore = ValueNotifier<bool>(true);

  /// `true` после того, как первый refreshList завершился (успешно или с
  /// ошибкой). Нужен экрану: пока false — показывает spinner, не EmptyState,
  /// иначе на холодном старте мелькает «Уведомлений пока нет», пока ответ
  /// сервера ещё в полёте.
  final ValueNotifier<bool> hasLoadedOnce = ValueNotifier<bool>(false);

  final API _api = API();

  StreamedResponseHandle? _streamHandle;
  StreamSubscription<String>? _streamSubscription;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  DateTime _lastSseActivity = DateTime.now();
  static const Duration _silentDropThreshold = Duration(minutes: 3);
  static const Duration _keepaliveCheckInterval = Duration(seconds: 60);

  bool _disposed = false;

  /// Координация перечитываний списка. Список перечитывают сразу несколько
  /// источников: in-app SSE, foreground-сервис (через sendDataToMain),
  /// pull-to-refresh, апдейт настроек. Без сериализации параллельные
  /// `GET /mobile` завершаются в произвольном порядке, и последний
  /// долетевший ответ перетирает актуальный → счётчик «N новых» скачет и
  /// список «прыгает». [_refreshInFlight] не даёт запускать одновременные
  /// запросы (повторный триггер просто ставит [_refreshQueued]), а
  /// [_refreshSeq] позволяет [markRead] аннулировать уже летящий ответ,
  /// чтобы он не вернул только что прочитанное обратно в «непрочитано».
  int _refreshSeq = 0;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  /// UUID'ы, помеченные прочитанными локально (по тапу), но которые сервер
  /// мог ещё не успеть отразить в `GET /mobile` (реплика/кэш отстают на
  /// доли секунды). Пока сервер не подтвердит `is_read = true`, мы
  /// реконсилим его ответ: держим элемент прочитанным и не считаем его в
  /// `unread_count`. Иначе перечитывание, прилетевшее сразу после markRead
  /// (его триггерит SSE-upsert от самой же пометки), вернуло бы прежний
  /// счётчик — «N новых» подскакивал вверх и тут же возвращался к верному.
  final Set<String> _locallyRead = <String>{};

  Future<void> bootstrap() async {
    _disposed = false;
    _attachForegroundListener();
    // Сразу включаем флаг загрузки — иначе первая отрисовка экрана видит
    // isLoading=false + пустой список и моргает EmptyState'ом до того, как
    // запрос успеет долететь до сервера.
    isLoading.value = true;
    try {
      final s = await _api.getNotificationSettings();
      settings.value = s;
    } catch (e) {
      debugPrint('Failed to load notification settings: $e');
    }
    await refreshList();
    if (settings.value.realtimeEnabled && settings.value.notificationsEnabled) {
      _connectStream();
    }
  }

  void _attachForegroundListener() {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_foregroundAttached) return;
    _foregroundAttached = true;
    FlutterForegroundTask.addTaskDataCallback(_onForegroundData);
  }

  void _detachForegroundListener() {
    if (!_foregroundAttached) return;
    _foregroundAttached = false;
    try {
      FlutterForegroundTask.removeTaskDataCallback(_onForegroundData);
    } catch (_) {}
  }

  bool _foregroundAttached = false;

  void _onForegroundData(Object data) {
    if (data is Map && data['type'] == 'sse_event') {
      refreshList();
    }
    // Тап по пушу (`type == 'push_tap'`) обрабатывается отдельной
    // подпиской в PushNotificationRouter — независимо от того, был ли
    // позван bootstrap.
  }

  Future<void> refreshList() async {
    if (!GlobalState.isAuthorized) return;
    // Уже идёт перечитывание — не плодим параллельные запросы. Помечаем, что
    // нужно ещё раз, и текущий цикл перезапросит сам после завершения.
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    isLoading.value = true;
    try {
      do {
        _refreshQueued = false;
        final seq = ++_refreshSeq;
        // Сохраняем уже загруженный объём: realtime-перечитывание не должно
        // схлопывать пролистанный список обратно к первой странице.
        // Сервер ограничивает limit сотней (см. api.md §7.1) — не превышаем.
        final loaded = notifications.value.length;
        final wanted = loaded <= pageSize
            ? pageSize
            : (loaded > 100 ? 100 : loaded);
        final result = await _api.getNotifications(skip: 0, limit: wanted);
        // markRead() во время полёта запроса инкрементит _refreshSeq — значит
        // наш снапшот уже устарел и его применять нельзя (иначе вернём
        // прочитанное обратно в «непрочитано»).
        if (seq != _refreshSeq) continue;
        var items = result.items;
        var unread = result.unreadCount;
        // Реконсиляция со свежими локальными пометками — см. [_locallyRead].
        if (_locallyRead.isNotEmpty) {
          final out = <AppNotification>[];
          for (final n in items) {
            if (_locallyRead.contains(n.uuid)) {
              if (n.isRead) {
                // Сервер догнал — снимаем локальную пометку.
                _locallyRead.remove(n.uuid);
                out.add(n);
              } else {
                // Сервер ещё отдаёт элемент непрочитанным — держим свою
                // пометку и не учитываем его в счётчике.
                unread = unread > 0 ? unread - 1 : 0;
                out.add(_asRead(n));
              }
            } else {
              out.add(n);
            }
          }
          items = out;
        }
        notifications.value = _sortNotifications(items);
        unreadCount.value = unread;
        hasMore.value = result.items.length >= wanted;
      } while (_refreshQueued);
    } catch (e) {
      debugPrint('Failed to load notifications: $e');
    } finally {
      _refreshInFlight = false;
      isLoading.value = false;
      hasLoadedOnce.value = true;
    }
  }

  Future<void> loadMore() async {
    if (!GlobalState.isAuthorized) return;
    if (isLoadingMore.value || isLoading.value) return;
    if (!hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final result = await _api.getNotifications(
        skip: notifications.value.length,
        limit: pageSize,
      );
      if (result.items.isEmpty) {
        hasMore.value = false;
      } else {
        final existing = notifications.value;
        final existingUuids = existing.map((e) => e.uuid).toSet();
        final newOnes = result.items
            .where((e) => !existingUuids.contains(e.uuid))
            .map((e) =>
                _locallyRead.contains(e.uuid) && !e.isRead ? _asRead(e) : e)
            .toList();
        final merged = [...existing, ...newOnes];
        notifications.value = _sortNotifications(merged);
        // НЕ трогаем unreadCount: пагинация подгружает старые элементы и не
        // меняет общее число непрочитанных. Авторитетные источники счётчика —
        // refreshList (полное перечитывание по SSE) и markRead (дельта с
        // сервера). Иначе ответ loadMore, долетевший после markRead, вернул бы
        // прежний (больший) счётчик → «N новых» скачет вверх.
        hasMore.value = result.items.length >= pageSize;
      }
    } catch (e) {
      debugPrint('Failed to load more notifications: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  List<AppNotification> _sortNotifications(List<AppNotification> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final byCreated = b.createdAt.compareTo(a.createdAt);
      if (byCreated != 0) return byCreated;
      // Тай-брейк по uuid: при совпадающем createdAt (пачка/сводка приходят
      // одним timestamp) сортировка Dart нестабильна и переставляет равные
      // элементы на каждом пере-сорте — карточки «прыгают», прочитанные то
      // выше, то ниже. Детерминированный ключ это убирает.
      return a.uuid.compareTo(b.uuid);
    });
    return sorted;
  }

  Future<bool> markRead(String uuid) async {
    try {
      final newUnread = await _api.markNotificationRead(uuid);
      // Запоминаем локальную пометку: refreshList, прилетевший до того как
      // сервер отразит чтение, не должен вернуть карточку в «непрочитано»
      // и подбросить счётчик. Снимется, когда сервер подтвердит is_read.
      _locallyRead.add(uuid);
      unreadCount.value = newUnread;
      final updated = notifications.value
          .map((n) => n.uuid == uuid ? _asRead(n) : n)
          .toList();
      notifications.value = _sortNotifications(updated);
      // Аннулируем уже летящий refreshList (если он стартовал до пометки):
      // его устаревший снапшот вернул бы карточку обратно в «непрочитано» и
      // дёрнул бы счётчик вверх.
      _refreshSeq++;
      return true;
    } catch (e) {
      debugPrint('Failed to mark read: $e');
      return false;
    }
  }

  /// Копия уведомления, помеченная прочитанной. Статус `new` → `viewed`
  /// (как у других прочитанных), прочие статусы сохраняются.
  AppNotification _asRead(AppNotification n) {
    return AppNotification(
      uuid: n.uuid,
      notificationType: n.notificationType,
      title: n.title,
      description: n.description,
      status: n.status == NotificationStatuses.newStatus
          ? NotificationStatuses.viewed
          : n.status,
      isRead: true,
      readAt: n.readAt ?? DateTime.now().toUtc(),
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
      priority: n.priority,
      priorityDisplay: n.priorityDisplay,
      equipmentUuid: n.equipmentUuid,
      equipmentName: n.equipmentName,
      inspectionUuid: n.inspectionUuid,
      responsibleUserUuid: n.responsibleUserUuid,
      responsibleUserFullname: n.responsibleUserFullname,
      targetScope: n.targetScope,
      canOpenTarget: n.canOpenTarget,
      payload: n.payload,
    );
  }

  Future<void> updateSettings(Map<String, dynamic> partial) async {
    try {
      final s = await _api.patchNotificationSettings(partial);
      settings.value = s;
      if (s.realtimeEnabled && s.notificationsEnabled) {
        _connectStream();
      } else {
        _disconnectStream();
      }
      await refreshList();
    } catch (e) {
      debugPrint('Failed to update settings: $e');
      rethrow;
    }
  }

  void _connectStream() {
    if (_streamHandle != null) return;
    _api.openNotificationStream().then((handle) {
      if (_disposed) {
        handle.close();
        return;
      }
      _streamHandle = handle;
      _lastSseActivity = DateTime.now();
      _ensureKeepalive();
      _streamSubscription = handle.response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _lastSseActivity = DateTime.now();
          _sseParser.handleLine(line, _dispatchSseEvent);
        },
        onError: (Object e) {
          debugPrint('SSE error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('SSE done');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    }).catchError((Object e) {
      debugPrint('Failed to open SSE: $e');
      _scheduleReconnect();
    });
  }

  /// Watchdog: SSE-сокет может «тихо умереть» — ни onError, ни onDone.
  /// Раз в минуту проверяем активность; если тихо больше 3 минут — рвём
  /// и переподключаемся. См. аналог в NotificationsTaskHandler.
  void _ensureKeepalive() {
    if (_keepaliveTimer != null) return;
    _keepaliveTimer = Timer.periodic(_keepaliveCheckInterval, (_) {
      if (_disposed) return;
      final silentFor = DateTime.now().difference(_lastSseActivity);
      if (silentFor > _silentDropThreshold) {
        debugPrint(
            'SSE silent for ${silentFor.inSeconds}s — force reconnect');
        _scheduleReconnect();
      }
    });
  }

  final SseLineParser _sseParser = SseLineParser();

  void _dispatchSseEvent(String event, String dataStr) {
    if (event == 'ping') return;
    if (event != 'notification') return;
    refreshList();
  }

  void _scheduleReconnect() {
    _disconnectStream();
    if (_disposed) return;
    if (!settings.value.realtimeEnabled ||
        !settings.value.notificationsEnabled) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectStream();
    });
  }

  void _disconnectStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamHandle?.close();
    _streamHandle = null;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _disconnectStream();
    _detachForegroundListener();
  }

  void onLogout() {
    dispose();
    notifications.value = const [];
    unreadCount.value = 0;
    _locallyRead.clear();
    hasMore.value = true;
    settings.value = NotificationSettings.defaults();
    PushNotificationsController.instance.stop();
  }
}
