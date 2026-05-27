import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app/src/utils/go_router_ext.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../src/widgets/square_button.dart';
import '../widgets/modal.dart';
import 'tasks_filter.dart';

/// Перенесённый с экрана уведомлений фильтр. Сейчас спрятан,
/// при необходимости включить — поставить `_kShowTasksFilter = true`.
// ignore: prefer_const_declarations
final bool _kShowTasksFilter = false;

// models.dart
class Equipment {
  final List<Checklist> checklists;
  final InventoryRecord machine;

  Equipment(this.machine, this.checklists);
}

class Checklist {
  final String period;
  final List<Task> tasks;
  bool isExpanded;

  Checklist(this.period, this.tasks, {this.isExpanded = false});
}

// Добавляем контроллер для управления выбором задач
class EquipmentDetailController {
  final ValueNotifier<List<Task>> _valueNotifier = ValueNotifier([]);

  ValueNotifier<List<Task>> get valueNotifier => _valueNotifier;

  List<Task> get value => _valueNotifier.value;

  set value(List<Task> newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }

  final Set<Task> selectedTasks = {};
  VoidCallback? onSelectionChanged;

  EquipmentDetailController({this.onSelectionChanged});

  void toggleTaskSelection(Task task) {
    if (selectedTasks.contains(task)) {
      selectedTasks.clear();
    } else {
      selectedTasks
        ..clear()
        ..add(task);
    }
    onSelectionChanged?.call();
    value = selectedTasks.toList();
  }

  void selectAll(List<Task> allTasks) {
    selectedTasks.clear();
    if (allTasks.isNotEmpty) {
      selectedTasks.add(allTasks.first);
      value = [allTasks.first];
    } else {
      value = [];
    }
    onSelectionChanged?.call();
  }

  void clearSelection() {
    selectedTasks.clear();
    value = [];
    onSelectionChanged?.call();
  }

  List<Task> getSelectedTasks() {
    return selectedTasks.toList();
  }
}

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
                .where((element) =>
                    _filteredTasksFor(element).length > 0)
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          'Нет задач',
                          style: const TextStyle(
                            // color: Colors.blue,
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                          title: Text(
                            '${equipment.name}',
                            style: const TextStyle(
                              // color: Colors.blue,
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          '${equipment.name} (нет задач)',
                          style: const TextStyle(
                            // color: Colors.blue,
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                        title: Text(
                          '${equipment.name} (${taskCount})',
                          style: const TextStyle(
                            // color: Colors.blue,
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
          // return body;
          return const Center(
              child: CircularProgressIndicator(
            color: Colors.black,
            strokeWidth: 8,
            constraints: BoxConstraints(minHeight: 128, minWidth: 128),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
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

// equipment_detail_screen.dart
// import 'package:flutter/material.dart';
// import 'models.dart';

final Map<String, Color> periodColors = {
  'Назначенные задачи': Colors.red,
  'Однократно': Colors.red,
  'Ежедневно (каждые 2.5 часа)': Colors.red,
  'Каждые 12 часов': Colors.red,
  'Ежедневно': Colors.red,
  'Еженедельно': Colors.yellow,
  '1 раз в неделю': Colors.yellow,
  "1 раз в 2 недели": Colors.orange,
  "Ежемесячно": Colors.green,
  "1 раз в месяц": Colors.green,
  '1 раз в 3 месяца': Colors.teal,
  '1 раз в 6 месяцев': Colors.blue,
  '1 раз в год': Colors.blueGrey,
  '1 раз в 2 года': Colors.grey,
  '1 раз в 3 года': Colors.grey,
  'Автоматический счетчик обслуживания': Colors.green,
};

class EquipmentDetailScreen extends StatefulWidget {
  final InventoryRecord machine;
  final bool isModal;
  final void Function(Task)? onTaskTap;
  final EquipmentDetailController? controller; // Добавляем контроллер

  const EquipmentDetailScreen({
    super.key,
    required this.machine,
    this.isModal = false,
    this.onTaskTap,
    this.controller, // Новый параметр для контроллера
  });

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  late EquipmentDetailController _selectionController;

  bool get _isSelectionMode => widget.controller != null;

  late Equipment equipment;

  @override
  void initState() {
    super.initState();
    equipment = createEquipment(widget.machine);
    // Используем переданный контроллер или создаем локальный
    _selectionController = widget.controller ?? EquipmentDetailController();
    _selectionController.onSelectionChanged = _handleSelectionChanged;
  }

  void _handleSelectionChanged() {
    if (mounted) setState(() {});
  }

  Equipment createEquipment(InventoryRecord machine) {
    List<Task> tasks =
        GlobalState.dataProvider.getTasksForMachine(machine.uuid);
    Map<String, List<Task>> byPeriod = {};
    var periodOrder = periodColors.keys.toList();
    for (var task in tasks) {
      var periodName = '';
      if (task.resultStatus == 'open') {
        periodName = 'Назначенные задачи';
      } else {
        periodName = task.periodicTask!.periodicityRuleDisplay;
      }
      if (periodName.length == 0) {
        continue;
      }
      if (!byPeriod.containsKey(periodName)) {
        byPeriod[periodName] = [];
      }
      byPeriod[periodName]!.add(task);
    }
    List<Checklist> checklists = [];
    for (var periodName in byPeriod.keys) {
      checklists.add(Checklist(periodName, byPeriod[periodName]!));
    }
    checklists.sort((a, b) =>
        periodOrder.indexOf(a.period).compareTo(periodOrder.indexOf(b.period)));
    return Equipment(machine, checklists);
  }

  Widget buildBody(Equipment equipment) {
    // Собираем все задачи для "Выбрать все"
    final allTasks =
        equipment.checklists.expand((checklist) => checklist.tasks).toList();

    Widget list = ListView.builder(
      itemCount: equipment.checklists.length + (widget.isModal ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == equipment.checklists.length) {
          return Row(
            children: [
              Expanded(
                  child: SquareButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text("Выбрать")))
            ],
          );
        }
        final checklist = equipment.checklists[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  decoration: BoxDecoration(
                    color: periodColors[checklist.period],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              ExpansionTile(
                shape: const Border(),
                title: Text(
                  " " + checklist.period + ' (${checklist.tasks.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    // fontSize: 18,
                  ),
                ),
                trailing: Icon(
                  checklist.isExpanded ? Icons.remove : Icons.add,
                  size: 28,
                ),
                childrenPadding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                children: checklist.tasks.map((task) {
                  return Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: task.resultStatus == "scheduled"
                        ? _buildTaskItem(task)
                        : _buildOpenTaskItem(task),
                  );
                }).toList(),
                onExpansionChanged: (expanded) {
                  setState(() {
                    checklist.isExpanded = expanded;
                  });
                },
              ),
            ],
          ),
        );
      },
    );

    return Column(
      spacing: 8,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            widget.machine.name,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
          ),
        ),
        SizedBox(
          height: 4,
        ),
        // Панель действий при множественном выборе
        if (_isSelectionMode && widget.isModal)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Row(
                //   children: [
                //     IconButton(
                //       icon: const Icon(Icons.check_box_outline_blank),
                //       onPressed: () => _selectionController.selectAll(allTasks),
                //       tooltip: 'Выбрать все',
                //     ),
                //     IconButton(
                //       icon: const Icon(Icons.check_box_outlined),
                //       onPressed: _selectionController.clearSelection,
                //       tooltip: 'Снять выделение',
                //     ),
                //   ],
                // ),
                Text(
                  // 'Выбрано: ${_selectionController.selectedTasks.length}',
                  'Выберите только одну задачу',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.cleaning_services),
                  onPressed: _selectionController.clearSelection,
                  tooltip: 'Снять выделение',
                ),
              ],
            ),
          ),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildTaskItem(Task task) {
    final isSelected =
        _isSelectionMode && _selectionController.selectedTasks.contains(task);

    final title = Text(
      task.periodicTask!.title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.blue,
      ),
    );

    final eyeIcon = task.periodicTask != null
        ? IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: () => _showPeriodicTaskCard(context, task),
            tooltip: 'Карточка периодической задачи',
          )
        : const SizedBox.shrink();

    if (widget.isModal && _isSelectionMode) {
      return InkWell(
        onTap: () => _selectionController.toggleTaskSelection(task),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[200]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: title),
              eyeIcon,
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(child: title),
          eyeIcon,
        ],
      ),
    );
  }

  void _showPeriodicTaskCard(BuildContext context, Task task) {
    final pt = task.periodicTask!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pt.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (pt.node != null && pt.node!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Узел:', pt.node!),
              ],
              if (pt.description != null && pt.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Описание:', pt.description!),
              ],
              const SizedBox(height: 8),
              // _buildDetailRow('Периодичность:', pt.periodicityRuleDisplay),
              // if (pt.nextDueAt != null)
              //   _buildDetailRow(
              //     'Следующий срок:',
              //     _formatDate(pt.nextDueAt!),
              //   ),
              // if (pt.lastRunAt != null)
              //   _buildDetailRow(
              //     'Последний запуск:',
              //     _formatDate(pt.lastRunAt!),
              //   ),
              if (pt.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Фото',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: pt.photos
                      .map(
                        (photo) => InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              barrierColor: Colors.black54,
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              isScrollControlled: true,
                              isDismissible: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => Modal(
                                child: SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.network(
                                              photo.url,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SquareButton(
                                                  onPressed: () =>
                                                      Navigator.of(context).pop(),
                                                  child: const Text('Закрыть'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Image.network(
                                photo.url,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SquareButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  Widget _buildOpenTaskItem(Task task) {
    final isSelected =
        _isSelectionMode && _selectionController.selectedTasks.contains(task);

    final title = Text(
      task.periodicTask?.title ?? 'Назначенная задача',
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.blue,
      ),
    );

    final eyeIcon = task.periodicTask != null
        ? IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: () => _showPeriodicTaskCard(context, task),
            tooltip: 'Карточка периодической задачи',
          )
        : const SizedBox.shrink();

    if (widget.isModal && _isSelectionMode) {
      return InkWell(
        onTap: () => _selectionController.toggleTaskSelection(task),
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[200]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: title),
              eyeIcon,
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(child: title),
          eyeIcon,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = buildBody(equipment);

    if (widget.isModal) {
      return body;
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: body,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// main.dart
// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import 'equipment_list_screen.dart';
// import 'equipment_detail_screen.dart';
// import 'models.dart';
