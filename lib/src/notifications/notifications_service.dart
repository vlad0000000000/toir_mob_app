import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../global_state.dart';
// Импорт нужен ради `syncMyRepairs`: метод объявлен в extension
// `DataProviderSync`, а extension-методы видны только при прямом импорте
// библиотеки, где они объявлены, — через `global_state.dart` не подтягиваются.
import '../data/data_provider.dart';
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
    if (data is Map && data['type'] == 'repair_changed') {
      _syncRepairsOnSignal();
    }
    // Тап по пушу (`type == 'push_tap'`) обрабатывается отдельной
    // подпиской в PushNotificationRouter — независимо от того, был ли
    // позван bootstrap.
  }

  Future<void> refreshList() async {
    if (!GlobalState.isAuthorized) return;
    isLoading.value = true;
    try {
      final result = await _api.getNotifications(
        skip: 0,
        limit: pageSize,
      );
      final sorted = _sortNotifications(result.items);
      notifications.value = sorted;
      unreadCount.value = result.unreadCount;
      hasMore.value = result.items.length >= pageSize;
    } catch (e) {
      debugPrint('Failed to load notifications: $e');
    } finally {
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
        final newOnes =
            result.items.where((e) => !existingUuids.contains(e.uuid)).toList();
        final merged = [...existing, ...newOnes];
        notifications.value = _sortNotifications(merged);
        unreadCount.value = result.unreadCount;
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
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  Future<bool> markRead(String uuid) async {
    try {
      final newUnread = await _api.markNotificationRead(uuid);
      unreadCount.value = newUnread;
      final updated = notifications.value.map((n) {
        if (n.uuid == uuid) {
          return AppNotification(
            uuid: n.uuid,
            notificationType: n.notificationType,
            title: n.title,
            description: n.description,
            status: n.status == NotificationStatuses.newStatus
                ? NotificationStatuses.viewed
                : n.status,
            isRead: true,
            readAt: DateTime.now().toUtc(),
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
        return n;
      }).toList();
      notifications.value = _sortNotifications(updated);
      return true;
    } catch (e) {
      debugPrint('Failed to mark read: $e');
      return false;
    }
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
        debugPrint('SSE silent for ${silentFor.inSeconds}s — force reconnect');
        _scheduleReconnect();
      }
    });
  }

  final SseLineParser _sseParser = SseLineParser();

  void _dispatchSseEvent(String event, String dataStr) {
    if (event == 'ping') return;
    // `repair_changed` — технический сигнал «перечитай ремонты», а не запись в
    // центре уведомлений. Раньше сервер слал его под именем `notification`, и
    // он попадал сюда же; теперь у него собственное имя, и без этой ветки
    // сигнал терялся бы целиком.
    if (event == 'repair_changed') {
      _syncRepairsOnSignal();
      return;
    }
    if (event != 'notification') return;
    refreshList();
  }

  Timer? _repairSyncDebounce;

  /// SSE — только сигнал, источник правды REST (см.
  /// `docs/mobile_notifications_flow.md`), поэтому перечитываем список
  /// ремонтов целиком. Ошибку глушим: нет связи — фоновый цикл догонит через
  /// минуту.
  void _syncRepairsOnSignal() {
    if (!GlobalState.isAuthorized) return;
    // Сигнал рассылается всей компании и на каждое изменение ремонта. Правка
    // нескольких ремонтов в админке подряд — это очередь событий, и без
    // склейки телефон отправил бы столько же запросов списка. Секунды тишины
    // достаточно, чтобы серия схлопнулась в один.
    _repairSyncDebounce?.cancel();
    _repairSyncDebounce = Timer(const Duration(seconds: 1), () async {
      try {
        await GlobalState.dataProvider.syncMyRepairs();
      } catch (e) {
        debugPrint('Failed to sync repairs on SSE signal: $e');
      }
    });
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
    // Иначе отложенная синхронизация сработала бы уже после выхода из учётной
    // записи — с чужим (или снятым) токеном.
    _repairSyncDebounce?.cancel();
    _repairSyncDebounce = null;
    _disconnectStream();
    _detachForegroundListener();
  }

  void onLogout() {
    dispose();
    notifications.value = const [];
    unreadCount.value = 0;
    hasMore.value = true;
    settings.value = NotificationSettings.defaults();
    PushNotificationsController.instance.stop();
  }
}
