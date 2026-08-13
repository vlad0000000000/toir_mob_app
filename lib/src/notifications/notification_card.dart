import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/notification.dart';
import 'notification_formatters.dart';

/// Карточка уведомления: тонкая вертикальная акцент-полоса слева (cтатус
/// уведомления), компактный layout заголовок → описание → meta-чипы. Для
/// непрочитанных — тонкая внешняя обводка primary.
class NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const NotificationCard({
    super.key,
    required this.notification,
    required this.onTap,
  });

  bool get _isOverdueType =>
      notification.notificationType == NotificationTypes.overdueTask ||
      notification.status == NotificationStatuses.overdue;
  bool get _isHighPriority =>
      notification.notificationType == NotificationTypes.inspectionHighPriority;
  bool get _isSummary =>
      notification.notificationType == NotificationTypes.summaryTask;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final unread = !notification.isRead;
    final summaryDesc = NotificationFormatters.summaryDescription(notification);
    final descText = summaryDesc ??
        NotificationFormatters.effectiveDescription(notification);
    final accentColor = _accentColor(context);

    return Material(
      color: unread ? cs.surface : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        side: BorderSide(
          color: unread
              ? (_isOverdueType || _isHighPriority
                  ? cs.error.withValues(alpha: 0.4)
                  : cs.outlineVariant)
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacingMD,
                      AppConstants.spacingMD - 2,
                      AppConstants.spacingMD,
                      AppConstants.spacingMD - 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              NotificationTypes.displayName(
                                      notification.notificationType)
                                  .toUpperCase(),
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.title.isEmpty ? '—' : notification.title,
                        style: tt.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w600,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (descText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          descText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppConstants.spacingSM),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!_isSummary)
                            _StatusPill(status: notification.status),
                          if ((notification.notificationType ==
                                      NotificationTypes.assignedInspection ||
                                  notification.notificationType ==
                                      NotificationTypes
                                          .inspectionHighPriority) &&
                              notification.priorityDisplay != null &&
                              notification.priorityDisplay!.isNotEmpty)
                            _PriorityPill(
                              priority: notification.priority,
                              label: notification.priorityDisplay!,
                            ),
                          _DeadlinePill(notification: notification),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _executorOrCreated(notification),
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_isOverdueType || _isHighPriority) return cs.error;
    if (notification.status == NotificationStatuses.completed) {
      return cs.success;
    }
    if (notification.status == NotificationStatuses.viewed) {
      return cs.info;
    }

    if (notification.isRead) return cs.outlineVariant;
    return cs.primary;
  }

  String _executorOrCreated(AppNotification n) {
    final created =
        DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal());
    if (n.notificationType == NotificationTypes.summaryTask) {
      return created;
    }
    final executor = NotificationFormatters.executorLabel(n);
    return '$executor  •  $created';
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = NotificationFormatters.statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            NotificationStatuses.displayName(status),
            style: tt.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  final String? priority;
  final String label;
  const _PriorityPill({required this.priority, required this.label});

  Color _color(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (priority) {
      case 'high':
        return cs.priorityHigh;
      case 'medium':
        return cs.priorityMedium;
      case 'low':
        return cs.priorityLow;
    }
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeadlinePill extends StatelessWidget {
  final AppNotification notification;
  const _DeadlinePill({required this.notification});

  DateTime? get _dueAt {
    final raw = notification.payload['due_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueAt;
    if (due == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now().toUtc();
    final diff = due.difference(now);
    final isOverdue = diff.isNegative ||
        notification.notificationType == NotificationTypes.overdueTask;
    final color = isOverdue ? cs.error : cs.onSurfaceVariant;
    final absDiff = diff.abs();
    final h = absDiff.inHours;
    final m = absDiff.inMinutes.remainder(60);
    final text = isOverdue ? 'Просрочено ${h}ч ${m}м' : 'Осталось ${h}ч ${m}м';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue
            ? cs.error.withValues(alpha: 0.10)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: tt.labelSmall?.copyWith(
              color: color,
              fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
