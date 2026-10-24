import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../widgets/filter_controls.dart';
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

  /// Фильтр «Моё подразделение / Все подразделения» переживает уход с
  /// экрана в пределах запуска — как фильтр справочника ЗИП. По умолчанию —
  /// своё.
  static bool _lastShowAll = false;
  bool _showAll = _lastShowAll;

  static List<InventoryRecord> _scopedEquipment(
    List<InventoryRecord> equipment, {
    required bool showAll,
  }) {
    if (showAll) return equipment;
    final provider = GlobalState.dataProvider;
    return [
      for (final item in equipment)
        if (provider.isOwnEquipment(item)) item,
    ];
  }

  Future<void> _openScopeFilter() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EquipmentScopeSheet(initialShowAll: _showAll),
    );
    if (result == null || !mounted) return;
    _lastShowAll = result;
    setState(() => _showAll = result);
  }

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

  Future<void> _openFilter() async {
    final result = await showTasksFilterSheet(context, _filter);
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  /// Оборудование с задачами — за один проход по задачам, а не по проходу на
  /// каждую единицу оборудования.
  ///
  /// Раньше `_filteredTasksFor` дёргался и в `where`, и дважды в компараторе
  /// сортировки, и ещё раз в `itemBuilder`; каждый вызов шёл по всем задачам
  /// и обоим боксам сканов. На двух сотнях единиц оборудования это тысячи
  /// полных проходов на один кадр.
  ///
  /// Возвращает оборудование с числом задач и числом из них возвращённых на
  /// доработку.
  List<(InventoryRecord, int, int)> _equipmentWithTasks() {
    final equipment = GlobalState.dataProvider.inventoryRecords;

    // «Осмотр оборудования или ТМЦ» — это выбор объекта для осмотра, а не
    // список задач: здесь нужен весь справочник. Счётчик задач в этом режиме
    // и не показывается (см. `_EquipmentTile`), а отбор по ним всё равно
    // применялся — и обходчик видел вместо справочника случайный огрызок из
    // тех единиц, по которым сейчас висит задача.
    //
    // Отбор здесь один — фильтр «Моё подразделение / Все подразделения»:
    // справочник может прийти по всей компании, и своё в нём отличаем на
    // телефоне. Влияет только на этот список — не на скан QR.
    if (widget.isProblems) {
      return [
        for (final item in _scopedEquipment(equipment, showAll: _showAll))
          (item, 0, 0),
      ];
    }

    // Сбрасываем кэш очередей на входе: внутри прохода он живёт и экономит
    // сотни обходов, но между кадрами очередь могла измениться.
    GlobalState.dataProvider.invalidateScanTaskCache();
    final withRework = <(InventoryRecord, int, int)>[];
    final rest = <(InventoryRecord, int, int)>[];
    for (final item in equipment) {
      final tasks = _filteredTasksFor(item);
      if (tasks.isEmpty) continue;
      final rework = tasks.where((task) => task.isReturnedForRework).length;
      (rework > 0 ? withRework : rest).add((item, tasks.length, rework));
    }
    // Оборудование с задачами на доработку — первым: проверяющий ждёт
    // исправления, и в общем списке такую задачу легко пропустить. В
    // остальном порядок справочника, как и был.
    return [...withRework, ...rest];
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
    // Список считаем один раз на кадр, а не по разу на каждое обращение.
    final items = _equipmentWithTasks();

    Widget body;
    if (items.isEmpty) {
      // Пока идёт первая синхронизация, а показывать ещё нечего — спиннер.
      // Если данные есть, он не нужен: список уже виден.
      body = _isSyncing
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 8,
                constraints:
                    const BoxConstraints(minHeight: 128, minWidth: 128),
              ),
            )
          : isProblems &&
                  !_showAll &&
                  GlobalState.dataProvider.inventoryRecords.isNotEmpty
              // Пусто только из-за фильтра «Моё»: оборудование есть, но не в
              // помещениях подразделений обходчика.
              ? const EmptyState(
                  icon: Icons.warehouse_outlined,
                  title: EquipmentFilterStrings.emptyMineTitle,
                  hint: EquipmentFilterStrings.emptyMineHint,
                )
              : EmptyState(
                  icon: isProblems
                      ? Icons.warehouse_outlined
                      : Icons.checklist_rounded,
                  title: isProblems ? 'Нет оборудования' : 'Нет активных задач',
                  hint: isProblems
                      ? 'Список оборудования пуст или ещё не загружен.'
                      : 'Отсканируйте QR-код оборудования, чтобы начать осмотр или открыть задачи.',
                );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
          vertical: AppConstants.spacingMD,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppConstants.spacingSM),
        itemBuilder: (context, index) {
          final (equipment, taskCount, reworkCount) = items[index];
          return _EquipmentTile(
            equipment: equipment,
            taskCount: taskCount,
            reworkCount: reworkCount,
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
          if (_kShowTasksFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TasksFilterButton(
                  activeCount: _filter.activeCount,
                  onTap: _openFilter,
                ),
              ),
            ),
          // Фильтр подразделений — в справочнике оборудования. Активным он
          // считается на «Всё»: по умолчанию показывается своё.
          if (isProblems)
            Padding(
              // Отступы — как у строки поиска с фильтром в справочнике ЗИП.
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                AppConstants.spacingMD,
                AppConstants.spacingMD,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: FilterButton.standaloneHeight,
                  child: FilterButton(
                    activeCount: _showAll ? 1 : 0,
                    onTap: _openScopeFilter,
                  ),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Лист фильтра справочника оборудования: пока один переключатель «Моё
/// подразделение / Все подразделения» — в стиле фильтров справочника ЗИП.
/// Возвращает «показывать все подразделения».
class _EquipmentScopeSheet extends StatefulWidget {
  final bool initialShowAll;

  const _EquipmentScopeSheet({required this.initialShowAll});

  @override
  State<_EquipmentScopeSheet> createState() => _EquipmentScopeSheetState();
}

class _EquipmentScopeSheetState extends State<_EquipmentScopeSheet> {
  late bool _showAll = widget.initialShowAll;

  /// Сколько единиц покажет список — в поле, а не в `build`: проход по
  /// справочнику на каждое перестроение листа был бы лишним.
  late int _count = _countFor(_showAll);

  static int _countFor(bool showAll) =>
      _EquipmentListScreenState._scopedEquipment(
        GlobalState.dataProvider.inventoryRecords,
        showAll: showAll,
      ).length;

  void _set(bool showAll) => setState(() {
        _showAll = showAll;
        _count = _countFor(showAll);
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppConstants.spacingMD),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    EquipmentFilterStrings.title,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _showAll ? () => _set(false) : null,
                  child: const Text(EquipmentFilterStrings.reset),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingSM,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  EquipmentFilterStrings.labelScope.toUpperCase(),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingSM),
                SegmentedToggle(
                  labels: const [
                    EquipmentFilterStrings.mine,
                    EquipmentFilterStrings.all,
                  ],
                  selectedIndex: _showAll ? 1 : 0,
                  onChanged: (index) => _set(index == 1),
                ),
              ],
            ),
          ),
          // Липкая кнопка, как у фильтра ЗИП: обещает ровно то число,
          // которое обходчик увидит после закрытия листа.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingSM,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: SizedBox(
              height: AppConstants.buttonHeightLarge,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_showAll),
                child: Text(
                  _count == 0
                      ? EquipmentFilterStrings.nothingFound
                      : EquipmentFilterStrings.showResults(_count),
                ),
              ),
            ),
          ),
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

  /// Сколько из задач вернули на доработку — отдельной строкой под
  /// счётчиком.
  final int reworkCount;
  final bool isProblems;
  final VoidCallback onTap;

  const _EquipmentTile({
    required this.equipment,
    required this.taskCount,
    this.reworkCount = 0,
    required this.isProblems,
    required this.onTap,
  });

  String _pluralizeTasks(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n активная задача';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
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
                      ),
                    ],
                    if (!isProblems && reworkCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        ReworkStrings.equipmentCount(reworkCount),
                        style: tt.bodySmall?.copyWith(
                          color: cs.warning,
                          fontWeight: FontWeight.w600,
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
