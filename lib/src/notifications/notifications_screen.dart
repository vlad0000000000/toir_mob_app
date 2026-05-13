import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../model/inventory_record.dart';
import '../model/notification.dart';
import '../utils/go_router_ext.dart';
import 'notifications_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _DateRange { all, today, yesterday, week, month, custom }

const Map<_DateRange, String> _dateRangeLabels = {
  _DateRange.all: 'Все время',
  _DateRange.today: 'Сегодня',
  _DateRange.yesterday: 'Вчера',
  _DateRange.week: 'Неделя',
  _DateRange.month: 'Месяц',
  _DateRange.custom: 'Период',
};

const Map<String, String> _typeLabels = {
  NotificationTypes.assignedInspection: 'Назначение осмотра',
  NotificationTypes.newTask: 'Новая задача',
  NotificationTypes.overdueTask: 'Просроченная',
};

const Map<String, String> _statusLabels = {
  NotificationStatuses.newStatus: 'Новая',
  NotificationStatuses.viewed: 'Просмотрена',
  NotificationStatuses.completed: 'Выполнена',
  NotificationStatuses.overdue: 'Просрочена',
};

const Map<String, String> _priorityLabels = {
  'low': 'Низкий',
  'medium': 'Средний',
  'high': 'Высокий',
};

class _FilterState {
  Set<String> types;
  Set<String> statuses;
  String? equipmentUuid;
  String? priority;
  _DateRange dateRange;
  DateTimeRange? customRange;

  _FilterState({
    Set<String>? types,
    Set<String>? statuses,
    this.equipmentUuid,
    this.priority,
    this.dateRange = _DateRange.all,
    this.customRange,
  })  : types = types ?? <String>{},
        statuses = statuses ?? <String>{};

  _FilterState clone() => _FilterState(
        types: {...types},
        statuses: {...statuses},
        equipmentUuid: equipmentUuid,
        priority: priority,
        dateRange: dateRange,
        customRange: customRange,
      );

  int get activeCount {
    int c = 0;
    if (types.isNotEmpty) c++;
    if (statuses.isNotEmpty) c++;
    if (equipmentUuid != null) c++;
    if (priority != null) c++;
    if (dateRange != _DateRange.all) c++;
    return c;
  }

  bool get isEmpty => activeCount == 0;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsService _service = NotificationsService.instance;
  _FilterState _filters = _FilterState();
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _service.bootstrap();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _applyFilters() async {
    DateTime? from;
    DateTime? to;
    final now = DateTime.now();
    switch (_filters.dateRange) {
      case _DateRange.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case _DateRange.yesterday:
        from = DateTime(now.year, now.month, now.day - 1);
        to = DateTime(now.year, now.month, now.day);
        break;
      case _DateRange.week:
        from = now.subtract(const Duration(days: 7));
        break;
      case _DateRange.month:
        from = now.subtract(const Duration(days: 30));
        break;
      case _DateRange.custom:
        if (_filters.customRange != null) {
          from = _filters.customRange!.start;
          to = _filters.customRange!.end;
        }
        break;
      case _DateRange.all:
        break;
    }
    await _service.refreshList(
      types: _filters.types.isEmpty ? null : _filters.types.toList(),
      statuses: _filters.statuses.isEmpty ? null : _filters.statuses.toList(),
      equipmentUuid: _filters.equipmentUuid,
      priority: _filters.priority,
      createdFrom: from,
      createdTo: to,
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_FilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(initial: _filters.clone()),
    );
    if (result != null) {
      setState(() => _filters = result);
      await _applyFilters();
    }
  }

  void _removeFilter({
    String? type,
    String? status,
    bool clearEquipment = false,
    bool clearPriority = false,
    bool clearDate = false,
  }) {
    setState(() {
      if (type != null) _filters.types.remove(type);
      if (status != null) _filters.statuses.remove(status);
      if (clearEquipment) _filters.equipmentUuid = null;
      if (clearPriority) _filters.priority = null;
      if (clearDate) {
        _filters.dateRange = _DateRange.all;
        _filters.customRange = null;
      }
    });
    _applyFilters();
  }

  void _resetAll() {
    setState(() => _filters = _FilterState());
    _applyFilters();
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
            onPressed: _applyFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          _FiltersHeader(
            filters: _filters,
            onOpenSheet: _openFilterSheet,
            onRemove: _removeFilter,
            onResetAll: _resetAll,
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _service.isLoading,
              builder: (context, loading, _) {
                return ValueListenableBuilder<List<AppNotification>>(
                  valueListenable: _service.notifications,
                  builder: (context, items, __) {
                    if (loading && items.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (items.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: _applyFilters,
                        child: ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    Icon(Icons.notifications_off_outlined,
                                        size: 56,
                                        color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      _filters.isEmpty
                                          ? 'Уведомлений нет'
                                          : 'Нет уведомлений по выбранным фильтрам',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    if (!_filters.isEmpty) ...[
                                      const SizedBox(height: 12),
                                      TextButton.icon(
                                        onPressed: _resetAll,
                                        icon: const Icon(Icons.refresh),
                                        label:
                                            const Text('Сбросить фильтры'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _applyFilters,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final n = items[i];
                          return NotificationCard(
                            notification: n,
                            onTap: () => _onTap(n),
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

    final company = GlobalState.dataProvider.company;
    final allowWithoutQr = company?.allowRequestsWithoutQr ?? false;
    final canOpen = n.canOpenTarget && allowWithoutQr;

    if (canOpen && n.equipmentUuid != null) {
      final records = GlobalState.dataProvider.inventoryRecords
          .where((r) => r.uuid == n.equipmentUuid)
          .toList();
      if (records.isNotEmpty) {
        GoRouter.of(context)
            .pushReplacement('/qr_result_problems', extra: records.first);
        return;
      }
    }
    _showDetail(n);
  }

  void _showDetail(AppNotification n) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
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
                if (n.description.isNotEmpty) ...[
                  Text(n.description),
                  const SizedBox(height: 8),
                ],
                _statusChip(n),
                const SizedBox(height: 8),
                if (n.priorityDisplay != null && n.priorityDisplay!.isNotEmpty)
                  Text('Приоритет: ${n.priorityDisplay}'),
                const SizedBox(height: 4),
                Text(_executorLabel(n)),
                const SizedBox(height: 4),
                Text('Создано: ${_formatDateTime(n.createdAt)}'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
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

  static String _executorLabel(AppNotification n) {
    if (n.status == NotificationStatuses.completed) {
      if (n.responsibleUserFullname != null &&
          n.responsibleUserFullname!.isNotEmpty) {
        return 'Исполнитель: ${n.responsibleUserFullname}';
      }
    }
    if (n.notificationType == NotificationTypes.assignedInspection) {
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

class _FiltersHeader extends StatelessWidget {
  final _FilterState filters;
  final VoidCallback onOpenSheet;
  final VoidCallback onResetAll;
  final void Function({
    String? type,
    String? status,
    bool clearEquipment,
    bool clearPriority,
    bool clearDate,
  }) onRemove;

  const _FiltersHeader({
    required this.filters,
    required this.onOpenSheet,
    required this.onResetAll,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = filters.activeCount;
    final hasActive = activeCount > 0;
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _FilterMainButton(
                  count: activeCount,
                  onTap: onOpenSheet,
                ),
                const SizedBox(width: 8),
                if (hasActive)
                  TextButton.icon(
                    onPressed: onResetAll,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Сбросить'),
                  ),
              ],
            ),
          ),
          if (hasActive)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _activeChips(context),
                ),
              ),
            ),
          Container(height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  List<Widget> _activeChips(BuildContext context) {
    final chips = <Widget>[];
    if (filters.dateRange != _DateRange.all) {
      String label = _dateRangeLabels[filters.dateRange] ?? 'Период';
      if (filters.dateRange == _DateRange.custom &&
          filters.customRange != null) {
        final f = DateFormat('dd.MM');
        label =
            '${f.format(filters.customRange!.start)} – ${f.format(filters.customRange!.end)}';
      }
      chips.add(_ActiveFilterChip(
        icon: Icons.calendar_today,
        label: label,
        onRemove: () => onRemove(clearDate: true),
      ));
    }
    for (final t in filters.types) {
      chips.add(_ActiveFilterChip(
        icon: Icons.label_outline,
        label: _typeLabels[t] ?? t,
        onRemove: () => onRemove(type: t),
      ));
    }
    for (final s in filters.statuses) {
      chips.add(_ActiveFilterChip(
        icon: Icons.flag_outlined,
        label: _statusLabels[s] ?? s,
        onRemove: () => onRemove(status: s),
      ));
    }
    if (filters.priority != null) {
      chips.add(_ActiveFilterChip(
        icon: Icons.priority_high,
        label: _priorityLabels[filters.priority!] ?? filters.priority!,
        onRemove: () => onRemove(clearPriority: true),
      ));
    }
    if (filters.equipmentUuid != null) {
      final record = GlobalState.dataProvider.inventoryRecords
          .where((r) => r.uuid == filters.equipmentUuid)
          .toList();
      final name =
          record.isNotEmpty ? record.first.name : 'Оборудование';
      chips.add(_ActiveFilterChip(
        icon: Icons.precision_manufacturing_outlined,
        label: name,
        onRemove: () => onRemove(clearEquipment: true),
      ));
    }
    return chips;
  }
}

class _FilterMainButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterMainButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: active ? Colors.black : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: 18,
                color: active ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 8),
              Text(
                'Фильтры',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.black87,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 14, color: Colors.blue.shade700),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final _FilterState initial;

  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _FilterState _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Фильтры',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _draft = _FilterState());
                      },
                      child: const Text('Сбросить все'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _SectionHeader(
                        icon: Icons.calendar_today, title: 'Период'),
                    const SizedBox(height: 8),
                    _DateRangeSelector(
                      value: _draft.dateRange,
                      customRange: _draft.customRange,
                      onChanged: (range, custom) {
                        setState(() {
                          _draft.dateRange = range;
                          if (custom != null) _draft.customRange = custom;
                          if (range != _DateRange.custom) {
                            _draft.customRange = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                        icon: Icons.label_outline, title: 'Тип уведомления'),
                    const SizedBox(height: 8),
                    _MultiChoiceChips(
                      options: _typeLabels,
                      selected: _draft.types,
                      onChanged: (next) =>
                          setState(() => _draft.types = next),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                        icon: Icons.flag_outlined, title: 'Статус'),
                    const SizedBox(height: 8),
                    _MultiChoiceChips(
                      options: _statusLabels,
                      selected: _draft.statuses,
                      onChanged: (next) =>
                          setState(() => _draft.statuses = next),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                        icon: Icons.priority_high, title: 'Приоритет'),
                    const SizedBox(height: 8),
                    _SingleChoiceChips(
                      options: _priorityLabels,
                      selected: _draft.priority,
                      onChanged: (v) => setState(() => _draft.priority = v),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                        icon: Icons.precision_manufacturing_outlined,
                        title: 'Оборудование'),
                    const SizedBox(height: 8),
                    _EquipmentPickerTile(
                      selectedUuid: _draft.equipmentUuid,
                      onChanged: (uuid) =>
                          setState(() => _draft.equipmentUuid = uuid),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, 12 + mq.padding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(_draft),
                        child: Text(
                          _draft.activeCount == 0
                              ? 'Показать все'
                              : 'Применить (${_draft.activeCount})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MultiChoiceChips extends StatelessWidget {
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _MultiChoiceChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final isSelected = selected.contains(e.key);
        return _PillChip(
          label: e.value,
          selected: isSelected,
          onTap: () {
            final next = {...selected};
            if (isSelected) {
              next.remove(e.key);
            } else {
              next.add(e.key);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}

class _SingleChoiceChips extends StatelessWidget {
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _SingleChoiceChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final isSelected = selected == e.key;
        return _PillChip(
          label: e.value,
          selected: isSelected,
          onTap: () {
            onChanged(isSelected ? null : e.key);
          },
        );
      }).toList(),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.black : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.black : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  final _DateRange value;
  final DateTimeRange? customRange;
  final void Function(_DateRange range, DateTimeRange? custom) onChanged;

  const _DateRangeSelector({
    required this.value,
    required this.customRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      _DateRange.all,
      _DateRange.today,
      _DateRange.yesterday,
      _DateRange.week,
      _DateRange.month,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in presets)
              _PillChip(
                label: _dateRangeLabels[r]!,
                selected: value == r,
                onTap: () => onChanged(r, null),
              ),
            _PillChip(
              label: value == _DateRange.custom && customRange != null
                  ? '${DateFormat('dd.MM').format(customRange!.start)} – ${DateFormat('dd.MM').format(customRange!.end)}'
                  : 'Произвольный…',
              selected: value == _DateRange.custom,
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate:
                      DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: customRange,
                );
                if (picked != null) {
                  onChanged(_DateRange.custom, picked);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _EquipmentPickerTile extends StatelessWidget {
  final String? selectedUuid;
  final ValueChanged<String?> onChanged;

  const _EquipmentPickerTile({
    required this.selectedUuid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final records = GlobalState.dataProvider.inventoryRecords;
    final matching = selectedUuid == null
        ? const <InventoryRecord>[]
        : records.where((r) => r.uuid == selectedUuid).toList();
    final selected = matching.isEmpty ? null : matching.first;
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await _showEquipmentPicker(context, selectedUuid);
          if (picked == null && selectedUuid != null) {
            onChanged(null);
          } else if (picked != null) {
            if (picked == '__clear__') {
              onChanged(null);
            } else {
              onChanged(picked);
            }
          }
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search,
                  size: 20, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selected?.name ?? 'Любое оборудование',
                  style: TextStyle(
                    fontSize: 14,
                    color: selected != null
                        ? Colors.black87
                        : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected != null)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 18, color: Colors.grey.shade600),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    size: 20, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showEquipmentPicker(
      BuildContext context, String? currentUuid) async {
    final records = GlobalState.dataProvider.inventoryRecords;
    final searchCtrl = TextEditingController();
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final filtered = query.isEmpty
                ? records
                : records
                    .where((r) =>
                        r.name.toLowerCase().contains(query.toLowerCase()))
                    .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            16, 12, 16, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Выберите оборудование',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: TextField(
                          controller: searchCtrl,
                          onChanged: (v) => setSt(() => query = v),
                          decoration: InputDecoration(
                            hintText: 'Поиск…',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ListTile(
                        leading: Icon(Icons.clear_all,
                            color: Colors.grey.shade700),
                        title: const Text('Любое оборудование'),
                        selected: currentUuid == null,
                        onTap: () =>
                            Navigator.of(ctx).pop('__clear__'),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final r = filtered[i];
                            return ListTile(
                              title: Text(r.name),
                              selected: r.uuid == currentUuid,
                              trailing: r.uuid == currentUuid
                                  ? const Icon(Icons.check,
                                      color: Colors.black)
                                  : null,
                              onTap: () =>
                                  Navigator.of(ctx).pop(r.uuid),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
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
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdueType ? Colors.red.shade300 : Colors.grey.shade300,
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
              if (notification.description.isNotEmpty) ...[
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
                  _StatusBadge(status: notification.status),
                  const SizedBox(width: 8),
                  if (notification.notificationType ==
                          NotificationTypes.assignedInspection &&
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
    final executor = _NotificationsScreenState._executorLabel(n);
    if (n.notificationType == NotificationTypes.assignedInspection) {
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
