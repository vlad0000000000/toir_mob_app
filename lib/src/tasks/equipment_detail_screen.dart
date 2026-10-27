import 'dart:async';

import 'package:flutter/material.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../utils/search_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sheet.dart';
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
///
/// Задачи, возвращённые на доработку, — ещё выше ППР: их ждёт проверяющий.
int _periodOrder(String period) {
  if (period == ReworkStrings.group) return -2;
  return period.startsWith(kPprGroupName)
      ? -1
      : _periodOrderNames.indexOf(period);
}

/// Цвет полосы группы доработки — тот же предупреждающий, что у пометки.
const Color reworkGroupColor = Color(0xFFEA580C);

/// Цвет полосы группы — с той же поправкой на именованные группы ППР.
Color? periodColorFor(String period) {
  if (period == ReworkStrings.group) return reworkGroupColor;
  return period.startsWith(kPprGroupName)
      ? pprGroupColor
      : periodColors[period];
}

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

  // ── Поиск и фильтр ─────────────────────────────────────────────────────
  // Только на отдельном экране «Задачи», не в окне выбора задачи при скане
  // QR. Разовые: сбрасываются при уходе с экрана, это не настройка. Фильтр
  // только прячет задачи — отправка осмотра, скан и доработка работают как
  // раньше.

  final _searchController = TextEditingController();

  /// Запрос, по которому отобраны задачи, — после паузы в наборе.
  String _query = '';
  Timer? _searchDebounce;
  static const Duration _searchDelay = Duration(milliseconds: 250);

  /// Выбранные чипы «Периодичность» — ключи [_filterKeyOf].
  Set<String> _groups = const {};

  /// Свёрнутость групп, пока действуют поиск или фильтр: найденное
  /// показываем раскрытым, но обходчик может группу свернуть.
  final Map<String, bool> _filteredExpanded = {};

  bool get _isFiltering => _query.trim().isNotEmpty || _groups.isNotEmpty;

  @override
  void initState() {
    super.initState();
    equipment = createEquipment(widget.machine);
    // Используем переданный контроллер или создаем локальный
    _selectionController = widget.controller ?? EquipmentDetailController();
    _selectionController.onSelectionChanged = _handleSelectionChanged;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() => _query = '');
  }

  /// Значение чипа «Периодичность» для группы: все группы ППР («ППР ·
  /// Октябрьский ППР» и прочие) — одним чипом «ППР», остальные — своим
  /// названием, включая «На доработку» и «Назначенные задачи».
  static String _filterKeyOf(String period) =>
      period.startsWith(kPprGroupName) ? TaskFilterStrings.ppr : period;

  /// Варианты чипов — группы этого оборудования, в порядке экрана. Правила
  /// периодичности, которых у оборудования нет, не показываем: они всегда
  /// давали бы «Ничего не найдено».
  Map<String, String> get _groupOptions => {
        for (final checklist in equipment.checklists)
          _filterKeyOf(checklist.period): _filterKeyOf(checklist.period),
      };

  /// Задача подходит под запрос — по названию или узлу, без учёта регистра
  /// и «ё/е». [query] — уже из [normalizeSearchText].
  static bool _taskMatches(Task task, String query) {
    if (query.isEmpty) return true;
    final periodic = task.periodicTask;
    for (final field in [
      periodic?.title ?? 'Назначенная задача',
      periodic?.node,
    ]) {
      if (field != null && normalizeSearchText(field).contains(query)) {
        return true;
      }
    }
    return false;
  }

  /// Группы после поиска и фильтра: только с найденными задачами, счётчик —
  /// по найденным. Одна функция и для экрана, и для «Показать N задач».
  List<Checklist> _filteredChecklists(Set<String> groups, String query) {
    final normalized = normalizeSearchText(query);
    if (groups.isEmpty && normalized.isEmpty) return equipment.checklists;
    final result = <Checklist>[];
    for (final checklist in equipment.checklists) {
      if (groups.isNotEmpty &&
          !groups.contains(_filterKeyOf(checklist.period))) {
        continue;
      }
      final tasks = [
        for (final task in checklist.tasks)
          if (_taskMatches(task, normalized)) task,
      ];
      if (tasks.isEmpty) continue;
      result.add(Checklist(
        checklist.period,
        tasks,
        isExpanded: _filteredExpanded[checklist.period] ?? true,
      ));
    }
    return result;
  }

  /// Применяет набранный текст, не дожидаясь паузы. Перед открытием листа:
  /// иначе, открытый раньше 250 мс, он считал бы «Показать N задач» по
  /// прежнему запросу, а экран после закрытия — по новому.
  void _applySearchNow() {
    _searchDebounce?.cancel();
    final text = _searchController.text;
    if (_query != text) setState(() => _query = text);
  }

  Future<void> _openFilter() async {
    _applySearchNow();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TaskFilterSheet(
        options: _groupOptions,
        initial: _groups,
        countFor: (groups) => _filteredChecklists(groups, _query)
            .fold(0, (sum, checklist) => sum + checklist.tasks.length),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _groups = result);
  }

  void _resetFilters() => setState(() => _groups = const {});

  Equipment createEquipment(InventoryRecord machine) {
    List<Task> tasks =
        GlobalState.dataProvider.getTasksForMachine(machine.uuid);
    Map<String, List<Task>> byPeriod = {};
    for (var task in tasks) {
      var periodName = '';
      final periodicTask = task.periodicTask;
      final ppr = GlobalState.dataProvider.pprForTask(task);
      if (task.isReturnedForRework) {
        // Возвращённая на доработку — своей группой, независимо от ППР и
        // периодичности: она уже выполнялась, и ждут её исправления.
        periodName = ReworkStrings.group;
      } else if (ppr != null) {
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
    final filtering = !widget.isModal && _isFiltering;
    // Поиск и фильтр сняты — забываем, что сворачивали среди найденного:
    // следующий поиск снова покажет найденное раскрытым.
    if (!filtering) _filteredExpanded.clear();
    final checklists =
        filtering ? _filteredChecklists(_groups, _query) : equipment.checklists;

    Widget list = ListView.builder(
      itemCount: checklists.length + (widget.isModal ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == checklists.length) {
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
        final checklist = checklists[index];

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
                  // Ключ меняется при включении и снятии поиска: найденные
                  // группы открываются раскрытыми, а после очистки поиска
                  // возвращается прежняя свёрнутость.
                  key: ValueKey('${checklist.period}|$filtering'),
                  initiallyExpanded: checklist.isExpanded,
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
                      // Отобранные группы — копии, пересоздаются на каждом
                      // кадре: свёрнутость храним отдельно.
                      if (filtering) {
                        _filteredExpanded[checklist.period] = expanded;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    // Поиск ничего не нашёл — вместо списка пустое состояние, название
    // оборудования над ним остаётся.
    if (filtering && checklists.isEmpty) {
      list = EmptyState(
        icon: Icons.search_off_rounded,
        title: TaskFilterStrings.nothingFoundTitle,
        hint: TaskFilterStrings.nothingFoundHint,
        // Без фильтра сбрасывать нечего — запрос стирают крестиком в поле.
        action: _groups.isEmpty
            ? null
            : ElevatedButton(
                onPressed: _resetFilters,
                child: const Text(FilterStrings.resetFilters),
              ),
      );
    }

    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        if (!widget.isModal)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              0,
            ),
            child: SearchFilterBar(
              controller: _searchController,
              hint: TaskFilterStrings.searchHint,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              activeCount: _groups.length,
              onFilter: _openFilter,
            ),
          ),
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

    final scopeLabel = GlobalState.dataProvider.taskScopeLabelFor(task);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.periodicTask?.title ?? 'Назначенная задача',
          style: tt.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        if (scopeLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            scopeLabel,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        // Задача и так в группе «На доработку», а причина — в карточке по
        // кнопке «i». Строкой она остаётся, только если карточки нет: у
        // задачи без периодической задачи кнопки «i» не бывает.
        if (task.isReturnedForRework && task.periodicTask == null) ...[
          const SizedBox(height: 2),
          Text(
            [
              ReworkStrings.badge,
              if ((task.access?.returnComment ?? '').isNotEmpty)
                ReworkStrings.reason(task.access!.returnComment!),
            ].join(' · '),
            style: tt.bodySmall?.copyWith(
              color: cs.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    final eyeIcon = task.periodicTask != null
        ? IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            visualDensity: VisualDensity.compact,
            color: cs.onSurfaceVariant,
            onPressed: () => showPeriodicTaskCard(
              context,
              task.periodicTask!,
              usage: task.sparePartUsage,
              rework: task.isReturnedForRework ? task.access : null,
            ),
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

/// Лист «Фильтры» экрана задач оборудования: один раздел «Периодичность».
/// Возвращает выбранные группы.
class _TaskFilterSheet extends StatefulWidget {
  /// Группы этого оборудования, в порядке экрана.
  final Map<String, String> options;
  final Set<String> initial;

  /// Сколько задач покажет экран при выбранных группах — с его поиском.
  final int Function(Set<String> groups) countFor;

  const _TaskFilterSheet({
    required this.options,
    required this.initial,
    required this.countFor,
  });

  @override
  State<_TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<_TaskFilterSheet> {
  late Set<String> _draft = widget.initial;
  late int _count = widget.countFor(_draft);

  /// Сколько раз нажали «Сбросить» — в ключе раздела: сброс сворачивает
  /// раскрытое «Ещё N».
  int _resets = 0;

  void _update(Set<String> next) {
    setState(() {
      _draft = next;
      _count = widget.countFor(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheet(
      onReset: _draft.isEmpty
          ? null
          : () {
              _resets++;
              _update(const {});
            },
      resultCount: _count,
      resultLabel: TaskFilterStrings.showResults,
      onApply: () => Navigator.of(context).pop(_draft),
      children: [
        FilterSection(
          key: ValueKey('periodicity#$_resets'),
          label: TaskFilterStrings.labelPeriodicity,
          count: _draft.length,
          child: FilterChipGroup(
            options: widget.options,
            selected: _draft,
            onChanged: _update,
          ),
        ),
      ],
    );
  }
}
