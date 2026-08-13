import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../http/api.dart';
import '../model/spare_part.dart';
import '../model/stock_history_entry.dart';
import '../repairs/repair_error_messages.dart';
import '../widgets/date_range_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/spare_part_row.dart';

/// Лента движений остатка выключена: на экране остаются только реквизиты
/// позиции и текущий остаток. Код ленты — загрузка, пагинация, поиск, чипы
/// категорий и фильтр периода — оставлен на месте и включается сменой флага
/// на `true`. Тот же приём, что у фильтра задач (`_kShowTasksFilter`).
///
/// Пока флаг выключен, `GET /company/spare_parts/history` не вызывается
/// вовсе — карточка открывается одним запросом вместо двух.
// ignore: prefer_const_declarations
final bool _kShowStockHistory = false;

/// Карточка позиции ЗИП: реквизиты номенклатуры и текущий остаток.
///
/// Повторяет карточку веб-админки (`SparePartDetailDialog`) в части формулы
/// полосы запаса. Лента движений там есть, здесь — выключена, см.
/// [_kShowStockHistory].
class SparePartDetailScreen extends StatefulWidget {
  final String sparePartUuid;

  /// Позиция из локального каталога — карточка рисуется сразу, без ожидания
  /// сети. Свежий остаток подтягивается следом.
  final SparePart? initial;

  const SparePartDetailScreen({
    super.key,
    required this.sparePartUuid,
    this.initial,
  });

  @override
  State<SparePartDetailScreen> createState() => _SparePartDetailScreenState();
}

class _SparePartDetailScreenState extends State<SparePartDetailScreen> {
  /// Сколько записей истории тянем за раз. Столько же берёт админка
  /// (`STOCK_HISTORY_PAGE_LIMIT`).
  static const int _pageLimit = 50;

  /// За сколько пикселей до конца списка запрашиваем следующую страницу.
  static const double _loadMoreThreshold = 400;

  static const Duration _searchDelay = Duration(milliseconds: 180);

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  SparePart? _part;

  /// Загруженные записи в порядке сервера — от новых к старым.
  List<StockHistoryEntry> _entries = const [];

  /// Отобранные поиском и чипами — то, что реально видно.
  List<StockHistoryEntry> _visible = const [];

  /// Всего записей на сервере. Приходит только с первой страницей.
  int _total = 0;

  final Set<StockMovementCategory> _categories = {};
  String _search = '';

  /// Границы периода, включительно по обоим краям. `null` — граница не задана,
  /// как и в веб-админке: можно указать только «с» или только «по».
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool get _hasPeriod => _dateFrom != null || _dateTo != null;

  /// Подпись чипа: «Период» без выбора, «01.06.26 – …» с ним. Многоточие на
  /// незаданной границе — как в админке: видно, что край открыт.
  String get _periodLabel {
    if (!_hasPeriod) return SparePartStrings.period;
    final from =
        _dateFrom == null ? '…' : DateFormat('dd.MM.yy').format(_dateFrom!);
    final to = _dateTo == null ? '…' : DateFormat('dd.MM.yy').format(_dateTo!);
    return '$from – $to';
  }

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _part = widget.initial ?? _fromCatalog();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  SparePart? _fromCatalog() =>
      GlobalState.dataProvider.sparePartByUuid(widget.sparePartUuid);

  /// Первая страница: свежие реквизиты позиции и начало ленты. Оба запроса
  /// идут параллельно — они независимы, и ждать их по очереди значило бы
  /// удвоить время открытия карточки.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = API();
    // Отказ превращаем в значение прямо здесь, а не в try вокруг await:
    // второй запрос успел бы отвалиться, пока мы ждём первый, и его ошибка
    // осталась бы без обработчика — Dart считает такую «непойманной».
    final partRequest = api
        .getSparePart(widget.sparePartUuid)
        .then<Object>((part) => part, onError: (Object error) => error);
    // Историю запрашиваем, только если лента показывается: иначе это лишний
    // запрос при каждом открытии карточки.
    final historyRequest = _kShowStockHistory
        ? api
            .getStockHistory(
              sparePartUuid: widget.sparePartUuid,
              limit: _pageLimit,
            )
            .then<Object>((page) => page, onError: (Object error) => error)
        : null;

    // Реквизиты не критичны: карточка уже нарисована по кэшу каталога, и
    // неудача обновления остатка её не портит. История критична — без неё
    // показывать нечего.
    final partResult = await partRequest;
    final historyResult = await historyRequest;
    if (!mounted) return;
    setState(() {
      if (partResult is SparePart) _part = partResult;
      _isLoading = false;
      if (historyResult is StockHistoryPage) {
        _entries = historyResult.entries;
        _total = historyResult.total ?? historyResult.entries.length;
        _error = null;
      } else if (historyResult != null) {
        _error = repairErrorMessage(historyResult);
      } else if (_part == null && partResult is! SparePart) {
        // Ленты нет, и причину сбоя больше сообщать некому: показываем отказ
        // по самой позиции, иначе экран «Позиция не найдена» умолчал бы о том,
        // что дело в связи.
        _error = repairErrorMessage(partResult);
      }
      _recomputeVisible();
    });
  }

  /// Следующая страница ленты. Ошибку не показываем — экран уже с данными,
  /// а прокрутка повторит попытку сама.
  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading) return;
    if (_entries.length >= _total) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await API().getStockHistory(
        sparePartUuid: widget.sparePartUuid,
        limit: _pageLimit,
        offset: _entries.length,
      );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...page.entries];
        _isLoadingMore = false;
        _recomputeVisible();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    // Подгружать нечего, пока лента выключена.
    if (!_kShowStockHistory) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  /// Отбор держим полем, а не считаем в build: build вызывается на каждый
  /// кадр прокрутки, а лента может насчитывать тысячи записей.
  void _recomputeVisible() {
    final query = _search.trim().toLowerCase();
    // Сравниваем по началу суток: обходчик выбирает день, а не момент, и
    // операция в 23:50 обязана попасть в период, заканчивающийся этим днём.
    final from = _dateFrom == null ? null : _dayStart(_dateFrom!);
    final to = _dateTo == null ? null : _dayStart(_dateTo!);
    _visible = _entries.where((entry) {
      if (_categories.isNotEmpty && !_categories.contains(entry.category)) {
        return false;
      }
      if (query.isNotEmpty && !entry.matchesQuery(query)) return false;
      if (from != null || to != null) {
        final day = _dayStart(entry.operationAt.toLocal());
        if (from != null && day.isBefore(from)) return false;
        if (to != null && day.isAfter(to)) return false;
      }
      return true;
    }).toList();
  }

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Лист выбора периода — два календаря «С даты» и «По дату», как в карточке
  /// ЗИП веб-админки.
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final result = await showDateRangeSheet(
      context,
      from: _dateFrom,
      to: _dateTo,
      firstDate: DateTime(now.year - 5),
      // Движений в будущем не бывает — дальше сегодняшнего дня выбирать нечего.
      lastDate: now,
    );
    if (result == null || !mounted) return;
    setState(() {
      _dateFrom = result.from;
      _dateTo = result.to;
      _recomputeVisible();
    });
  }

  void _onSearchChanged(String value) {
    // Текст обновляем сразу — от него зависит крестик очистки.
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (!mounted) return;
      setState(_recomputeVisible);
    });
  }

  void _toggleCategory(StockMovementCategory? category) {
    setState(() {
      if (category == null) {
        _categories.clear();
      } else if (!_categories.remove(category)) {
        _categories.add(category);
      }
      // Отмеченные все три категории — то же самое, что «Все»: снимаем
      // отметки, чтобы подсветился один чип, а не четыре.
      if (_categories.length == StockMovementCategory.values.length) {
        _categories.clear();
      }
      _recomputeVisible();
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _categories.clear();
      _dateFrom = null;
      _dateTo = null;
      _searchDebounce?.cancel();
      _recomputeVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final part = _part;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: part == null
            ? const Text(SparePartStrings.cardTitle)
            : _TitleWithIcon(name: part.name),
        actions: [
          if (part != null)
            Padding(
              padding: const EdgeInsets.only(right: AppConstants.spacingMD),
              child: Center(child: _StockPill(part: part)),
            ),
        ],
      ),
      body: part == null ? _buildMissing(cs) : _buildBody(part),
    );
  }

  /// Карточки нет ни в каталоге, ни на сервере — открыли по устаревшей ссылке
  /// или каталог ещё не выгружен.
  Widget _buildMissing(ColorScheme cs) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: cs.primary,
          strokeWidth: 8,
          constraints: const BoxConstraints(minHeight: 128, minWidth: 128),
        ),
      );
    }
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      title: SparePartStrings.notFoundTitle,
      hint: _error ?? SparePartStrings.notFoundHint,
      action: FilledButton(
        onPressed: _load,
        child: const Text(SparePartStrings.retry),
      ),
    );
  }

  Widget _buildBody(SparePart part) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _StockBlock(part: part)),
          SliverToBoxAdapter(child: _DetailsCard(part: part)),
          // Лента движений выключена — см. [_kShowStockHistory].
          if (_kShowStockHistory) ...[
            SliverToBoxAdapter(child: _buildHistoryHeader()),
            if (_isLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spacingXL,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: cs.primary,
                      strokeWidth: 6,
                      constraints:
                          const BoxConstraints(minHeight: 64, minWidth: 64),
                    ),
                  ),
                ),
              )
            else if (_visible.isEmpty)
              SliverToBoxAdapter(child: _buildHistoryEmpty())
            else
              _buildHistorySliver(part),
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppConstants.spacingXL,
                child: _isLoadingMore
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ] else
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spacingXL),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMD,
        AppConstants.spacingLG,
        AppConstants.spacingMD,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  SparePartStrings.historyTitle,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (!_isLoading && _error == null)
                Text(
                  SparePartStrings.shownOf(_visible.length, _total),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMD),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: SparePartStrings.historySearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: SparePartStrings.clearSearch,
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingMD),
          // Чипы уезжают за край экрана: четыре подписи в строку не влезают,
          // а перенос на вторую строку съедал бы высоту у самой ленты.
          SizedBox(
            height: AppConstants.buttonHeightSmall,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: SparePartStrings.categoryAll,
                  selected: _categories.isEmpty,
                  onTap: () => _toggleCategory(null),
                ),
                for (final category in StockMovementCategory.values) ...[
                  const SizedBox(width: AppConstants.spacingSM),
                  _CategoryChip(
                    label: category.label,
                    selected: _categories.contains(category),
                    onTap: () => _toggleCategory(category),
                  ),
                ],
                const SizedBox(width: AppConstants.spacingSM),
                _CategoryChip(
                  label: _periodLabel,
                  selected: _hasPeriod,
                  // Тот же значок, что у чипа «Период» в админке — lucide
                  // Calendar.
                  iconAsset: 'assets/images/calendar.svg',
                  onTap: _pickPeriod,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryEmpty() {
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: SparePartStrings.historyUnavailableTitle,
        hint: _error,
        action: FilledButton(
          onPressed: _load,
          child: const Text(SparePartStrings.retry),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: SparePartStrings.historyEmptyTitle,
        hint: SparePartStrings.historyEmptyHint,
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: SparePartStrings.nothingFound,
      hint: SparePartStrings.refineHint,
      action: TextButton(
        onPressed: _resetFilters,
        child: const Text(SparePartStrings.resetFilters),
      ),
    );
  }

  /// Лента с заголовками дней. Строки и заголовки разложены в один плоский
  /// список: SliverList строит только видимые элементы, а вложенные Column по
  /// дням заставили бы его строить день целиком.
  Widget _buildHistorySliver(SparePart part) {
    final rows = <Object>[];
    String? currentDay;
    for (final entry in _visible) {
      final day = formatDayLabelRu(entry.operationAt.toLocal());
      if (day != currentDay) {
        currentDay = day;
        rows.add(day);
      }
      rows.add(entry);
    }
    final unit = part.unitLabel;

    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is String) {
          return _DayHeader(label: row, first: index == 0);
        }
        return _MovementRow(entry: row as StockHistoryEntry, unit: unit);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Шапка
// ─────────────────────────────────────────────────────────────────────────

class _TitleWithIcon extends StatelessWidget {
  final String name;

  const _TitleWithIcon({required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          ),
          child: SvgPicture.asset(
            'assets/images/spare_part.svg',
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: AppConstants.spacingSM),
        Expanded(
          child: Text(
            name,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Пилюля наличия в шапке. Три состояния, те же, что подсвечивают остаток в
/// строке справочника: нет вовсе, опустился до минимума, в наличии.
class _StockPill extends StatelessWidget {
  final SparePart part;

  const _StockPill({required this.part});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Ровно два состояния, как в админке: позиция либо есть на складе, либо
    // её нет. «Ниже минимума» отсюда убрано намеренно — про запас говорит
    // полоса под остатком, и дублировать это пилюлей значит спорить с ней
    // цветом при остатке между минимумом и нормой.
    final inStock = part.quantity > 0;
    final label = inStock
        ? SparePartStrings.availabilityIn
        : SparePartStrings.availabilityOut;
    final foreground = inStock ? cs.onSuccessContainer : cs.error;
    final background = inStock ? cs.successContainer : cs.errorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSM,
        vertical: AppConstants.spacingXS,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Остаток
// ─────────────────────────────────────────────────────────────────────────

/// Текущий остаток крупно, полоса запаса и подпись «минимум N · норма M».
class _StockBlock extends StatelessWidget {
  final SparePart part;

  const _StockBlock({required this.part});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final minimum = part.minimumStock;
    final norm = part.stockNorm;
    final unit = part.unitLabel;

    // Формула и цвета — как в веб-админке: ниже минимума красный, ниже нормы
    // оранжевый, иначе основной. Ширина — доля от нормы; без нормы полоса
    // либо полная, либо пустая, сравнивать не с чем.
    final Color barColor;
    if (minimum != null && part.quantity < minimum) {
      barColor = cs.error;
    } else if (norm != null && part.quantity < norm) {
      barColor = cs.warning;
    } else {
      barColor = cs.primary;
    }
    final double barValue;
    if (norm != null && norm > 0) {
      barValue = (part.quantity / norm).clamp(0.0, 1.0);
    } else {
      barValue = part.quantity > 0 ? 1 : 0;
    }

    final thresholds = <String>[
      if (minimum != null)
        SparePartStrings.minimum(formatSparePartQuantity(minimum)),
      if (norm != null)
        SparePartStrings.stockNorm(formatSparePartQuantity(norm)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMD,
        AppConstants.spacingLG,
        AppConstants.spacingMD,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SparePartStrings.currentStock,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatSparePartQuantity(part.quantity),
                style: tt.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: AppConstants.spacingSM),
                Text(
                  unit,
                  style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
          if (thresholds.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingMD),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              child: LinearProgressIndicator(
                value: barValue,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSM),
            Text(
              thresholds.join(' · '),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Реквизиты позиции: подпись слева, значение справа.
class _DetailsCard extends StatelessWidget {
  final SparePart part;

  const _DetailsCard({required this.part});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMD,
        AppConstants.spacingLG,
        AppConstants.spacingMD,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          children: [
            _DetailRow(
              label: SparePartStrings.fieldWarehouse,
              value: part.warehouseName,
            ),
            _DetailRow(
              label: SparePartStrings.fieldGroup,
              value: part.nomenclatureGroupName,
            ),
            _DetailRow(
              label: SparePartStrings.fieldArticle,
              value: part.supplierCode,
            ),
            _DetailRow(
              label: SparePartStrings.fieldAccount,
              value: part.accountingAccount,
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool last;

  const _DetailRow({required this.label, this.value, this.last = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final text = (value == null || value!.trim().isEmpty) ? '—' : value!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMD,
        vertical: AppConstants.spacingMD - 4,
      ),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: AppConstants.spacingMD),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: tt.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Лента движений
// ─────────────────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Значок слева от подписи — есть только у чипа периода, как в админке.
  final String? iconAsset;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconAsset,
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
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
              if (iconAsset != null) ...[
                SvgPicture.asset(
                  iconAsset!,
                  width: 14,
                  height: 14,
                  colorFilter: ColorFilter.mode(
                    selected ? cs.onPrimary : cs.onSurfaceVariant,
                    BlendMode.srcIn,
                  ),
                ),
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

class _DayHeader extends StatelessWidget {
  final String label;

  /// Первый заголовок ленты — над ним отступ меньше: сверху уже чипы.
  final bool first;

  const _DayHeader({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Дата — залитая плашка во всю ширину, как в веб-админке: лента длинная,
    // и без такой «полки» дни в ней сливаются.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spacingMD,
        first ? AppConstants.spacingSM : AppConstants.spacingLG,
        AppConstants.spacingMD,
        AppConstants.spacingSM,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
          vertical: AppConstants.spacingSM,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
        ),
        child: Text(
          label.toUpperCase(),
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Строка движения: значок категории, основание операции, время и
/// ответственный, знаковое количество справа.
class _MovementRow extends StatelessWidget {
  final StockHistoryEntry entry;
  final String unit;

  const _MovementRow({required this.entry, required this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Значки взяты из веб-админки один в один — те же иконки lucide, что
    // рисует `SparePartDetailDialog`: ArrowDownToLine на приход, ArrowUpFromLine
    // на расход, SlidersHorizontal на корректировку.
    final (String asset, Color foreground, Color background) =
        switch (entry.category) {
      StockMovementCategory.replenish => (
          'assets/images/stock_in.svg',
          cs.onSuccessContainer,
          cs.successContainer,
        ),
      StockMovementCategory.writeoff => (
          'assets/images/stock_out.svg',
          cs.error,
          cs.errorContainer,
        ),
      StockMovementCategory.correction => (
          'assets/images/stock_correction.svg',
          cs.onSurfaceVariant,
          cs.surfaceContainerHigh,
        ),
    };

    final local = entry.operationAt.toLocal();
    final meta = <String>[
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}',
      if (entry.responsibleName != null &&
          entry.responsibleName!.trim().isNotEmpty)
        entry.responsibleName!,
    ].join(' · ');

    final positive = entry.quantityChange >= 0;
    final amount = '${positive ? '+' : '−'}'
        '${formatSparePartQuantity(entry.quantityChange.abs())}'
        '${unit.isEmpty ? '' : ' $unit'}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMD,
        vertical: AppConstants.spacingMD - 4,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            ),
            child: SvgPicture.asset(
              asset,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  style: tt.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingSM),
          Text(
            amount,
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: positive ? cs.success : cs.error,
            ),
          ),
        ],
      ),
    );
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Открыть карточку позиции. `push`, а не `go`: список ЗИП остаётся в стеке
/// вместе с введённым поиском и выбранными фильтрами — обходчик возвращается
/// ровно туда, откуда ушёл.
void openSparePartCard(BuildContext context, SparePart part) {
  context.push('/spare_parts/${part.uuid}', extra: part);
}
