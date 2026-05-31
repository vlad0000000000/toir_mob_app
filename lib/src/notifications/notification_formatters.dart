import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../design/app_theme.dart';
import '../model/notification.dart';

/// Чистые форматтеры/стили уведомлений. Вынесены из `_NotificationsScreenState`,
/// чтобы и экран, и `NotificationCard` использовали их без cross-class доступа
/// к приватным статикам State.
class NotificationFormatters {
  /// Семантический цвет статуса уведомления, опираясь на ColorScheme
  /// (success / info / error). Контекст обязателен — нужен ColorScheme.
  static Color statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case NotificationStatuses.newStatus:
        return cs.primary;
      case NotificationStatuses.viewed:
        return cs.info;
      case NotificationStatuses.completed:
        return cs.success;
      case NotificationStatuses.overdue:
        return cs.error;
    }
    return cs.onSurfaceVariant;
  }

  static String formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(local);
  }

  static String? summaryDescription(AppNotification n) {
    if (n.notificationType != NotificationTypes.summaryTask) return null;
    final s = n.payload['summary'];
    if (s is! Map) return null;
    final newTasks = (s['new_tasks'] ?? 0) as int;
    final assigned = (s['assigned_inspections'] ?? 0) as int;
    final overdue = (s['overdue_tasks'] ?? 0) as int;
    return 'Новых: $newTasks, Назначенных: $assigned, Просроченных: $overdue';
  }

  static String executorLabel(AppNotification n) {
    if (n.status == NotificationStatuses.completed) {
      if (n.responsibleUserFullname != null &&
          n.responsibleUserFullname!.isNotEmpty) {
        return 'Исполнитель: ${n.responsibleUserFullname}';
      }
    }
    if (n.notificationType == NotificationTypes.assignedInspection ||
        n.notificationType == NotificationTypes.inspectionHighPriority) {
      if (n.responsibleUserFullname != null &&
          n.responsibleUserFullname!.isNotEmpty) {
        return 'Исполнитель: ${n.responsibleUserFullname}';
      }
    }
    final role = (n.payload['role'] is Map)
        ? (n.payload['role'] as Map)['name'] as String?
        : null;
    if (role != null && role.isNotEmpty) {
      return 'Исполнитель: $role';
    }
    return 'Исполнитель: —';
  }
}
