import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';

/// Смысл окна — по нему выбираются цвет значка, его подложки и окрашенной
/// плашки.
enum DialogTone {
  /// Обычный вопрос или действие: «Отправить осмотр?», «Выйти?».
  primary,

  /// Справка без оценки: «Информация».
  info,

  /// Получилось: «Все данные синхронизированы».
  success,

  /// Нельзя или не вышло, но поправимо: нет связи, нет доступа, расход не
  /// заполнен.
  warning,

  /// Ошибка, необратимое действие или осознанный запрет: удаление, неверный
  /// пароль, компания отключена.
  error,
}

/// Единое окно приложения: значок в цветном квадрате, заголовок и пояснение
/// по центру, необязательная плашка и кнопки во всю ширину друг под другом.
///
/// Через него показываются **все** окна-сообщения и подтверждения — тариф и
/// закрытый доступ, «Нет доступа», удаление и завершение ремонта, ошибки
/// входа, результат синхронизации. Стандартный `AlertDialog` и прежний
/// `Dialogs.notify` (AwesomeDialog) выглядели в приложении чужими: другой
/// фон, кнопки в ряд, нет значка. Вне его — только просмотр фото на весь
/// экран и окно онбординга: у них своя задача и свой вид.
///
/// Простые случаи — [showInfoDialog] и [showConfirmDialog]; сам виджет нужен,
/// когда в окне есть что-то кроме текста ([content]) или своя раскладка
/// кнопок.
class InfoDialog extends StatelessWidget {
  final IconData icon;
  final DialogTone tone;

  final String title;

  /// Пояснение под заголовком. Может отсутствовать, если хватает заголовка
  /// («Все данные синхронизированы»).
  final String? body;

  /// Своё содержимое под пояснением: текст с выделением, сводка, поле ввода.
  final Widget? content;

  /// Плашка внизу — второстепенное: что делать, что ничего не пропало.
  /// `null` — плашки нет.
  final String? note;

  /// Плашка цветом окна, а не серая. Для последствия, которое важнее
  /// остального текста, — «удаление нельзя отменить».
  final bool noteTinted;

  /// Кнопки сверху вниз; первая — главная. Во всю ширину каждая: в ряд
  /// длинная подпись переносилась бы и обрезалась. Собирать из
  /// [DialogPrimaryButton] и [DialogSecondaryButton].
  final List<Widget> actions;

  const InfoDialog({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.body,
    this.content,
    this.note,
    this.noteTinted = false,
    required this.actions,
  });

  /// Цвет значка и его подложка для [tone].
  static ({Color accent, Color container}) colorsOf(
      ColorScheme cs, DialogTone tone) {
    return switch (tone) {
      DialogTone.primary => (
          accent: cs.primary,
          container: cs.primaryContainer
        ),
      DialogTone.info => (accent: cs.info, container: cs.infoContainer),
      DialogTone.success => (
          accent: cs.success,
          container: cs.successContainer
        ),
      DialogTone.warning => (
          accent: cs.warning,
          container: cs.warningContainer
        ),
      DialogTone.error => (accent: cs.error, container: cs.errorContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final colors = colorsOf(cs, tone);
    final body = this.body;
    final content = this.content;
    final note = this.note;
    return Dialog(
      backgroundColor: cs.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(AppConstants.spacingMD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLG),
        // Содержимое прокручивается, кнопки — нет. Длинное название и
        // помещение на маленьком экране (320×568) иначе выталкивали нижнюю
        // кнопку за край: окно без прокрутки просто переполнялось. Высоту
        // ограничивает сам `Dialog` — по экрану за вычетом отступов, —
        // поэтому `Flexible` здесь работает.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.container,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLG),
                      ),
                      child: Icon(icon, size: 36, color: colors.accent),
                    ),
                    const SizedBox(height: AppConstants.spacingMD),
                    Text(
                      title,
                      style:
                          tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacingSM),
                      Text(body,
                          style: tt.bodyLarge, textAlign: TextAlign.center),
                    ],
                    if (content != null) ...[
                      const SizedBox(height: AppConstants.spacingMD),
                      content,
                    ],
                    if (note != null) ...[
                      const SizedBox(height: AppConstants.spacingMD),
                      // Плашка без значка и по центру: заголовок и пояснение
                      // уже отцентрованы, полоса со значком слева ломала бы
                      // этот ряд.
                      DialogNote(
                        text: note,
                        color: noteTinted ? colors.accent : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingLG),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingSM),
              // Высота — минимальная, а не жёсткая: при крупном системном
              // шрифте длинная подпись («Завершить и сохранить») переносится
              // на вторую строку и кнопка растёт, а не обрезает текст.
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: double.infinity,
                  minHeight: AppConstants.buttonHeightLarge,
                ),
                child: actions[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Плашка окна: серая по умолчанию, цветная — с [color].
class DialogNote extends StatelessWidget {
  final String text;
  final Color? color;

  const DialogNote({super.key, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = this.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: (color ?? cs.onSurfaceVariant).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Text(
        text,
        style: tt.bodySmall?.copyWith(color: color ?? cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Главная кнопка окна — заливка основным цветом, для необратимого
/// ([destructive]) — красным.
class DialogPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onPressed;

  const DialogPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.destructive = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = destructive
        ? ElevatedButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          )
        : null;
    final text = Text(label, textAlign: TextAlign.center);
    final icon = this.icon;
    if (icon == null) {
      return ElevatedButton(style: style, onPressed: onPressed, child: text);
    }
    return ElevatedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: text,
    );
  }
}

/// Вторая кнопка окна («Отмена», «Закрыть») — заливка серым, а не обводка:
/// обе кнопки одной «плотности».
class DialogSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const DialogSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.surfaceContainer,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Сообщение с одной кнопкой «Понятно» (или [buttonLabel]).
Future<void> showInfoDialog(
  BuildContext context, {
  required IconData icon,
  required DialogTone tone,
  required String title,
  String? body,
  Widget? content,
  String? note,
  String? buttonLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => InfoDialog(
      icon: icon,
      tone: tone,
      title: title,
      body: body,
      content: content,
      note: note,
      actions: [
        DialogPrimaryButton(
          label: buttonLabel ?? DialogStrings.understand,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Подтверждение: главная кнопка [confirmLabel] сверху, [cancelLabel] под
/// ней. `true` — только по главной кнопке; закрытие мимо окна или «назад» —
/// как отказ.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required DialogTone tone,
  required String title,
  String? body,
  Widget? content,
  String? note,
  bool noteTinted = false,
  required String confirmLabel,
  IconData? confirmIcon,
  bool destructive = false,
  String? cancelLabel,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => InfoDialog(
      icon: icon,
      tone: tone,
      title: title,
      body: body,
      content: content,
      note: note,
      noteTinted: noteTinted,
      actions: [
        DialogPrimaryButton(
          label: confirmLabel,
          icon: confirmIcon,
          destructive: destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        DialogSecondaryButton(
          label: cancelLabel ?? DialogStrings.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  return result == true;
}
