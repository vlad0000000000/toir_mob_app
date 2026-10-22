import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../exceptions/app_exceptions.dart';

/// Причина, по которой обходчика не пустили или вывели: доступ закрыт —
/// тариф компании или роль доступа.
///
/// Собран как диалоги ремонтов (`_SubmitConfirmDialog`,
/// `confirmRepairDelete`): значок в цветном квадрате, заголовок, короткое
/// пояснение, плашка и кнопка во всю ширину. Раньше это был общий
/// `Dialogs.notify` — один абзац из трёх мыслей сплошным текстом. Теперь
/// главное («работать нельзя, к руководителю») — отдельно, а успокаивающее
/// («данные целы») — в плашке.
///
/// Оранжевый — поправимо обычным порядком: тариф продлят, роль назначат.
/// Красный — доступ закрыли осознанно: компанию или роль отключили.
Future<void> showAccessBlockedDialog(
  BuildContext context,
  AccessBlockedException blocked,
) {
  final _AccessBlockedView view = switch (blocked) {
    SubscriptionBlockedException(:final isDeactivated) => (
        severe: isDeactivated,
        icon: isDeactivated
            ? Icons.domain_disabled_rounded
            : Icons.event_busy_rounded,
        title: SubscriptionStrings.title(deactivated: isDeactivated),
      ),
    _ => switch (blocked.code) {
        NoBusinessAccessException.roleMissing => (
            severe: false,
            icon: Icons.person_off_rounded,
            title: AccessRoleStrings.roleMissingTitle,
          ),
        NoBusinessAccessException.roleInactive => (
            severe: true,
            icon: Icons.lock_person_rounded,
            title: AccessRoleStrings.roleInactiveTitle,
          ),
        _ => (
            severe: true,
            icon: Icons.domain_disabled_rounded,
            title: AccessRoleStrings.companyMissingTitle,
          ),
      },
  };
  return showDialog<void>(
    context: context,
    builder: (_) => _AccessBlockedDialog(view: view),
  );
}

/// Что показать: цвет (красный — [severe]), значок и заголовок.
typedef _AccessBlockedView = ({bool severe, IconData icon, String title});

class _AccessBlockedDialog extends StatelessWidget {
  final _AccessBlockedView view;

  const _AccessBlockedDialog({required this.view});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = view.severe ? cs.error : cs.warning;
    final accentContainer =
        view.severe ? cs.errorContainer : cs.warningContainer;

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
              child: Icon(view.icon, size: 36, color: accent),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            Text(
              view.title,
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
