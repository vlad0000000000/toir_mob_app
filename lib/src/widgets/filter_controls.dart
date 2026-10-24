import 'package:flutter/material.dart';

import '../design/app_constants.dart';

/// Кнопка фильтров рядом с поиском или над списком: значок настроек, а при
/// активных условиях — заливка цветом и их число. Общая для справочника ЗИП
/// и списка оборудования, чтобы фильтры выглядели одинаково.
class FilterButton extends StatelessWidget {
  /// Высота кнопки, когда рядом нет поля поиска, от которого её можно взять:
  /// столько же, сколько у поля поиска справочника ЗИП (отступы темы 14 + 14
  /// и строка текста 24). С ней кнопка выглядит так же — квадратом.
  static const double standaloneHeight = 52;

  final int activeCount;
  final VoidCallback onTap;

  const FilterButton(
      {super.key, required this.activeCount, required this.onTap});

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

/// Переключатель из нескольких вариантов («Все / В наличии», «Моё
/// подразделение / Все подразделения»): выбранный сегмент — приподнятая
/// белая плашка внутри серого контейнера, как в макете.
class SegmentedToggle extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const SegmentedToggle({
    super.key,
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
