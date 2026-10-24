import 'package:flutter/material.dart';

import '../design/app_constants.dart';

/// Информационное окно в стиле приложения: значок в цветном квадрате,
/// заголовок и пояснение по центру, необязательная плашка и кнопки во всю
/// ширину друг под другом.
///
/// Тот же вид, что у окна закрытого доступа (`login/access_blocked_dialog.dart`)
/// и диалогов ремонтов. Стандартный `AlertDialog` и `Dialogs.notify` выглядят
/// в приложении чужими: другой фон, кнопки в ряд, нет значка.
class InfoDialog extends StatelessWidget {
  final IconData icon;

  /// Цвет значка и его подложка — по смыслу окна: оранжевый для «нельзя, но
  /// поправимо», основной для простого предупреждения.
  final Color accent;
  final Color accentContainer;

  final String title;
  final String body;

  /// Плашка под пояснением — второстепенное: что делать, что ничего не
  /// пропало. `null` — плашки нет.
  final String? note;

  /// Кнопки сверху вниз; первая — главная. Во всю ширину каждая: в ряд
  /// длинная подпись переносилась бы и обрезалась.
  final List<Widget> actions;

  const InfoDialog({
    super.key,
    required this.icon,
    required this.accent,
    required this.accentContainer,
    required this.title,
    required this.body,
    this.note,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
                        color: accentContainer,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLG),
                      ),
                      child: Icon(icon, size: 36, color: accent),
                    ),
                    const SizedBox(height: AppConstants.spacingMD),
                    Text(
                      title,
                      style:
                          tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppConstants.spacingSM),
                    Text(body,
                        style: tt.bodyLarge, textAlign: TextAlign.center),
                    if (note != null) ...[
                      const SizedBox(height: AppConstants.spacingMD),
                      // Плашка нейтральная, без значка и по центру — как в
                      // окне закрытого доступа.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppConstants.spacingMD),
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                        ),
                        child: Text(
                          note,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingLG),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingSM),
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeightLarge,
                child: actions[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
