import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';

/// Плашка в карточке взятой задачи по удалённому оборудованию: что здесь
/// можно (завершить задачу) и чего нельзя (ремонт, заявка). Вид — как у
/// всех плашек-подсказок, без значка ([TaskPauseBanner]).
class RemovedEquipmentBanner extends StatelessWidget {
  const RemovedEquipmentBanner({super.key});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            RemovedEquipmentStrings.bannerTitle,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            RemovedEquipmentStrings.bannerBody,
            style: tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}
