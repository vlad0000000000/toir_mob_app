import 'package:flutter/material.dart';

import '../../strings.dart';
import '../widgets/info_dialog.dart';

/// Подтверждение удаления неотправленных данных ремонта.
///
/// В общем стиле окон приложения ([InfoDialog]), красное: удаление
/// необратимо. Последствие — в красной плашке, а не в общем тексте: это
/// единственное, что стоит прочитать, если читают одно.
///
/// Общий для списка ремонтов и карточки: удалять черновик можно из обоих
/// мест, и спрашивать в них по-разному не за что.
Future<bool> confirmRepairDelete(
  BuildContext context, {
  required String title,
  required String body,
  required String note,
}) {
  return showConfirmDialog(
    context,
    icon: Icons.delete_outline_rounded,
    tone: DialogTone.error,
    title: title,
    body: body,
    note: note,
    noteTinted: true,
    confirmLabel: RepairStrings.delete,
    confirmIcon: Icons.delete_outline_rounded,
    destructive: true,
    cancelLabel: RepairStrings.cancel,
  );
}
