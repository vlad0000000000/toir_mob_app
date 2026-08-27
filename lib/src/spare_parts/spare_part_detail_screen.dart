
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../http/api.dart';
import '../model/spare_part.dart';
import '../repairs/repair_error_messages.dart';
import '../widgets/empty_state.dart';
import '../widgets/spare_part_row.dart';

/// Карточка позиции ЗИП: реквизиты номенклатуры и текущий остаток.
///
/// Повторяет карточку веб-админки (`SparePartDetailDialog`) в части формулы
/// полосы запаса. Ленты движений здесь нет: заказчик её не заказывал, а код,
/// лежавший за выключенным флагом, удалён — половина файла, которая
/// компилировалась и поддерживалась впустую.
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
  SparePart? _part;

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _part = widget.initial ?? _fromCatalog();
    _load();
  }

  SparePart? _fromCatalog() =>
      GlobalState.dataProvider.sparePartByUuid(widget.sparePartUuid);

  /// Свежие реквизиты позиции. Карточка уже нарисована по кэшу каталога,
  /// поэтому запрос только обновляет остаток.
  ///
  /// Отказ важен лишь тогда, когда показывать нечего вовсе: позиции нет и в
  /// кэше. Иначе экран «Позиция не найдена» умолчал бы о том, что дело в связи.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final part = await API().getSparePart(widget.sparePartUuid);
      if (!mounted) return;
      setState(() {
        _part = part;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_part == null) _error = repairErrorMessage(error);
      });
    }
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
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _StockBlock(part: part)),
          SliverToBoxAdapter(child: _DetailsCard(part: part)),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.spacingXL),
          ),
        ],
      ),
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

/// Открыть карточку позиции. `push`, а не `go`: список ЗИП остаётся в стеке
/// вместе с введённым поиском и выбранными фильтрами — обходчик возвращается
/// ровно туда, откуда ушёл.
void openSparePartCard(BuildContext context, SparePart part) {
  context.push('/spare_parts/${part.uuid}', extra: part);
}
