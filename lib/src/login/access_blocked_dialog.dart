import 'package:flutter/material.dart';

import '../../strings.dart';
import '../exceptions/app_exceptions.dart';
import '../widgets/info_dialog.dart';

/// Причина, по которой обходчика не пустили или вывели: доступ закрыт —
/// тариф компании или роль доступа.
///
/// В общем стиле окон приложения ([InfoDialog]): главное («работать нельзя,
/// к руководителю») — пояснением, а успокаивающее («данные целы») — в
/// плашке. Раньше это был общий `Dialogs.notify` — один абзац из трёх мыслей
/// сплошным текстом.
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
  return showInfoDialog(
    context,
    icon: view.icon,
    tone: view.severe ? DialogTone.error : DialogTone.warning,
    title: view.title,
    body: SubscriptionStrings.body,
    note: SubscriptionStrings.dataSafe,
  );
}

/// Что показать: цвет (красный — [severe]), значок и заголовок.
typedef _AccessBlockedView = ({bool severe, IconData icon, String title});
