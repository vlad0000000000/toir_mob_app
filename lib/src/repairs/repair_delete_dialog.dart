import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';

/// Подтверждение удаления неотправленных данных ремонта.
///
/// Собран как подтверждение завершения ремонта (`_SubmitConfirmDialog`):
/// значок в цветном квадрате, заголовок, пояснение, плашка с последствием и
/// две кнопки во всю ширину друг под другом. Удаление необратимо, поэтому
/// подача такая же весомая, только красная.
///
/// Общий для списка ремонтов и карточки: удалять черновик можно из обоих
/// мест, и спрашивать в них по-разному не за что.
Future<bool> confirmRepairDelete(
  BuildContext context, {
  required String title,
  required String body,
  required String note,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteConfirmDialog(title: title, body: body, note: note),
  );
  return result == true;
}

class _DeleteConfirmDialog extends StatelessWidget {
  final String title;

  /// Что именно пропадёт — одной фразой.
  final String body;

  /// Последствие, которое нельзя отменить. Вынесено в плашку, а не в общий
  /// текст: это единственное, что стоит прочитать, если читают одно.
  final String note;

  const _DeleteConfirmDialog({
    required this.title,
    required this.body,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(AppConstants.spacingMD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 36,
                color: cs.error,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            Text(
              title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingSM),
            Text(
              body,
              style: tt.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingMD),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Text(
                note,
                style: tt.bodySmall?.copyWith(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLG),
            // Кнопки друг под другом и во всю ширину — как в подтверждении
            // завершения: в ряду подпись со значком переносилась бы на вторую
            // строку, а высота кнопки фиксированная.
            SizedBox(
              width: double.infinity,
              height: AppConstants.buttonHeightLarge,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text(RepairStrings.delete, maxLines: 1),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSM),
            SizedBox(
              width: double.infinity,
              height: AppConstants.buttonHeightLarge,
              child: ElevatedButton(
                // Вторичная кнопка — заливка серым, а не обводка: обе кнопки
                // одинаковой «плотности».
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.surfaceContainer,
                  foregroundColor: cs.onSurface,
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(RepairStrings.cancel, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
