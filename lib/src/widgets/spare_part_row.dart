import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/spare_part.dart';

/// Строка справочника ЗИП: значок, название и серая строка
/// «Арт. X · На складе: N ед».
///
/// Один виджет на два места — раздел «ЗИП» и окно выбора позиции при вводе
/// фактического расхода. Раньше это были две почти одинаковые реализации,
/// которые успели разойтись по виду.
class SparePartRow extends StatelessWidget {
  final SparePart part;
  final VoidCallback? onTap;

  /// Правый край строки: например пометка «Добавлено» в окне выбора.
  final Widget? trailing;

  /// Приглушить строку — позиция уже добавлена и выбрать её нельзя.
  final bool dimmed;

  const SparePartRow({
    super.key,
    required this.part,
    this.onTap,
    this.trailing,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final unit = part.unitLabel;
    final stock = formatSparePartQuantity(part.quantity);

    // Остаток — единственный цветной элемент строки, и оценка у него та же,
    // что в карточке позиции (`SparePart.stockLevel`): раньше правила
    // расходились, и одна позиция была в списке оранжевой, а в карточке
    // красной.
    //
    // Отличие от карточки одно и намеренное: благополучный остаток здесь
    // **не красится**. Цвет в строке означает «обрати внимание», и если им
    // же отмечать норму, сигнал перестанет работать — в списке на тысячи
    // позиций цветным станет всё.
    final stockColor = switch (part.stockLevel) {
      SparePartStockLevel.out => cs.error,
      SparePartStockLevel.belowMinimum => cs.error,
      SparePartStockLevel.belowNorm => cs.warning,
      SparePartStockLevel.sufficient => null,
    };

    final code = part.supplierCode;

    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: SvgPicture.asset(
                  'assets/images/spare_part.svg',
                  width: 20,
                  height: 20,
                  colorFilter:
                      ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      part.name,
                      style: tt.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        children: [
                          if (code != null && code.isNotEmpty)
                            TextSpan(text: SparePartStrings.article(code)),
                          TextSpan(
                            text: SparePartStrings.inStock(stock) +
                                '${unit.isEmpty ? '' : ' $unit'}',
                            style: stockColor == null
                                ? null
                                : TextStyle(color: stockColor),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppConstants.spacingSM),
                trailing!,
              ]
              // Шеврон — единственный намёк, что строка кликабельна: в окне
              // выбора ЗИП его нет, там у строки своя роль и свой trailing.
              else if (onTap != null) ...[
                const SizedBox(width: AppConstants.spacingSM),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Целое — без дробной части: «40», а не «40.0». Сервер отдаёт
/// `Numeric(14, 4)`, и «40.0000» в цехе читать неудобно.
String formatSparePartQuantity(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}
