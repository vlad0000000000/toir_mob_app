import 'package:flutter/material.dart';
import 'modal.dart';

/// Единый каркас модального bottom-sheet: barrier, верхние скругления,
/// прозрачный фон и обёртка [Modal]. Заменяет повторяющийся
/// `showModalBottomSheet(...)` в `select_*`-кнопках и меню действий.
Future<T?> showAppModalSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isDismissible = false,
  bool enableDrag = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    builder: (context) => Modal(child: child),
  );
}
