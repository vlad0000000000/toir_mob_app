import 'package:flutter/material.dart';

import '../../strings.dart';
import 'info_dialog.dart';

/// Объяснение по нажатию на запертое по роли — плитку, строку, поле.
///
/// [what] — к чему нет доступа, из [AccessStrings] («к ремонтам»).
/// В общем стиле окон приложения ([InfoDialog]): замок в оранжевом квадрате
/// — доступа нет, но это поправимо через руководителя; что делать — в
/// плашке, отдельно от самой новости.
Future<void> showNoAccessDialog(BuildContext context, String what) {
  return showInfoDialog(
    context,
    icon: Icons.lock_outline_rounded,
    tone: DialogTone.warning,
    title: AccessStrings.title,
    body: AccessStrings.body(what),
    note: AccessStrings.hint,
  );
}

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
