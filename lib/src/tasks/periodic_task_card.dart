import 'package:flutter/material.dart';
import '../../src/model/periodic_task_models.dart';
import '../../src/model/spare_part_usage.dart';
import '../design/app_constants.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/spare_part_consumption.dart';

/// Карточка периодической задачи (узел, описание, норма расхода, фото) — общая
/// для списка задач оборудования и для списка задач ППР.
///
/// [usage] — блок расхода ЗИП из осмотра, а не из самой периодической задачи:
/// план приходит в `spare_part_usage` вместе с осмотром и уже разобран в
/// `Task`. Берём его оттуда, а не тащим норму в [PeriodicTask], — иначе
/// пришлось бы менять её Hive-адаптер и хранить одно и то же дважды.
/// `null` или пустой план — раздела нормы в карточке нет.
void showPeriodicTaskCard(
  BuildContext context,
  PeriodicTask pt, {
  SparePartUsage? usage,
}) {
  final tt = Theme.of(context).textTheme;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMD,
            0,
            AppConstants.spacingMD,
            AppConstants.spacingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pt.title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (pt.node != null && pt.node!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(context, 'Узел:', pt.node!),
            ],
            if (pt.description != null && pt.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(context, 'Описание:', pt.description!),
            ],
            const SizedBox(height: 8),
            // Норма расхода — до фото: это такая же текстовая справка о задаче,
            // как узел и описание, и читают её чаще, чем смотрят снимки.
            if (usage != null && usage.hasPlan) ...[
              const SizedBox(height: 12),
              _buildSectionLabel(context, 'НОРМА РАСХОДА ЗИП'),
              const SizedBox(height: 8),
              for (final item in usage.planned) _buildNormRow(context, item),
            ],
            if (pt.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildSectionLabel(context, 'ФОТО'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pt.photos
                    .map(
                      (photo) => InkWell(
                        onTap: () {
                          showAppModalSheet(
                            context,
                            isDismissible: true,
                            enableDrag: true,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppConstants.spacingMD,
                                  vertical: AppConstants.spacingSM,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            AppConstants.radiusMD),
                                        child: Image.network(
                                          photo.url,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                        height: AppConstants.spacingSM),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: FilledButton.tonal(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text('Закрыть'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusSM),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: Image.network(
                              photo.url,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: AppConstants.spacingLG),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Подпись раздела карточки — «НОРМА РАСХОДА ЗИП», «ФОТО».
Widget _buildSectionLabel(BuildContext context, String text) {
  final tt = Theme.of(context).textTheme;
  return Text(
    text,
    style: tt.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// Строка нормы: «Болт 6347-59 × 3». По левому краю, вровень с описанием и
/// узлом — карточка вся набрана без отступов и маркеров.
///
/// Знак «×» — уже принятый в приложении разделитель для состава нормы, тот же
/// что в `ConsumptionNorm.compositionSummary`. Единицу измерения не
/// показываем: в составе плана сервер её не присылает, в админке её тоже нет,
/// а тянуть ради неё каталог ЗИП на экран задач слишком дорого.
Widget _buildNormRow(BuildContext context, SparePartUsageItem item) {
  final tt = Theme.of(context).textTheme;
  final quantity = formatConsumptionQuantity(item.quantity);
  return Padding(
    padding: const EdgeInsets.only(bottom: AppConstants.spacingXS),
    child: Text(
      '${item.sparePartName} × $quantity',
      style: tt.bodyMedium,
    ),
  );
}

Widget _buildDetailRow(BuildContext context, String label, String value) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.replaceAll(':', '').toUpperCase(),
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: tt.bodyMedium),
      ],
    ),
  );
}
