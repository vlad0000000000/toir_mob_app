import 'package:flutter/material.dart';
import '../design/app_constants.dart';

/// Универсальный empty-state для списков (нет задач / нет уведомлений и т.д.).
/// Иконка-«монета» на tonal surface + заголовок + подсказка + опциональный CTA.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.padding = const EdgeInsets.all(AppConstants.spacingXL),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppConstants.spacingLG),
            Text(
              title,
              style: tt.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppConstants.spacingSM),
              Text(
                hint!,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppConstants.spacingLG),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
