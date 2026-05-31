import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_scan_industry/src/utils/go_router_ext.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../design/app_constants.dart';
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
              Widget list = ListView.builder(
                itemCount: 1,
                itemBuilder: (context, index) {
                  return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                      ),
                      child: ListTile(
                        title: Text(
                          'Нет задач',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ));
                },
              );
              return list;
            }
            Widget list = ListView.builder(
              itemCount: equipmentList.length,
              itemBuilder: (context, index) {
                final equipment = equipmentList[index];
                var taskCount = _filteredTasksFor(equipment).length;
                if (isProblems) {
                  return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                      ),
                      child: ListTile(
                          title: Text(
                            '${equipment.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () {
                            if (isProblems) {
                              GoRouter.of(context).clearStackAndNavigate(
                                  '/qr_result_problems',
                                  extra: equipment);
                            } else {
                              GoRouter.of(context)
                                  .go('/details/${equipment.id}');
                            }
                          }));
                }
                if (taskCount == 0) {
                  return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                      ),
                      child: ListTile(
                        title: Text(
                          '${equipment.name} (нет задач)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ));
                }
                return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: ListTile(
                        title: Text(
                          '${equipment.name} (${taskCount})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          if (isProblems) {
                            GoRouter.of(context).clearStackAndNavigate(
                                '/qr_result_problems',
                                extra: equipment);
                          } else {
                            GoRouter.of(context).go('/details/${equipment.id}');
                          }
                        }));
              },
            );
            return list;
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
