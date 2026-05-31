import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../model/inventory_record.dart';
import 'tasks_filter_state.dart';

const Map<TasksDateRange, String> _dateRangeLabels = {
  TasksDateRange.all: 'Все время',
  TasksDateRange.today: 'Сегодня',
  TasksDateRange.yesterday: 'Вчера',
  TasksDateRange.week: 'Неделя',
  TasksDateRange.month: 'Месяц',
  TasksDateRange.custom: 'Период',
};

/// Открывает sheet с фильтрами задач. Аналогичный набор полей, что
/// был на экране уведомлений, но применяется к локальному списку задач.
Future<TasksFilterState?> showTasksFilterSheet(
  BuildContext context,
  TasksFilterState initial,
) {
  return showModalBottomSheet<TasksFilterState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TasksFilterSheet(initial: initial.clone()),
  );
}

class TasksFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const TasksFilterButton({
    super.key,
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Material(
      color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHigh,
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
                color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Фильтры',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (activeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    activeCount.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
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

class _TasksFilterSheet extends StatefulWidget {
  final TasksFilterState initial;

  const _TasksFilterSheet({required this.initial});

  @override
  State<_TasksFilterSheet> createState() => _TasksFilterSheetState();
}

class _TasksFilterSheetState extends State<_TasksFilterSheet> {
  late TasksFilterState _draft;

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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
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
                        setState(() => _draft = TasksFilterState());
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
                    const _SectionHeader(
                        icon: Icons.calendar_today, title: 'Период'),
                    const SizedBox(height: 8),
                    _DateRangeSelector(
                      value: _draft.dateRange,
                      customRange: _draft.customRange,
                      onChanged: (range, custom) {
                        setState(() {
                          _draft.dateRange = range;
                          if (custom != null) _draft.customRange = custom;
                          if (range != TasksDateRange.custom) {
                            _draft.customRange = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    const _SectionHeader(
                        icon: Icons.flag_outlined, title: 'Статус'),
                    const SizedBox(height: 8),
                    _MultiChoiceChips(
                      options: tasksStatusLabels,
                      selected: _draft.statuses,
                      onChanged: (next) =>
                          setState(() => _draft.statuses = next),
                    ),
                    const SizedBox(height: 20),
                    const _SectionHeader(
                        icon: Icons.priority_high, title: 'Приоритет'),
                    const SizedBox(height: 8),
                    _SingleChoiceChips(
                      options: tasksPriorityLabels,
                      selected: _draft.priority,
                      onChanged: (v) => setState(() => _draft.priority = v),
                    ),
                    const SizedBox(height: 20),
                    const _SectionHeader(
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
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                      top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
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
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHigh,
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
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check,
                    size: 14,
                    color: Theme.of(context).colorScheme.onPrimary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
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
  final TasksDateRange value;
  final DateTimeRange? customRange;
  final void Function(TasksDateRange range, DateTimeRange? custom) onChanged;

  const _DateRangeSelector({
    required this.value,
    required this.customRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      TasksDateRange.all,
      TasksDateRange.today,
      TasksDateRange.yesterday,
      TasksDateRange.week,
      TasksDateRange.month,
    ];
    return Wrap(
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
          label: value == TasksDateRange.custom && customRange != null
              ? '${DateFormat('dd.MM').format(customRange!.start)} – ${DateFormat('dd.MM').format(customRange!.end)}'
              : 'Произвольный…',
          selected: value == TasksDateRange.custom,
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate:
                  DateTime.now().add(const Duration(days: 365)),
              initialDateRange: customRange,
            );
            if (picked != null) {
              onChanged(TasksDateRange.custom, picked);
            }
          },
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
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                  size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selected?.name ?? 'Любое оборудование',
                  style: TextStyle(
                    fontSize: 14,
                    color: selected != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
                        size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outline,
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
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                                  ? Icon(Icons.check,
                                      color: Theme.of(context).colorScheme.primary)
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
