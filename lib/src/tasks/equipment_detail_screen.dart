import 'package:flutter/material.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../widgets/app_bottom_sheet.dart';
import '../design/app_constants.dart';
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
          return Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Выбрать'),
              ),
            ),
          );
        }
        final checklist = equipment.checklists[index];

        final tt = Theme.of(context).textTheme;
        return Card(
          margin: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD,
              vertical: AppConstants.spacingSM / 2 + 2),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: periodColors[checklist.period],
              ),
              Expanded(
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingMD),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          checklist.period,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                        ),
                        child: Text(
                          '${checklist.tasks.length}',
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: AnimatedRotation(
                    turns: checklist.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                  childrenPadding: const EdgeInsets.only(
                    left: AppConstants.spacingMD,
                    right: AppConstants.spacingMD,
                    bottom: AppConstants.spacingMD,
                  ),
                  children: checklist.tasks.map(_buildTaskItem).toList(),
                  onExpansionChanged: (expanded) {
                    setState(() {
                      checklist.isExpanded = expanded;
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingLG,
              AppConstants.spacingMD,
              AppConstants.spacingLG,
              AppConstants.spacingSM),
          child: Text(
            widget.machine.name,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
        if (_isSelectionMode && widget.isModal)
          Container(
            margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMD,
                vertical: AppConstants.spacingSM),
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMD,
                vertical: AppConstants.spacingSM),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Выберите только одну задачу',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.clear_rounded),
                  color: cs.onPrimaryContainer,
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected =
        _isSelectionMode && _selectionController.selectedTasks.contains(task);

    final title = Text(
      task.periodicTask?.title ?? 'Назначенная задача',
      style: tt.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
    );

    final eyeIcon = task.periodicTask != null
        ? IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            visualDensity: VisualDensity.compact,
            color: cs.onSurfaceVariant,
            onPressed: () => _showPeriodicTaskCard(context, task),
            tooltip: 'Карточка периодической задачи',
          )
        : const SizedBox.shrink();

    final selectable = widget.isModal && _isSelectionMode;

    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingSM),
      child: Material(
        color: isSelected ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          side: BorderSide(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selectable
              ? () => _selectionController.toggleTaskSelection(task)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                AppConstants.spacingMD - 2,
                AppConstants.spacingSM,
                AppConstants.spacingMD - 2),
            child: Row(
              children: [
                if (selectable) ...[
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: AppConstants.spacingMD),
                ],
                Expanded(child: title),
                eyeIcon,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPeriodicTaskCard(BuildContext context, Task task) {
    final pt = task.periodicTask!;
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              0,
              AppConstants.spacingMD,
              AppConstants.spacingMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pt.title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
                Text(
                  'ФОТО',
                  style: tt.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
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
                                      horizontal: AppConstants.spacingMD,
                                      vertical: AppConstants.spacingSM,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(AppConstants.radiusMD),
                                            child: Image.network(
                                              photo.url,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                            height: AppConstants.spacingSM),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 48,
                                          child: FilledButton.tonal(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('Закрыть'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
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
              const SizedBox(height: AppConstants.spacingLG),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.replaceAll(':', '').toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: tt.bodyMedium),
        ],
      ),
    );
  }
}
