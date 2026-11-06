import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';

/// Плашка «Новые задачи приостановлены» на экранах оборудования не «В работе»
/// (правило — `isTaskGenerationPaused`). Показывать её или нет, решает экран.
class TaskPauseBanner extends StatelessWidget {
  const TaskPauseBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.warningContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pause_circle_outline_rounded, size: 20, color: cs.warning),
          const SizedBox(width: AppConstants.spacingSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  TaskPauseStrings.title,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  TaskPauseStrings.body,
                  style: tt.bodySmall?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
