import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/app_constants.dart';
import '../model/notification.dart';
import 'notification_formatters.dart';

class NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const NotificationCard({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdueType =
        notification.notificationType == NotificationTypes.overdueTask ||
            notification.status == NotificationStatuses.overdue;
    final isSummary =
        notification.notificationType == NotificationTypes.summaryTask;
    final isHighPriority = notification.notificationType ==
        NotificationTypes.inspectionHighPriority;
    final summaryDesc =
        NotificationFormatters.summaryDescription(notification);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(
          color: isOverdueType || isHighPriority
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    NotificationTypes.displayName(notification.notificationType),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (!notification.isRead)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                notification.title.isEmpty ? '—' : notification.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: NotificationFormatters.statusColor(
                      notification.status),
                ),
              ),
              if (summaryDesc != null) ...[
                const SizedBox(height: 4),
                Text(
                  summaryDesc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ] else if (notification.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  notification.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!isSummary) _StatusBadge(status: notification.status),
                  if (!isSummary) const SizedBox(width: 8),
                  if ((notification.notificationType ==
                              NotificationTypes.assignedInspection ||
                          notification.notificationType ==
                              NotificationTypes.inspectionHighPriority) &&
                      notification.priorityDisplay != null &&
                      notification.priorityDisplay!.isNotEmpty)
                    _PriorityBadge(
                      priority: notification.priority,
                      label: notification.priorityDisplay!,
                    ),
                  const Spacer(),
                  _DeadlineLabel(notification: notification),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _executorOrCreated(notification),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _executorOrCreated(AppNotification n) {
    final created = DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal());
    if (n.notificationType == NotificationTypes.summaryTask) {
      return 'Создано: $created';
    }
    final executor = NotificationFormatters.executorLabel(n);
    if (n.notificationType == NotificationTypes.assignedInspection ||
        n.notificationType == NotificationTypes.inspectionHighPriority) {
      return '$executor  •  $created';
    }
    return '$executor  •  Создано: $created';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = NotificationFormatters.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Text(
        NotificationStatuses.displayName(status),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String? priority;
  final String label;
  const _PriorityBadge({required this.priority, required this.label});

  Color get _color {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Text('Приоритет: $label',
          style: TextStyle(color: _color, fontSize: 12)),
    );
  }
}

class _DeadlineLabel extends StatelessWidget {
  final AppNotification notification;
  const _DeadlineLabel({required this.notification});

  DateTime? get _dueAt {
    final raw = notification.payload['due_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueAt;
    if (due == null) return const SizedBox.shrink();
    final now = DateTime.now().toUtc();
    final diff = due.difference(now);
    final isOverdue = diff.isNegative ||
        notification.notificationType == NotificationTypes.overdueTask;
    final color = isOverdue
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    final absDiff = diff.abs();
    final h = absDiff.inHours;
    final m = absDiff.inMinutes.remainder(60);
    String text;
    if (isOverdue) {
      text = 'Просрочено: ${h}ч ${m}м';
    } else {
      text = 'Осталось: ${h}ч ${m}м';
    }
    return Text(text, style: TextStyle(fontSize: 12, color: color));
  }
}
