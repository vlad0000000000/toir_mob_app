import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../global_state.dart';
import '../http/api.dart';
import '../model/notification.dart';
import '../model/notification_settings.dart';

class NotificationsService {
  NotificationsService._();

  static final NotificationsService instance = NotificationsService._();

  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final ValueNotifier<NotificationSettings> settings =
      ValueNotifier<NotificationSettings>(NotificationSettings.defaults());
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final API _api = API();

  StreamedResponseHandle? _streamHandle;
  StreamSubscription<String>? _streamSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  Future<void> bootstrap() async {
    _disposed = false;
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

  Future<void> refreshList({
    List<String>? types,
    List<String>? statuses,
    String? equipmentUuid,
    String? priority,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 100,
  }) async {
    if (!GlobalState.isAuthorized) return;
    isLoading.value = true;
    try {
      final result = await _api.getNotifications(
        limit: limit,
        notificationTypes: types,
        statuses: statuses,
        equipmentUuid: equipmentUuid,
        priority: priority,
        createdFrom: createdFrom,
        createdTo: createdTo,
      );
      final sorted = _sortNotifications(result.items);
      notifications.value = sorted;
      unreadCount.value = result.unreadCount;
    } catch (e) {
      debugPrint('Failed to load notifications: $e');
    } finally {
      isLoading.value = false;
    }
  }

  List<AppNotification> _sortNotifications(List<AppNotification> items) {
    final overdue = <AppNotification>[];
    final rest = <AppNotification>[];
    for (final n in items) {
      if (n.status == NotificationStatuses.overdue ||
          n.notificationType == NotificationTypes.overdueTask) {
        overdue.add(n);
      } else {
        rest.add(n);
      }
    }
    overdue.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    rest.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...overdue, ...rest];
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
      notifications.value = updated;
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
      _streamSubscription = handle.response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleStreamLine,
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

  String? _currentEvent;
  final StringBuffer _currentData = StringBuffer();

  void _handleStreamLine(String line) {
    if (line.isEmpty) {
      if (_currentEvent != null) {
        _dispatchSseEvent(_currentEvent!, _currentData.toString());
      }
      _currentEvent = null;
      _currentData.clear();
      return;
    }
    if (line.startsWith(':')) return;
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (_currentData.isNotEmpty) _currentData.write('\n');
      _currentData.write(line.substring(5).trim());
    }
  }

  void _dispatchSseEvent(String event, String dataStr) {
    if (event == 'ping') return;
    if (event != 'notification') return;
    Map<String, dynamic> data = const {};
    try {
      data = jsonDecode(dataStr) as Map<String, dynamic>;
    } catch (_) {}
    // По контракту - просто перечитать список
    refreshList();
    _onForegroundNotification(data);
  }

  final ValueNotifier<AppNotification?> lastIncoming =
      ValueNotifier<AppNotification?>(null);

  void _onForegroundNotification(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action != 'upsert') return;
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
    _disconnectStream();
  }

  void onLogout() {
    dispose();
    notifications.value = const [];
    unreadCount.value = 0;
    settings.value = NotificationSettings.defaults();
  }
}
