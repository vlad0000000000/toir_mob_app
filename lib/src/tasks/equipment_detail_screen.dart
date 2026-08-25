import 'package:flutter/material.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../design/app_constants.dart';
import 'task_models.dart';
import 'equipment_detail_controller.dart';
import 'periodic_task_card.dart';

/// Имя группы ППР. Осмотры периодических задач, входящих в актуальный ППР,
/// собираются под ним и показываются в самом верху списка.
const String kPprGroupName = 'ППР';

/// Цвет раздела ППР — тот же на экране задач оборудования и на экране ППР.
const Color pprGroupColor = Colors.deepPurple;

final Map<String, Color> periodColors = {
  kPprGroupName: pprGroupColor,
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

final List<String> _periodOrderNames = periodColors.keys.toList();

/// Порядок групп в списке. Группы ППР («ППР» и «ППР · Название») всегда
/// наверху: имена конкретных ППР заранее не известны и в [periodColors] их нет.
int _periodOrder(String period) =>
    period.startsWith(kPprGroupName) ? -1 : _periodOrderNames.indexOf(period);

/// Цвет полосы группы — с той же поправкой на именованные группы ППР.
Color? periodColorFor(String period) =>
    period.startsWith(kPprGroupName) ? pprGroupColor : periodColors[period];

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

  /// Подсказку «Выберите только одну задачу» пользователь может закрыть
  /// крестиком — до следующего открытия окна выбора задач.
  bool _hintHidden = false;

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
    for (var task in tasks) {
      var periodName = '';
      final periodicTask = task.periodicTask;
      final ppr = GlobalState.dataProvider.pprForTask(task);
      if (ppr != null) {
        // Осмотр входит в состав актуального ППР — выносим его в отдельную
        // группу вне зависимости от статуса. У ППР может не быть названия,
        // тогда группа называется просто «ППР».
        periodName = ppr.groupTitle;
      } else if (task.resultStatus == 'open') {
        periodName = 'Назначенные задачи';
      } else {
        periodName = periodicTask!.periodicityRuleDisplay;
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
    checklists.sort((a, b) {
      final byOrder = _periodOrder(a.period).compareTo(_periodOrder(b.period));
      if (byOrder != 0) return byOrder;
      return a.period.compareTo(b.period);
    });
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
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  color: periodColorFor(checklist.period),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
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
        if (_isSelectionMode && widget.isModal && !_hintHidden)
          _buildSelectionHint(
            context,
            _selectionController.allowMultiSelect
                ? 'Можно выбрать несколько задач. Фото и комментарий будут '
                    'доступны только при выборе одной задачи.'
                : 'Выберите только одну задачу',
          ),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildSelectionHint(BuildContext context, String hintText) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
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
          Icon(Icons.info_outline_rounded, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hintText,
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
            // Крестик закрывает саму подсказку: выделение снимается
            // повторным тапом по задаче, а «X» на сообщении читается
            // как «скрыть сообщение».
            onPressed: () => setState(() => _hintHidden = true),
            tooltip: 'Скрыть подсказку',
          ),
        ],
      ),
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
            onPressed: () => showPeriodicTaskCard(context, task.periodicTask!),
            tooltip: 'Карточка периодической задачи',
          )
        : const SizedBox.shrink();

    final selectable = widget.isModal && _isSelectionMode;

    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingSM),
      child: Material(
        color: isSelected ? cs.primaryContainer : cs.surfaceContainerLow,
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
}
