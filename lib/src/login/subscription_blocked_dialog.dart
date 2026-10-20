import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../exceptions/app_exceptions.dart';

/// Причина, по которой обходчика не пустили или вывели: доступ компании
/// закрыт.
///
/// Собран как диалоги ремонтов (`_SubmitConfirmDialog`,
/// `confirmRepairDelete`): значок в цветном квадрате, заголовок, короткое
/// пояснение, плашка и кнопка во всю ширину. Раньше это был общий
/// `Dialogs.notify` — один абзац из трёх мыслей сплошным текстом. Теперь
/// главное («работать нельзя, к руководителю») — отдельно, а успокаивающее
/// («данные целы») — в плашке.
///
/// Тариф истёк — оранжевый: это поправимо, продлят — заработает.
/// Компанию отключили — красный.
Future<void> showSubscriptionBlockedDialog(
  BuildContext context,
  SubscriptionBlockedException blocked,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SubscriptionBlockedDialog(
      deactivated: blocked.isDeactivated,
    ),
  );
}

class _SubscriptionBlockedDialog extends StatelessWidget {
  final bool deactivated;

  const _SubscriptionBlockedDialog({required this.deactivated});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = deactivated ? cs.error : cs.warning;
    final accentContainer =
        deactivated ? cs.errorContainer : cs.warningContainer;

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
                color: accentContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              ),
              child: Icon(
                deactivated
                    ? Icons.domain_disabled_rounded
                    : Icons.event_busy_rounded,
                size: 36,
                color: accent,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            Text(
              SubscriptionStrings.title(deactivated: deactivated),
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingSM),
            Text(
              SubscriptionStrings.body,
              style: tt.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingMD),
            // Плашка нейтральная, без значка и по центру — как `_Banner` в
            // карточке ремонта: это не предупреждение, а «ничего не пропало».
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Text(
                SubscriptionStrings.dataSafe,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLG),
            SizedBox(
              width: double.infinity,
              height: AppConstants.buttonHeightLarge,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Strings.understand, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
