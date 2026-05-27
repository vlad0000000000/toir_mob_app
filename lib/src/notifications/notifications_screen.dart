import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../settings.dart';
import '../model/inventory_record.dart';
import '../model/notification.dart';
import '../model/task.dart';
import '../utils/go_router_ext.dart';
import 'notifications_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsService _service = NotificationsService.instance;
  final ScrollController _scrollController = ScrollController();
  Timer? _tickTimer;
  bool _hideRead = false;

  @override
  void initState() {
    super.initState();
    _hideRead = Settings.notificationsHideRead;
    _service.bootstrap();
    _scrollController.addListener(_onScroll);
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _service.loadMore();
    }
  }

  Future<void> _refresh() async {
    await _service.refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/actions');
          },
        ),
        title: ValueListenableBuilder<int>(
          valueListenable: _service.unreadCount,
          builder: (context, count, _) {
            if (count > 0) {
              return Text('Уведомления ($count)');
            }
            return const Text('Уведомления');
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки уведомлений',
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/notifications_settings');
            },
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _HideReadToggle(
            value: _hideRead,
            onChanged: (v) {
              setState(() => _hideRead = v);
              Settings.notificationsHideRead = v;
            },
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _service.isLoading,
              builder: (context, loading, _) {
                return ValueListenableBuilder<List<AppNotification>>(
                  valueListenable: _service.notifications,
                  builder: (context, allItems, __) {
                    final items = _hideRead
                        ? allItems.where((n) => !n.isRead).toList()
                        : allItems;
                    if (loading && items.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.notifications_off_outlined,
                                  size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Уведомлений нет',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _service.isLoadingMore,
                  builder: (context, loadingMore, ___) {
                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      itemCount: items.length + (loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i >= items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final n = items[i];
                        return NotificationCard(
                          notification: n,
                          onTap: () => _onTap(n),
                        );
                      },
                    );
                  },
                ),
              );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.isRead) {
      await _service.markRead(n.uuid);
    }
    if (!mounted) return;
    _showDetail(n);
  }

  void _showDetail(AppNotification n) {
    InventoryRecord? equipment;
    if (n.equipmentUuid != null) {
      final matches = GlobalState.dataProvider.inventoryRecords
          .where((r) => r.uuid == n.equipmentUuid)
          .toList();
      if (matches.isNotEmpty) equipment = matches.first;
    }
    Task? task;
    if (n.inspectionUuid != null) {
      for (final t in GlobalState.dataProvider.taskBox.values) {
        if (t.uuid == n.inspectionUuid) {
          task = t;
          break;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          NotificationTypes.displayName(n.notificationType),
                          style: const TextStyle(
                              fontSize: 14, color: Colors.grey),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    n.title.isEmpty ? '—' : n.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_summaryDescription(n) != null) ...[
                    Text(_summaryDescription(n)!),
                    const SizedBox(height: 8),
                  ] else if (n.description.isNotEmpty) ...[
                    Text(n.description),
                    const SizedBox(height: 8),
                  ],
                  if (n.notificationType != NotificationTypes.summaryTask)
                    _statusChip(n),
                  if (n.notificationType != NotificationTypes.summaryTask)
                    const SizedBox(height: 8),
                  if (n.priorityDisplay != null &&
                      n.priorityDisplay!.isNotEmpty)
                    Text('Приоритет: ${n.priorityDisplay}'),
                  const SizedBox(height: 4),
                  Text(_executorLabel(n)),
                  const SizedBox(height: 4),
                  Text('Создано: ${_formatDateTime(n.createdAt)}'),
                  if (task != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Задача',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._buildTaskInfo(task),
                  ],
                  if (equipment != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Оборудование',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._buildEquipmentInfo(equipment),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTaskInfo(Task task) {
    final widgets = <Widget>[];
    final pt = task.periodicTask;
    if (pt != null) {
      if (pt.title.isNotEmpty) {
        widgets.add(_kv('Название', pt.title));
      }
      if (pt.description != null && pt.description!.isNotEmpty) {
        widgets.add(_kv('Описание', pt.description!));
      }
      if (pt.periodicityRuleDisplay.isNotEmpty) {
        widgets.add(_kv('Периодичность', pt.periodicityRuleDisplay));
      }
      if (pt.nextDueAt != null) {
        widgets.add(_kv('Срок', _formatDateTime(pt.nextDueAt!)));
      }
      if (pt.node != null && pt.node!.isNotEmpty) {
        widgets.add(_kv('Узел', pt.node!));
      }
    }
    if (task.comment != null && task.comment!.isNotEmpty) {
      widgets.add(_kv('Комментарий', task.comment!));
    }
    if (task.roles.isNotEmpty) {
      widgets.add(_kv('Роли', task.roles.join(', ')));
    }
    if (widgets.isEmpty) {
      widgets.add(const Text('—', style: TextStyle(color: Colors.grey)));
    }
    return widgets;
  }

  List<Widget> _buildEquipmentInfo(InventoryRecord eq) {
    final widgets = <Widget>[
      _kv('Название', eq.name),
    ];
    if (eq.typeModel != null && eq.typeModel!.isNotEmpty) {
      widgets.add(_kv('Тип / модель', eq.typeModel!));
    }
    if (eq.serialNumber != null && eq.serialNumber!.isNotEmpty) {
      widgets.add(_kv('Серийный номер', eq.serialNumber!));
    }
    if (eq.location != null && eq.location!.isNotEmpty) {
      widgets.add(_kv('Местоположение', eq.location!));
    }
    if (eq.manufacturer != null && eq.manufacturer!.isNotEmpty) {
      widgets.add(_kv('Производитель', eq.manufacturer!));
    }
    if (eq.description != null && eq.description!.isNotEmpty) {
      widgets.add(_kv('Описание', eq.description!));
    }
    return widgets;
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _statusChip(AppNotification n) {
    final color = _statusColor(n.status);
    final label = NotificationStatuses.displayName(n.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color)),
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case NotificationStatuses.newStatus:
        return Colors.red;
      case NotificationStatuses.viewed:
        return Colors.blue;
      case NotificationStatuses.completed:
        return Colors.green;
      case NotificationStatuses.overdue:
        return Colors.red.shade700;
    }
    return Colors.grey;
  }

  static String _formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(local);
  }

  static String? _summaryDescription(AppNotification n) {
    if (n.notificationType != NotificationTypes.summaryTask) return null;
    final s = n.payload['summary'];
    if (s is! Map) return null;
    final newTasks = (s['new_tasks'] ?? 0) as int;
    final assigned = (s['assigned_inspections'] ?? 0) as int;
    final overdue = (s['overdue_tasks'] ?? 0) as int;
    return 'Новых: $newTasks, Назначенных: $assigned, Просроченных: $overdue';
  }

  static String _executorLabel(AppNotification n) {
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

class _HideReadToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _HideReadToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Скрыть прочитанные',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
        _NotificationsScreenState._summaryDescription(notification);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdueType || isHighPriority
              ? Colors.red.shade300
              : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (!notification.isRead)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
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
                  color: _NotificationsScreenState._statusColor(
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
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
    final executor = _NotificationsScreenState._executorLabel(n);
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
    final color = _NotificationsScreenState._statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
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
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
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
    final color = isOverdue ? Colors.red : Colors.grey.shade800;
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
