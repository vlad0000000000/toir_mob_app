import 'dart:async';

import 'package:flutter/material.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../app_bar/app_bar.dart';
// Импорт библиотеки целиком, а не part-файла: syncSpareParts объявлен в
// extension DataProviderSync и виден только через data_provider.dart.
import '../data/data_provider.dart';
import '../design/app_constants.dart';
import '../model/spare_part.dart';
import '../widgets/empty_state.dart';
import '../widgets/spare_part_row.dart';
import 'spare_part_detail_screen.dart';

/// Справочник ЗИП: что и в каком количестве лежит на складах.
///
/// Экран только читает. Поиск и фильтры применяются **локально** к
/// выгруженному справочнику, хотя сервер такие фильтры тоже умеет: без сети
/// серверные всё равно недоступны, а обходчику раздел нужен именно в цеху.
class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  /// Выбранный фильтр, переживающий уход с экрана.
  ///
  /// Внутри одного захода список остаётся в стеке под карточкой позиции и свой
  /// `State` сохраняет сам. Но раздел открывается с главной заново каждый раз,
  /// и тогда `State` создаётся с нуля — обычного поля не хватило бы. Статик
  /// живёт до перезапуска приложения. Так же сделан фильтр статусов в списке
  /// ремонтов (`repairs_list_screen.dart`).
  ///
  /// Поисковый запрос сюда намеренно не входит: фильтр — осознанная
  /// настройка, а запрос набирают ради одной позиции, и восстановленный
  /// текст прятал бы каталог при следующем заходе.
  static _SparePartsFilter _lastFilter = const _SparePartsFilter();

  final _searchController = TextEditingController();
  String _search = '';
  _SparePartsFilter _filter = _lastFilter;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    // Справочник подтягивается фоновым циклом раз в 60 секунд, и сразу после
    // установки (или после смены версии, когда база создаётся заново) он ещё
    // пуст. Не заставляем обходчика ждать минуту и гадать, почему список
    // пустой, — тянем каталог сами и показываем спиннер.
    // Первый отбор без setState — билда ещё не было.
    _visible = _filterNow();
    if (GlobalState.dataProvider.spareParts.isEmpty) {
      _isSyncing = true;
      _syncCatalog();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncCatalog() async {
    await GlobalState.dataProvider.syncSpareParts();
    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _visible = _filterNow();
    });
  }

  int get _activeFilterCount => _filter.activeCount;

  /// Готовый список для отрисовки. Держим полем, а не геттером: build
  /// вызывается на каждое касание экрана, и пересчитывать отбор по каталогу
  /// в десятки тысяч позиций там нельзя.
  List<SparePart> _visible = const [];

  /// Ввод фильтруется не на каждый символ, а после паузы: пока обходчик
  /// набирает «подшипник», иначе прошло бы девять полных проходов по каталогу.
  Timer? _searchDebounce;
  static const Duration _searchDelay = Duration(milliseconds: 180);

  List<SparePart> _filterNow() => _applySparePartFilter(
        GlobalState.dataProvider.spareParts,
        filter: _filter,
        query: _search,
      );

  void _recompute() {
    if (!mounted) return;
    setState(() => _visible = _filterNow());
  }

  void _onSearchChanged(String value) {
    // Сам текст обновляем сразу — от него зависит крестик очистки.
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, _recompute);
  }

  /// Дата последней синхронизации в коротком виде. Остатки всегда показываются
  /// «на момент», даже когда связь есть: обходчик должен понимать, насколько
  /// свежие числа он видит, а не гадать.
  String? get _stockAsOf => GlobalState.dataProvider.sparePartsFreshness();

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<_SparePartsFilter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SparePartsFilterSheet(
        initial: _filter,
        query: _search,
      ),
    );
    if (result == null) return;
    _filter = result;
    _lastFilter = result;
    _recompute();
  }

  void _clearSearch() {
    _searchController.clear();
    _search = '';
    _searchDebounce?.cancel();
    _recompute();
  }

  /// Обновляем только справочник ЗИП — это один запрос постранично, а не все
  /// семь каталогов.
  ///
  /// Неудачу показываем: подпись «Остатки на …» остаётся старой намеренно —
  /// она обязана говорить правду о том, когда числа приезжали в последний
  /// раз, — но обходчик должен понимать, что это отказ, а не «нечему
  /// меняться».
  Future<void> _refresh() async {
    final updated = await GlobalState.dataProvider.syncSpareParts();
    _recompute();
    if (updated || !mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        SparePartStrings.refreshFailed,
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onError),
      ),
      backgroundColor: cs.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final parts = _visible;
    final asOf = _stockAsOf;
    final catalogIsEmpty = GlobalState.dataProvider.spareParts.isEmpty;

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingSM,
            ),
            // IntrinsicHeight + stretch: кнопка фильтра принимает ровно ту же
            // высоту, что и поле поиска. Задавать ей высоту числом нельзя —
            // фактическая высота TextField зависит от темы и кегля.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: SparePartStrings.searchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: SparePartStrings.clearSearch,
                                onPressed: _clearSearch,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSM),
                  _FilterButton(
                    activeCount: _activeFilterCount,
                    onTap: _openFilter,
                  ),
                ],
              ),
            ),
          ),
          if (asOf != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                0,
                AppConstants.spacingMD,
                AppConstants.spacingSM,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  SparePartStrings.stockAsOf(asOf),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          if (_isSyncing && catalogIsEmpty)
            // Первичная загрузка: спиннер вместо EmptyState, иначе на холодном
            // старте мелькает «Справочник ЗИП пуст», пока ответ ещё в полёте.
            Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: cs.primary,
                  strokeWidth: 8,
                  constraints:
                      const BoxConstraints(minHeight: 128, minWidth: 128),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: parts.isEmpty
                    // EmptyState внутри ListView с AlwaysScrollableScrollPhysics —
                    // иначе на непрокручиваемом содержимом жест «потянуть вниз»
                    // не срабатывает.
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          EmptyState(
                            icon: catalogIsEmpty
                                ? Icons.inventory_2_outlined
                                : Icons.search_off_rounded,
                            title: catalogIsEmpty
                                ? SparePartStrings.catalogEmptyTitle
                                : SparePartStrings.nothingFound,
                            hint: catalogIsEmpty
                                ? SparePartStrings.catalogEmptyHint
                                : SparePartStrings.refineHint,
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(
                          bottom: AppConstants.spacingXL,
                        ),
                        itemCount: parts.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: cs.outlineVariant,
                        ),
                        itemBuilder: (context, index) => SparePartRow(
                          part: parts[index],
                          onTap: () => openSparePartCard(context, parts[index]),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Фильтр
// ─────────────────────────────────────────────────────────────────────────
class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final active = activeCount > 0;
    return Material(
      color: active ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        child: Container(
          // Высоту не задаём — её диктует IntrinsicHeight по полю поиска.
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 20,
                color: active ? cs.onPrimary : cs.onSurface,
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Text(
                  '$activeCount',
                  style: tt.labelMedium?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
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

/// Состояние фильтра справочника ЗИП. Пустые множества — «без ограничений».
class _SparePartsFilter {
  final Set<String> warehouseUuids;
  final Set<String> groupUuids;

  /// Показывать только позиции с ненулевым остатком.
  final bool inStockOnly;

  const _SparePartsFilter({
    this.warehouseUuids = const {},
    this.groupUuids = const {},
    this.inStockOnly = false,
  });

  int get activeCount =>
      warehouseUuids.length + groupUuids.length + (inStockOnly ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  bool matches(SparePart part) {
    if (inStockOnly && part.quantity <= 0) return false;
    if (warehouseUuids.isNotEmpty &&
        !warehouseUuids.contains(part.warehouseUuid)) {
      return false;
    }
    if (groupUuids.isNotEmpty &&
        !groupUuids.contains(part.nomenclatureGroupUuid)) {
      return false;
    }
    return true;
  }

  _SparePartsFilter copyWith({
    Set<String>? warehouseUuids,
    Set<String>? groupUuids,
    bool? inStockOnly,
  }) {
    return _SparePartsFilter(
      warehouseUuids: warehouseUuids ?? this.warehouseUuids,
      groupUuids: groupUuids ?? this.groupUuids,
      inStockOnly: inStockOnly ?? this.inStockOnly,
    );
  }
}

/// Общий отбор для экрана и для счётчика «Показать N позиций» в листе —
/// чтобы обещанное на кнопке число совпадало с тем, что реально покажется.
List<SparePart> _applySparePartFilter(
  List<SparePart> source, {
  required _SparePartsFilter filter,
  required String query,
}) {
  // Запрос приводим к нижнему регистру один раз, а не на каждую позицию;
  // сами позиции сравниваются по заранее подготовленным полям.
  final normalized = query.trim().toLowerCase();
  final result = <SparePart>[];
  for (final part in source) {
    if (!filter.matches(part)) continue;
    if (normalized.isNotEmpty && !part.matchesQuery(normalized)) continue;
    result.add(part);
  }
  // Не сортируем: справочник уже отсортирован по названию при синхронизации,
  // а отбор порядок сохраняет.
  return result;
}

/// Склонение для кнопки: «1 позицию», «2 позиции», «5 позиций».
String _pluralizePositions(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n позицию';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
    return '$n позиции';
  }
  return '$n позиций';
}

class _SparePartsFilterSheet extends StatefulWidget {
  final _SparePartsFilter initial;

  /// Текущий поисковый запрос экрана — входит в счётчик на кнопке, иначе
  /// обещанное число не совпало бы с тем, что видно после закрытия листа.
  final String query;

  const _SparePartsFilterSheet({required this.initial, required this.query});

  @override
  State<_SparePartsFilterSheet> createState() => _SparePartsFilterSheetState();
}

class _SparePartsFilterSheetState extends State<_SparePartsFilterSheet> {
  /// Сколько чипов показываем в секции до нажатия «Ещё N».
  static const int _collapsedChips = 8;

  late _SparePartsFilter _draft = widget.initial;
  bool _warehousesExpanded = false;
  bool _groupsExpanded = false;

  /// Варианты секции считаются с учётом **остальных** условий фильтра, но не
  /// своего собственного. Иначе выбор одного склада спрятал бы все прочие
  /// склады, и второй уже нельзя было бы добавить.
  Map<String, String> get _warehouseOptions =>
      GlobalState.dataProvider.sparePartWarehouses(
        where: _draft.copyWith(warehouseUuids: const {}).matches,
      );

  Map<String, String> get _groupOptions =>
      GlobalState.dataProvider.sparePartNomenclatureGroups(
        where: _draft.copyWith(groupUuids: const {}).matches,
      );

  int get _resultCount => _applySparePartFilter(
        GlobalState.dataProvider.spareParts,
        filter: _draft,
        query: widget.query,
      ).length;

  /// Любое изменение фильтра сужает списки вариантов — как переключение
  /// «В наличии», так и выбор склада или группы. Выбранное значение могло
  /// пропасть из перечня, поэтому после каждой правки снимаем то, чего в
  /// вариантах больше нет: иначе остался бы невидимый активный фильтр,
  /// из-за которого список выглядел бы необъяснимо пустым.
  ///
  /// Одного прохода достаточно: снятие выбора только расширяет варианты
  /// соседней секции, сузить их обратно оно не может.
  void _updateDraft(_SparePartsFilter next) {
    setState(() {
      _draft = next;
      final warehouses = _warehouseOptions.keys.toSet();
      final groups = _groupOptions.keys.toSet();
      _draft = _draft.copyWith(
        warehouseUuids: _draft.warehouseUuids.intersection(warehouses),
        groupUuids: _draft.groupUuids.intersection(groups),
      );
    });
  }

  void _apply() => Navigator.of(context).pop(_draft);

  void _reset() {
    setState(() {
      _draft = const _SparePartsFilter();
      _warehousesExpanded = false;
      _groupsExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final warehouses = _warehouseOptions;
    final groups = _groupOptions;
    final count = _resultCount;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    SparePartStrings.filtersTitle,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _draft.isEmpty ? null : _reset,
                  child: const Text(SparePartStrings.reset),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
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
                  if (warehouses.isNotEmpty) ...[
                    _SectionLabel(
                      SparePartStrings.labelWarehouse,
                      count: _draft.warehouseUuids.length,
                    ),
                    const SizedBox(height: AppConstants.spacingSM),
                    _ChipGroup(
                      options: warehouses,
                      selected: _draft.warehouseUuids,
                      expanded: _warehousesExpanded,
                      collapsedLimit: _collapsedChips,
                      onExpand: () =>
                          setState(() => _warehousesExpanded = true),
                      onChanged: (next) => _updateDraft(
                        _draft.copyWith(warehouseUuids: next),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingLG),
                  ],
                  if (groups.isNotEmpty) ...[
                    _SectionLabel(
                      SparePartStrings.labelGroup,
                      count: _draft.groupUuids.length,
                    ),
                    const SizedBox(height: AppConstants.spacingSM),
                    _ChipGroup(
                      options: groups,
                      selected: _draft.groupUuids,
                      expanded: _groupsExpanded,
                      collapsedLimit: _collapsedChips,
                      onExpand: () => setState(() => _groupsExpanded = true),
                      onChanged: (next) =>
                          _updateDraft(_draft.copyWith(groupUuids: next)),
                    ),
                    const SizedBox(height: AppConstants.spacingLG),
                  ],
                  _SectionLabel(SparePartStrings.labelAvailability),
                  const SizedBox(height: AppConstants.spacingSM),
                  _SegmentedToggle(
                    labels: const [
                      SparePartStrings.toggleAll,
                      SparePartStrings.toggleInStock,
                    ],
                    selectedIndex: _draft.inStockOnly ? 1 : 0,
                    onChanged: (index) => _updateDraft(
                      _draft.copyWith(inStockOnly: index == 1),
                    ),
                  ),
                  if (warehouses.isEmpty && groups.isEmpty) ...[
                    const SizedBox(height: AppConstants.spacingLG),
                    Text(
                      _draft.inStockOnly
                          ? SparePartStrings.noFacetsInStock
                          : SparePartStrings.noFacets,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Липкая кнопка: обещает ровно то число, которое обходчик увидит
          // после закрытия листа — с учётом поиска на экране.
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
                onPressed: _apply,
                child: Text(
                  count == 0
                      ? SparePartStrings.nothingFound
                      : SparePartStrings.showResults(
                          _pluralizePositions(count)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Переключатель «Все / В наличии»: выбранный сегмент — приподнятая белая
/// плашка внутри серого контейнера, как в макете.
class _SegmentedToggle extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SegmentedToggle({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  /// Позиция плашки: −1 — крайний левый сегмент, +1 — крайний правый.
  Alignment get _thumbAlignment {
    if (labels.length < 2) return Alignment.center;
    return Alignment(-1 + 2 * selectedIndex / (labels.length - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Stack(
        children: [
          // Плашка едет к выбранному сегменту, а не перекрашивается на месте —
          // как ползунок Switch в веб-админке (transition-transform).
          // Positioned.fill: размер Stack задаёт ряд подписей ниже, а плашка
          // просто накрывает его и выравнивается внутри.
          Positioned.fill(
            child: AnimatedAlign(
              duration: AppConstants.durationFast,
              curve: AppConstants.curveDefault,
              alignment: _thumbAlignment,
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                    onTap: () => onChanged(i),
                    child: SizedBox(
                      height: AppConstants.buttonHeightSmall,
                      child: Center(
                        // Подпись перекрашивается плавно: на фоне едущей
                        // плашки резкая смена цвета бросалась бы в глаза.
                        child: AnimatedDefaultTextStyle(
                          duration: AppConstants.durationFast,
                          curve: AppConstants.curveDefault,
                          style: tt.labelLarge!.copyWith(
                            color: i == selectedIndex
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                            fontWeight:
                                i == selectedIndex ? FontWeight.w600 : null,
                          ),
                          child: Text(labels[i]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool expanded;
  final int collapsedLimit;
  final VoidCallback onExpand;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.expanded,
    required this.collapsedLimit,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList();
    // Выбранные поднимаем наверх: иначе после сворачивания активный фильтр
    // мог бы оказаться спрятанным под «Ещё N».
    entries.sort((a, b) {
      final aSelected = selected.contains(a.key) ? 0 : 1;
      final bSelected = selected.contains(b.key) ? 0 : 1;
      if (aSelected != bSelected) return aSelected - bSelected;
      return a.value.compareTo(b.value);
    });

    final hidden = expanded ? 0 : entries.length - collapsedLimit;
    final visible = hidden > 0 ? entries.take(collapsedLimit) : entries;

    return Wrap(
      spacing: AppConstants.spacingSM,
      runSpacing: AppConstants.spacingSM,
      children: [
        for (final entry in visible)
          _PillChip(
            label: entry.value,
            selected: selected.contains(entry.key),
            onTap: () {
              final next = {...selected};
              if (!next.remove(entry.key)) next.add(entry.key);
              onChanged(next);
            },
          ),
        if (hidden > 0) _MoreChip(count: hidden, onTap: onExpand),
      ],
    );
  }
}

/// Чип «Ещё N» — раскрывает спрятанные варианты. Обратно не сворачивается:
/// свернуть уже увиденное посреди выбора только сбивает.
class _MoreChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MoreChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.buttonHeightSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                SparePartStrings.more(count),
                style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          // Общая минимальная высота: чипы в строке одинаковые независимо
          // от того, показана ли галочка. Без неё выбранные становились выше.
          constraints: const BoxConstraints(
            minHeight: AppConstants.buttonHeightSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: AppConstants.spacingSM,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border:
                Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 16, color: cs.onPrimary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: tt.labelLarge?.copyWith(
                  color: selected ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  /// Сколько значений выбрано в секции. Ноль — счётчик не рисуется.
  final int count;

  const _SectionLabel(this.text, {this.count = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final labelStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
    if (count == 0) {
      return Text(text, style: labelStyle);
    }
    return Row(
      children: [
        Text(text, style: labelStyle),
        const SizedBox(width: 6),
        Text(
          '· $count',
          style: labelStyle?.copyWith(color: cs.primary),
        ),
      ],
    );
  }
}
