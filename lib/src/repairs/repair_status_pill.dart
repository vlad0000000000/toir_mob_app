import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/repair.dart';

/// Пилюля «ремонт свободен» — назначен на должность, но исполнителя нет.
///
/// Показывается вместо статуса: такой ремонт всегда «Открыт», и дублировать
/// это рядом со «Свободен» незачем.
class RepairFreePill extends StatelessWidget {
  /// Уменьшенный вариант — для строки списка, где рядом стоит «№128 · дата».
  final bool compact;

  const RepairFreePill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = cs.info;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      // Без значка — как и у пилюли статуса рядом: один текст в заливке.
      child: Text(
        RepairStrings.statusFree,
        style: (compact ? tt.labelSmall : tt.labelMedium)?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Пилюля черновика — стоит на месте статуса: в списке ремонтов и в блоке
/// незакрытых ремонтов оборудования.
class RepairDraftPill extends StatelessWidget {
  const RepairDraftPill({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSM,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        // На месте статуса — «Черновик»: серверного статуса у него ещё нет
        // (п. 4.2.4 отчёта). «Не отправлено» осталось за ремонтами, которые
        // на сервере уже есть, но с неотправленными правками.
        ConflictStrings.badgeDraft,
        style: tt.labelSmall?.copyWith(
          color: cs.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Пилюля статуса ремонта. По общему образцу приложения: заливка цветом с
/// прозрачностью 0.12, точка и текст — тем же цветом на полной непрозрачности.
///
/// Лежит отдельным файлом, а не приватным виджетом экрана, потому что нужна
/// и списку ремонтов, и карточке.
class RepairStatusPill extends StatelessWidget {
  final String status;

  /// Уменьшенный вариант для строки списка: там рядом стоит «№128 · дата»,
  /// и полноразмерная пилюля выталкивала бы её на вторую строку.
  /// В шапке карточки, где места хватает, используется обычный размер.
  final bool compact;

  const RepairStatusPill({
    super.key,
    required this.status,
    this.compact = false,
  });

  /// Цвета — те же, что у пилюли статуса в веб-админке
  /// (`REPAIR_STATUS_SELECT_STYLES`): «Открыт» красный (работа не завершена),
  /// «На рассмотрении» янтарный (ждём администратора), «Закрыт» зелёный
  /// (всё сделано). Порядок неочевидный, но менять его в мобилке нельзя —
  /// обходчик и мастер должны видеть одно и то же.
  Color _color(ColorScheme cs) {
    switch (status) {
      case RepairStatuses.scheduled:
        return cs.scheduled;
      case RepairStatuses.open:
        return cs.error;
      case RepairStatuses.underReview:
        return cs.warning;
      case RepairStatuses.closed:
        return cs.success;
    }
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = _color(cs);
    // Форма по макету: полная пилюля без точки, как в админке (rounded-full).
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        RepairStatuses.displayName(status),
        style: (compact ? tt.labelSmall : tt.labelMedium)?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
