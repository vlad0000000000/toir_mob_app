import 'package:flutter/material.dart';

import '../../strings.dart';
import '../utils/dialogs.dart';

/// Объяснение по нажатию на запертое по роли — плитку, строку, поле.
///
/// [what] — к чему нет доступа, из [AccessStrings] («к ремонтам»).
/// Обычный `Dialogs.notify`: здесь одна мысль, отдельный диалог с плашкой,
/// как у закрытого доступа целиком, был бы тяжелее самой новости.
Future<void> showNoAccessDialog(BuildContext context, String what) =>
    Dialogs.notify(context, AccessStrings.title, AccessStrings.body(what));

/// Значок замка у запертого по роли элемента — один на всё приложение,
/// чтобы плитка, строка и поле читались одинаково.
class NoAccessIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const NoAccessIcon({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.lock_outline_rounded,
      size: size,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
