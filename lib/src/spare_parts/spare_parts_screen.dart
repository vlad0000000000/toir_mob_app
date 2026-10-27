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
import '../utils/search_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_controls.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/spare_part_row.dart';
import 'spare_part_detail_screen.dart';

/// Справочник ЗИП: что и в каком количестве лежит на складах.
///
/// Экран только читает. Поиск и фильтры применяются **локально** к
/// выгруженному справочнику, хотя сервер такие фильтры тоже умеет: без сети
/// серверные всё равно недоступны, а обходчику раздел нужен именно в цеху.
class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  /// Забывает запомненный фильтр — при выходе из аккаунта: склады и группы
  /// прошлого пользователя следующему ни к чему.
  static void forgetFilter() =>
      _SparePartsScreenState._lastFilter = const _SparePartsFilter();

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
    // Каталог обновляется и без участия экрана — фоновым циклом раз в минуту.
    // Инкрементальный проход чаще всего меняет именно остатки, а они и есть
    // главное, ради чего сюда заходят: без подписки на экране оставались бы
    // числа с момента открытия, притом что подпись «Остатки на …» уверяла бы
    // в обратном.
    GlobalState.dataProvider.sparePartsRevision.addListener(_onCatalogChanged);
  }

  @override
  void dispose() {
    GlobalState.dataProvider.sparePartsRevision
        .removeListener(_onCatalogChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Отобранный список лежит в поле, поэтому одной перерисовки мало — отбор
  /// надо прогнать заново по новому каталогу.
  void _onCatalogChanged() => _recompute();

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
    // Без setState: крестик очистки следит за полем сам
    // (`SearchFilterBar`), а список пересчитается после паузы.
    _search = value;
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
            child: SearchFilterBar(
              controller: _searchController,
              hint: SparePartStrings.searchHint,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              activeCount: _activeFilterCount,
              onFilter: _openFilter,
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
String _pluralizePositions(int n) =>
    '$n ${pluralRu(n, 'позицию', 'позиции', 'позиций')}';

/// Варианты раздела по подписи: выбранные чип-группа поднимает сама.
Map<String, String> _sortedByLabel(Map<String, String> options) {
  final entries = options.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return {for (final entry in entries) entry.key: entry.value};
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
  late _SparePartsFilter _draft = widget.initial;

  /// Варианты секций и число совпадений — в полях, а не в геттерах.
  ///
  /// Раньше это были три геттера, каждый из которых проходил по всему каталогу,
  /// и все три вызывались из `build`. Вместе с двумя проходами в [_updateDraft]
  /// выходило пять проходов на каждое касание чипа. На стенде с 802 позициями
  /// незаметно, но каталог рассчитан на десятки тысяч — там это уже подвисание
  /// листа на каждое нажатие.
  ///
  /// Сам экран этой ошибки не делает: отобранный список лежит у него в поле с
  /// явным замечанием, что считать его в `build` нельзя. Лист фильтра — тот же
  /// код, написанный без этой предосторожности.
  Map<String, String> _warehouses = const {};
  Map<String, String> _groups = const {};
  int _resultCount = 0;

  @override
  void initState() {
    super.initState();
    _recomputeOptions();
    _recomputeCount();
  }

  /// Варианты секции считаются с учётом **остальных** условий фильтра, но не
  /// своего собственного. Иначе выбор одного склада спрятал бы все прочие
  /// склады, и второй уже нельзя было бы добавить.
  void _recomputeOptions() {
    _warehouses = _sortedByLabel(GlobalState.dataProvider.sparePartWarehouses(
      where: _draft.copyWith(warehouseUuids: const {}).matches,
    ));
    _groups =
        _sortedByLabel(GlobalState.dataProvider.sparePartNomenclatureGroups(
      where: _draft.copyWith(groupUuids: const {}).matches,
    ));
  }

  void _recomputeCount() {
    _resultCount = _applySparePartFilter(
      GlobalState.dataProvider.spareParts,
      filter: _draft,
      query: widget.query,
    ).length;
  }

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
      _recomputeOptions();
      final warehouses =
          _draft.warehouseUuids.intersection(_warehouses.keys.toSet());
      final groups = _draft.groupUuids.intersection(_groups.keys.toSet());
      // Пересчитываем варианты второй раз, только если выбор действительно
      // сузился. Снятие выбора расширяет варианты соседней секции, поэтому
      // посчитанные до отсечения оказались бы неполными — но случается это
      // редко, и платить лишним проходом на каждое касание незачем.
      // Пересечение только уменьшает множество, так что сравнения длин хватает.
      if (warehouses.length != _draft.warehouseUuids.length ||
          groups.length != _draft.groupUuids.length) {
        _draft = _draft.copyWith(
          warehouseUuids: warehouses,
          groupUuids: groups,
        );
        _recomputeOptions();
      }
      _recomputeCount();
    });
  }

  void _apply() => Navigator.of(context).pop(_draft);

  /// Сколько раз нажали «Сбросить» — в ключах разделов: сброс сворачивает
  /// раскрытое «Ещё N», как и раньше, когда раскрытие хранилось здесь.
  int _resets = 0;

  void _reset() {
    setState(() {
      _resets++;
      _draft = const _SparePartsFilter();
      // Сброс снимает все условия, значит варианты и счётчик меняются тоже.
      _recomputeOptions();
      _recomputeCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final warehouses = _warehouses;
    final groups = _groups;

    return FilterSheet(
      onReset: _draft.isEmpty ? null : _reset,
      resultCount: _resultCount,
      resultLabel: (count) =>
          SparePartStrings.showResults(_pluralizePositions(count)),
      onApply: _apply,
      children: [
        if (warehouses.isNotEmpty)
          FilterSection(
            // Ключ — чтобы при исчезновении соседнего раздела раскрытое
            // «Ещё N» не перешло к другому.
            key: ValueKey('warehouses#$_resets'),
            label: SparePartStrings.labelWarehouse,
            count: _draft.warehouseUuids.length,
            child: FilterChipGroup(
              options: warehouses,
              selected: _draft.warehouseUuids,
              onChanged: (next) =>
                  _updateDraft(_draft.copyWith(warehouseUuids: next)),
            ),
          ),
        if (groups.isNotEmpty)
          FilterSection(
            key: ValueKey('groups#$_resets'),
            label: SparePartStrings.labelGroup,
            count: _draft.groupUuids.length,
            child: FilterChipGroup(
              options: groups,
              selected: _draft.groupUuids,
              onChanged: (next) =>
                  _updateDraft(_draft.copyWith(groupUuids: next)),
            ),
          ),
        FilterSectionLabel(SparePartStrings.labelAvailability),
        const SizedBox(height: AppConstants.spacingSM),
        SegmentedToggle(
          labels: const [
            SparePartStrings.toggleAll,
            SparePartStrings.toggleInStock,
          ],
          selectedIndex: _draft.inStockOnly ? 1 : 0,
          onChanged: (index) =>
              _updateDraft(_draft.copyWith(inStockOnly: index == 1)),
        ),
        if (warehouses.isEmpty && groups.isEmpty) ...[
          const SizedBox(height: AppConstants.spacingLG),
          Text(
            _draft.inStockOnly
                ? SparePartStrings.noFacetsInStock
                : SparePartStrings.noFacets,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
