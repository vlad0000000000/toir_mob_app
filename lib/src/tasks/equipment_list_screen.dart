import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_scan_industry/src/utils/go_router_ext.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../design/app_constants.dart';
import '../widgets/empty_state.dart';
import 'tasks_filter.dart';

/// Перенесённый с экрана уведомлений фильтр. Сейчас спрятан,
/// при необходимости включить — поставить `_kShowTasksFilter = true`.
// ignore: prefer_const_declarations
final bool _kShowTasksFilter = false;

class EquipmentListScreen extends StatefulWidget {
  final bool isModal;
  final bool isProblems;

  const EquipmentListScreen(
      {super.key, this.isModal = false, this.isProblems = false});

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  TasksFilterState _filter = TasksFilterState();

  Future<void> _openFilter() async {
    final result = await showTasksFilterSheet(context, _filter);
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  List<Task> _filteredTasksFor(InventoryRecord equipment) {
    final all = GlobalState.dataProvider.getTasksForMachine(equipment.uuid);
    if (_filter.isEmpty) return all;
    return _filter.apply(all);
  }

  @override
  Widget build(BuildContext context) {
    final isProblems = widget.isProblems;
    final isModal = widget.isModal;
    Widget body = FutureBuilder<void>(
        future: GlobalState.syncMainOnce(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            var equipmentList = GlobalState.dataProvider.inventoryRecords;
            equipmentList = equipmentList
                .where((element) => _filteredTasksFor(element).length > 0)
                .toList();
            equipmentList.sort((a, b) {
              var ac = _filteredTasksFor(a).length == 0 ? 0 : 1;
              var bc = _filteredTasksFor(b).length == 0 ? 0 : 1;
              return bc.compareTo(ac);
            });
            if (equipmentList.length == 0) {
              return EmptyState(
                icon: isProblems
                    ? Icons.warehouse_outlined
                    : Icons.checklist_rounded,
                title: isProblems
                    ? 'Нет оборудования'
                    : 'Нет активных задач',
                hint: isProblems
                    ? 'Список оборудования пуст или ещё не загружен.'
                    : 'Отсканируйте QR-код оборудования, чтобы начать осмотр или открыть задачи.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMD,
                vertical: AppConstants.spacingMD,
              ),
              itemCount: equipmentList.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppConstants.spacingSM),
              itemBuilder: (context, index) {
                final equipment = equipmentList[index];
                final taskCount = _filteredTasksFor(equipment).length;
                return _EquipmentTile(
                  equipment: equipment,
                  taskCount: taskCount,
                  isProblems: isProblems,
                  onTap: () {
                    if (isProblems) {
                      GoRouter.of(context).clearStackAndNavigate(
                          '/qr_result_problems',
                          extra: equipment);
                    } else {
                      GoRouter.of(context).go('/details/${equipment.id}');
                    }
                  },
                );
              },
            );
          }
          return Center(
              child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 8,
            constraints: const BoxConstraints(minHeight: 128, minWidth: 128),
          ));
        });

    if (isModal) {
      return body;
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          if (_kShowTasksFilter)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TasksFilterButton(
                  activeCount: _filter.activeCount,
                  onTap: _openFilter,
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Карточка оборудования в списке: leading-иконка, имя, подзаголовок со
/// счётчиком задач, badge справа (или chevron в режиме «problems»).
class _EquipmentTile extends StatelessWidget {
  final InventoryRecord equipment;
  final int taskCount;
  final bool isProblems;
  final VoidCallback onTap;

  const _EquipmentTile({
    required this.equipment,
    required this.taskCount,
    required this.isProblems,
    required this.onTap,
  });

  String _pluralizeTasks(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n активная задача';
    if (mod10 >= 2 &&
        mod10 <= 4 &&
        (mod100 < 10 || mod100 >= 20)) {
      return '$n активные задачи';
    }
    return '$n активных задач';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasTasks = !isProblems && taskCount > 0;

    final subtitle = isProblems
        ? null
        : taskCount == 0
            ? 'Нет активных задач'
            : _pluralizeTasks(taskCount);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasTasks
                      ? cs.primaryContainer
                      : cs.surfaceContainerHigh,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: Icon(
                  Icons.precision_manufacturing_outlined,
                  color: hasTasks
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      equipment.name,
                      style: tt.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: hasTasks
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingSM),
              if (hasTasks)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    '$taskCount',
                    style: tt.labelMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
