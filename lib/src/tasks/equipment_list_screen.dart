import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../utils/search_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_controls.dart';
import '../widgets/filter_sheet.dart';
import 'equipment_filter.dart';

/// Список оборудования — в двух режимах с одним заголовком «Оборудование»:
///
/// * «Задачи» (`/tasks`) — оборудование с активными задачами и их число;
/// * «Осмотр оборудования или ТМЦ» (`/problems`, [isProblems]) — весь
///   справочник, выбор объекта для осмотра.
///
/// В обоих — поиск по названию, модели и серийному номеру и лист фильтров
/// (местоположение, состояние). Область «Моё подразделение / Все
/// подразделения» и «Задачи: Все / С активными» — только в справочнике: в
/// «Задачах» список и так состоит из работы обходчика, которую ему выдал
/// сервер, и прятать её по подразделению оборудования нельзя.
///
/// Отбор локальный, по кэшу: работает и без сети.
class EquipmentListScreen extends StatefulWidget {
  final bool isModal;
  final bool isProblems;

  const EquipmentListScreen(
      {super.key, this.isModal = false, this.isProblems = false});

  /// Забывает запомненные фильтры — при выходе из аккаунта: помещения и
  /// состояния прошлого пользователя (а то и другой компании) следующему
  /// дали бы «Ничего не найдено».
  static void forgetFilters() => _EquipmentListScreenState._lastFilters.clear();

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  /// Фильтр переживает уход с экрана в пределах запуска — как фильтр
  /// справочника ЗИП. У каждого режима свой: в «Задачах» нет области и
  /// раздела задач. Поисковый запрос сюда не входит: его набирают ради
  /// одной единицы, и восстановленный текст прятал бы список при следующем
  /// заходе.
  static final Map<bool, EquipmentFilter> _lastFilters = {};

  late EquipmentFilter _filter =
      _lastFilters[widget.isProblems] ?? const EquipmentFilter();

  final _searchController = TextEditingController();

  /// Запрос, по которому отобран список, — после паузы в наборе.
  String _query = '';
  Timer? _searchDebounce;
  static const Duration _searchDelay = Duration(milliseconds: 250);

  /// Область есть только в справочнике — см. класс.
  bool get _hasScope => widget.isProblems;

  /// Синхронизация уже идёт — показываем тонкую полоску над списком, но сам
  /// список не прячем.
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    // Справочники подтягиваем в фоне, а не блокируем ими экран. Раньше здесь
    // стоял FutureBuilder на mainSync(), и «Задачи» показывали спиннер, пока
    // не перекачаются все справочники — включая каталог ЗИП на десятки тысяч
    // позиций. При этом всё нужное уже лежит в Hive и рисуется мгновенно.
    _syncInBackground();
    // Фоновая синхронизация меняет и сам справочник, и то, что считать своим
    // (помещения подразделений, профиль с «все подразделения»). Без
    // подписки открытый экран держал бы прежний отбор до повторного входа.
    final provider = GlobalState.dataProvider;
    provider.inventoryRevision.addListener(_onScopeChanged);
    provider.accessProfile.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    final provider = GlobalState.dataProvider;
    provider.inventoryRevision.removeListener(_onScopeChanged);
    provider.accessProfile.removeListener(_onScopeChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onScopeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _syncInBackground() async {
    if (!GlobalState.allowSyncMainOnce) return;
    setState(() => _isSyncing = true);
    await GlobalState.syncMainOnce();
    if (!mounted) return;
    setState(() => _isSyncing = false);
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

  void _setFilter(EquipmentFilter filter) {
    _lastFilters[widget.isProblems] = filter;
    setState(() => _filter = filter);
  }

  bool _isOwn(InventoryRecord equipment) =>
      !_hasScope || GlobalState.dataProvider.isOwnEquipment(equipment);

  /// Есть ли у оборудования активные задачи — для «С активными задачами».
  /// Кэш очередей сбрасывает вызывающий, один раз на проход.
  static bool _hasActiveTasks(InventoryRecord equipment) =>
      GlobalState.dataProvider.getTasksForMachine(equipment.uuid).isNotEmpty;

  /// Набор до области и фильтров с числом задач у каждой единицы.
  ///
  /// В «Задачах» — оборудование с задачами, за один проход по задачам, а не
  /// по проходу на каждую единицу. Раньше подсчёт дёргался и в `where`, и
  /// дважды в компараторе сортировки, и ещё раз в `itemBuilder`; каждый
  /// вызов шёл по всем задачам и обоим боксам сканов. На двух сотнях единиц
  /// оборудования это тысячи полных проходов на один кадр.
  ///
  /// В справочнике — весь справочник: «Осмотр оборудования или ТМЦ» — это
  /// выбор объекта для осмотра, а не список задач.
  List<(InventoryRecord, int)> _base() {
    final provider = GlobalState.dataProvider;
    // Сбрасываем кэш очередей на входе: внутри прохода он живёт и экономит
    // сотни обходов, но между кадрами очередь могла измениться.
    provider.invalidateScanTaskCache();
    final equipment = provider.inventoryRecords;
    if (widget.isProblems) {
      return [for (final item in equipment) (item, 0)];
    }
    final withRework = <(InventoryRecord, int)>[];
    final rest = <(InventoryRecord, int)>[];
    for (final item in equipment) {
      final tasks = provider.getTasksForMachine(item.uuid);
      if (tasks.isEmpty) continue;
      final hasRework = tasks.any((task) => task.isReturnedForRework);
      (hasRework ? withRework : rest).add((item, tasks.length));
    }
    // Оборудование с задачами на доработку — первым: проверяющий ждёт
    // исправления, и в общем списке такую задачу легко пропустить. В
    // остальном порядок справочника, как и был.
    return [...withRework, ...rest];
  }

  List<InventoryRecord> _apply(
    List<InventoryRecord> base,
    EquipmentFilter filter,
  ) {
    return applyEquipmentFilter(
      base,
      filter: filter,
      query: _query,
      isOwn: _isOwn,
      hasActiveTasks: _hasActiveTasks,
    );
  }

  /// Применяет набранный текст, не дожидаясь паузы. Перед открытием листа:
  /// иначе, открытый раньше 250 мс, он считал бы «Показать N» по прежнему
  /// запросу, а список после закрытия — по новому.
  void _applySearchNow() {
    _searchDebounce?.cancel();
    final text = _searchController.text;
    if (_query != text) setState(() => _query = text);
  }

  Future<void> _openFilter() async {
    _applySearchNow();
    final result = await showModalBottomSheet<EquipmentFilter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EquipmentFilterSheet(
        initial: _filter,
        hasScope: _hasScope,
        hasTasksToggle: widget.isProblems,
        base: () => [for (final (item, _) in _base()) item],
        apply: (base, filter) => _apply(base, filter),
        isOwn: _isOwn,
      ),
    );
    if (result == null || !mounted) return;
    _setFilter(result);
  }

  @override
  Widget build(BuildContext context) {
    final isProblems = widget.isProblems;
    final isModal = widget.isModal;
    // Список считаем один раз на кадр, а не по разу на каждое обращение.
    final base = _base();
    final taskCounts = {for (final (item, count) in base) item.uuid: count};
    final baseRecords = [for (final (item, _) in base) item];
    final items = _apply(baseRecords, _filter);

    Widget body;
    if (items.isEmpty) {
      body = _isSyncing && baseRecords.isEmpty
          // Пока идёт первая синхронизация, а показывать ещё нечего — спиннер.
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 8,
                constraints:
                    const BoxConstraints(minHeight: 128, minWidth: 128),
              ),
            )
          : _buildEmpty(baseRecords);
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          AppConstants.spacingSM,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppConstants.spacingSM),
        itemBuilder: (context, index) {
          final equipment = items[index];
          return _EquipmentTile(
            equipment: equipment,
            taskCount: taskCounts[equipment.uuid] ?? 0,
            isProblems: isProblems,
            onTap: () {
              // push: список остаётся под карточкой, «назад» возвращает в него
              // вместе с прокруткой и фильтром.
              if (isProblems) {
                GoRouter.of(context)
                    .push('/qr_result_problems', extra: equipment);
              } else {
                GoRouter.of(context).push('/details/${equipment.id}');
              }
            },
          );
        },
      );
    }

    // Обновление в фоне — тонкой полоской сверху, чтобы список оставался на
    // экране и с ним можно было работать.
    if (_isSyncing && items.isNotEmpty) {
      body = Column(
        children: [
          const LinearProgressIndicator(minHeight: 2),
          Expanded(child: body),
        ],
      );
    }

    if (isModal) {
      return body;
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          Padding(
            // Отступы — как у строки поиска с фильтром в справочнике ЗИП.
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingSM,
            ),
            child: SearchFilterBar(
              controller: _searchController,
              hint: EquipmentFilterStrings.searchHint,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              activeCount: _filter.activeCount,
              onFilter: _openFilter,
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// Пустой список — по причине: данных нет совсем, пусто из-за области
  /// «Моё» или ничего не нашли поиск и фильтры.
  Widget _buildEmpty(List<InventoryRecord> base) {
    final isProblems = widget.isProblems;
    final searching = _query.trim().isNotEmpty || _filter.hasConditions;
    final mineOnly = _hasScope && !_filter.showAll;

    if (base.isEmpty) {
      return EmptyState(
        icon: isProblems ? Icons.warehouse_outlined : Icons.checklist_rounded,
        title: isProblems ? 'Нет оборудования' : 'Нет активных задач',
        hint: isProblems
            ? 'Список оборудования пуст или ещё не загружен.'
            : 'Отсканируйте QR-код оборудования, чтобы начать осмотр или открыть задачи.',
      );
    }

    final showAllButton = ElevatedButton(
      onPressed: () => _setFilter(_filter.copyWith(showAll: true)),
      child: Text(searching
          ? EquipmentFilterStrings.searchAllDivisions
          : EquipmentFilterStrings.showAllDivisions),
    );

    if (!searching) {
      // Пусто только из-за области «Моё»: оборудование есть, но не в
      // подразделениях обходчика.
      return EmptyState(
        icon: Icons.warehouse_outlined,
        title: EquipmentFilterStrings.emptyMineTitle,
        hint: EquipmentFilterStrings.emptyMineHint,
        action: showAllButton,
      );
    }

    // В «Моё» не нашлось — но, может, найдётся во всех подразделениях: тогда
    // говорим сколько и даём переключиться одной кнопкой.
    if (mineOnly) {
      final elsewhere = _apply(base, _filter.copyWith(showAll: true)).length;
      if (elsewhere > 0) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: FilterStrings.nothingFound,
          hint: EquipmentFilterStrings.foundElsewhere(elsewhere),
          action: showAllButton,
        );
      }
    }

    return EmptyState(
      icon: Icons.search_off_rounded,
      title: FilterStrings.nothingFound,
      hint: mineOnly
          ? EquipmentFilterStrings.nothingFoundMineHint
          : EquipmentFilterStrings.nothingFoundHint,
      // Без фильтров сбрасывать нечего — запрос стирают крестиком в поле.
      action: _filter.hasConditions
          ? ElevatedButton(
              onPressed: () => _setFilter(_filter.withoutConditions()),
              child: const Text(FilterStrings.resetFilters),
            )
          : null,
    );
  }
}

/// Лист «Фильтры» списка оборудования: область, местоположение, состояние,
/// задачи. Возвращает выбранный фильтр.
class _EquipmentFilterSheet extends StatefulWidget {
  final EquipmentFilter initial;
  final bool hasScope;
  final bool hasTasksToggle;

  /// Набор экрана до области и фильтров — функцией: пока лист открыт,
  /// фоновая синхронизация может его поменять.
  final List<InventoryRecord> Function() base;

  /// Отбор экрана, с его поисковым запросом — тот же, что у списка.
  final List<InventoryRecord> Function(
    List<InventoryRecord> base,
    EquipmentFilter filter,
  ) apply;
  final bool Function(InventoryRecord) isOwn;

  const _EquipmentFilterSheet({
    required this.initial,
    required this.hasScope,
    required this.hasTasksToggle,
    required this.base,
    required this.apply,
    required this.isOwn,
  });

  @override
  State<_EquipmentFilterSheet> createState() => _EquipmentFilterSheetState();
}

class _EquipmentFilterSheetState extends State<_EquipmentFilterSheet> {
  late EquipmentFilter _draft = widget.initial;

  /// Сколько раз нажали «Сбросить» — в ключах разделов: сброс сворачивает
  /// раскрытое «Ещё N».
  int _resets = 0;

  /// Варианты и счётчик — в полях, а не в `build`: проход по справочнику на
  /// каждое перестроение листа был бы лишним.
  List<InventoryRecord> _base = const [];
  Map<String, String> _locations = const {};
  Map<String, String> _states = const {};
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _base = widget.base();
    _recompute();
    // Пока лист открыт, фоновая синхронизация может добавить оборудование
    // или поменять «своё» (помещения подразделений, профиль). Без подписки
    // кнопка обещала бы прежнее число, а после закрытия список показывал бы
    // другое.
    final provider = GlobalState.dataProvider;
    provider.inventoryRevision.addListener(_onDataChanged);
    provider.accessProfile.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    final provider = GlobalState.dataProvider;
    provider.inventoryRevision.removeListener(_onDataChanged);
    provider.accessProfile.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(() {
      _base = widget.base();
      _recompute();
    });
  }

  /// Варианты чипов — из набора выбранной области: при «Моё подразделение»
  /// помещение чужого подразделения всегда давало бы «Ничего не найдено».
  /// Выбранное, чего в новых вариантах нет (сменили область), снимаем —
  /// иначе остался бы невидимый активный фильтр.
  void _recompute() {
    final scoped = equipmentInScope(
      _base,
      showAll: _draft.showAll,
      isOwn: widget.isOwn,
    );
    _locations = equipmentLocationOptions(scoped);
    _states = equipmentStateOptions(
      scoped,
      dictionary: GlobalState.dataProvider.equipmentState?.states ?? const {},
    );
    _draft = _draft.copyWith(
      locations: _draft.locations.intersection(_locations.keys.toSet()),
      states: _draft.states.intersection(_states.keys.toSet()),
    );
    _count = widget.apply(_base, _draft).length;
  }

  void _update(EquipmentFilter next) {
    setState(() {
      _draft = next;
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheet(
      onReset: _draft.isDefault
          ? null
          : () {
              _resets++;
              _update(const EquipmentFilter());
            },
      resultCount: _count,
      resultLabel: EquipmentFilterStrings.showResults,
      onApply: () => Navigator.of(context).pop(_draft),
      children: [
        if (widget.hasScope) ...[
          const FilterSectionLabel(EquipmentFilterStrings.labelScope),
          const SizedBox(height: AppConstants.spacingSM),
          SegmentedToggle(
            labels: const [
              EquipmentFilterStrings.mine,
              EquipmentFilterStrings.all,
            ],
            selectedIndex: _draft.showAll ? 1 : 0,
            onChanged: (index) => _update(_draft.copyWith(showAll: index == 1)),
          ),
          const SizedBox(height: AppConstants.spacingLG),
        ],
        if (_locations.isNotEmpty)
          FilterSection(
            // Ключ — чтобы при исчезновении соседнего раздела (сменили
            // область) раскрытое «Ещё N» не перешло к другому; номер сброса
            // — чтобы «Сбросить» сворачивал раскрытое.
            key: ValueKey('locations#$_resets'),
            label: EquipmentFilterStrings.labelLocation,
            count: _draft.locations.length,
            child: FilterChipGroup(
              options: _locations,
              selected: _draft.locations,
              onChanged: (next) => _update(_draft.copyWith(locations: next)),
            ),
          ),
        if (_states.isNotEmpty)
          FilterSection(
            key: ValueKey('states#$_resets'),
            label: EquipmentFilterStrings.labelState,
            count: _draft.states.length,
            child: FilterChipGroup(
              options: _states,
              selected: _draft.states,
              onChanged: (next) => _update(_draft.copyWith(states: next)),
            ),
          ),
        if (widget.hasTasksToggle) ...[
          const FilterSectionLabel(EquipmentFilterStrings.labelTasks),
          const SizedBox(height: AppConstants.spacingSM),
          SegmentedToggle(
            labels: const [
              EquipmentFilterStrings.tasksAll,
              EquipmentFilterStrings.tasksActive,
            ],
            selectedIndex: _draft.onlyWithTasks ? 1 : 0,
            onChanged: (index) =>
                _update(_draft.copyWith(onlyWithTasks: index == 1)),
          ),
        ],
      ],
    );
  }
}

/// Карточка оборудования в списке: leading-иконка, имя, подзаголовок, badge
/// справа (или chevron в справочнике).
class _EquipmentTile extends StatelessWidget {
  final InventoryRecord equipment;

  /// Все задачи оборудования, включая возвращённые на доработку: отдельной
  /// строки «N задач на доработку» у плитки нет — иначе одна и та же задача
  /// считалась бы дважды, и активной, и на доработку. Что среди них есть
  /// доработка, видно на экране задач оборудования (группа «На доработку»),
  /// а само такое оборудование стоит в списке первым.
  final int taskCount;
  final bool isProblems;
  final VoidCallback onTap;

  const _EquipmentTile({
    required this.equipment,
    required this.taskCount,
    required this.isProblems,
    required this.onTap,
  });

  /// Подпись в справочнике: «Литейный цех · В работе» — то, по чему
  /// фильтруют, чтобы было видно, почему единица попала в список.
  String? get _problemsSubtitle {
    final state = equipment.state;
    final parts = [
      if (equipmentLocationOf(equipment) case final location?) location,
      if (state != null && state.isNotEmpty)
        GlobalState.dataProvider.getEquipmentStateName(state) ?? state,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasTasks = !isProblems && taskCount > 0;

    final subtitle = isProblems
        ? _problemsSubtitle
        : taskCount == 0
            ? 'Нет активных задач'
            : '$taskCount ${pluralRu(taskCount, 'активная задача', 'активные задачи', 'активных задач')}';

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
                  color:
                      hasTasks ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: Icon(
                  Icons.precision_manufacturing_outlined,
                  color: hasTasks ? cs.onPrimaryContainer : cs.onSurfaceVariant,
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
                          color: hasTasks ? cs.primary : cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
