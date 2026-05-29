import 'package:flutter/material.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../src/widgets/square_button.dart';
import '../widgets/app_bottom_sheet.dart';
import 'task_models.dart';
import 'equipment_detail_controller.dart';

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
                    child: _buildTaskItem(task),
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
                Text(
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
                            showAppModalSheet(
                              context,
                              isDismissible: true,
                              enableDrag: true,
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
                                                      Navigator.of(context)
                                                          .pop(),
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
