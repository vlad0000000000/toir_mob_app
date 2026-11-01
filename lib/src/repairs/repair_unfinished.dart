import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../http/api.dart';
import '../model/repair.dart';
import 'repair_status_pill.dart';

/// Незакрытые ремонты одного оборудования — подсказка «уже есть ремонты» на
/// форме создания (макет 14b) и на экране скана (14h).
///
/// Ремонтов по оборудованию может быть несколько (механика и электрика
/// сразу, бэкенд `7be3756`), и создание это не блокирует — блок только
/// показывает, кто уже работает и когда.
class UnfinishedRepairs {
  /// По дате начала: сначала идущие, потом запланированные.
  final List<Repair> repairs;

  /// Связи нет — показаны ремонты из офлайн-кэша, то есть только свои.
  final bool fromCache;

  const UnfinishedRepairs(this.repairs, {this.fromCache = false});

  static const UnfinishedRepairs empty = UnfinishedRepairs([]);
}

/// Незакрытые ремонты оборудования [equipmentUuid].
///
/// В сети — с сервера (`GET /v1/repairs/?equipment_uuid=…&status=…`). Сервер
/// отдаёт только ремонты в области пользователя: ремонт другого направления в
/// подсказку не попадёт (п. 2 `docs/backend-unplanned-repairs.md`). Без сети —
/// из кэша: там только ремонты самого обходчика, о чём блок и говорит.
Future<UnfinishedRepairs> loadUnfinishedRepairs(String equipmentUuid) async {
  try {
    final page = await API().getRepairsPage(
      statuses: const [
        RepairStatuses.scheduled,
        RepairStatuses.open,
        RepairStatuses.underReview,
      ],
      equipmentUuid: equipmentUuid,
    );
    return UnfinishedRepairs(_sorted([
      for (final repair in page.items)
        // Фильтр по оборудованию у сервера прошлой версии мог и не
        // сработать — сверяем сами.
        if (repair.equipmentUuid == equipmentUuid && repair.isUnfinished)
          repair,
    ]));
  } catch (_) {
    return UnfinishedRepairs(
      _sorted([
        for (final repair in GlobalState.dataProvider.repairs)
          if (repair.equipmentUuid == equipmentUuid && repair.isUnfinished)
            repair,
      ]),
      fromCache: true,
    );
  }
}

List<Repair> _sorted(List<Repair> repairs) =>
    repairs..sort((a, b) => a.startedAt.compareTo(b.startedAt));

/// Ремонты, начинающиеся в ту же минуту, что [start]: время вводится с
/// точностью до минуты, поэтому и сравниваем по ней.
List<Repair> sameStartRepairs(List<Repair> repairs, DateTime start) {
  String minute(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  final target = minute(start);
  return [
    for (final repair in repairs)
      if (minute(repair.startedAt) == target) repair,
  ];
}

/// Предупреждение под датой начала (макет 14c-2): на это время уже есть
/// ремонт. Создание не блокирует — над одним оборудованием могут работать
/// мастера разных направлений. Тексты — как в веб-админке.
String? sameStartWarning(List<Repair> repairs) {
  if (repairs.isEmpty) return null;
  if (repairs.length > 1) {
    return RepairStrings.sameStartMany(repairs.map(_repairRef).join(', '));
  }
  final repair = repairs.single;
  return RepairStrings.sameStartOne(
    scheduled: repair.isScheduled,
    ref: _repairRef(repair),
  );
}

String _repairRef(Repair repair) {
  final direction = repair.responsibleRoleName;
  return direction == null || direction.isEmpty
      ? '№${repair.id}'
      : '№${repair.id} ($direction)';
}

/// Блок «Незакрытые ремонты по оборудованию: N» — статус, номер, начало,
/// направление и ответственный. Пустой список — блока нет.
class UnfinishedRepairsBlock extends StatelessWidget {
  final UnfinishedRepairs data;

  /// Нажатие на ремонт — открыть его карточку. `null` — строки не нажимаются.
  final ValueChanged<Repair>? onOpen;

  const UnfinishedRepairsBlock({super.key, required this.data, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final repairs = data.repairs;
    if (repairs.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          RepairStrings.unfinishedTitle(repairs.length),
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        if (data.fromCache) ...[
          const SizedBox(height: 4),
          Text(
            RepairStrings.unfinishedOffline,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppConstants.spacingSM),
        for (var i = 0; i < repairs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingSM),
          _UnfinishedRepairRow(
            repair: repairs[i],
            onTap: onOpen == null ? null : () => onOpen!(repairs[i]),
          ),
        ],
      ],
    );
  }
}

class _UnfinishedRepairRow extends StatelessWidget {
  final Repair repair;
  final VoidCallback? onTap;

  const _UnfinishedRepairRow({required this.repair, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final start = DateFormat('dd.MM HH:mm').format(repair.startedAt.toLocal());
    final direction = repair.responsibleRoleName;
    final person = (repair.responsibleUserFullname ?? '').trim();
    final who = [
      if (direction != null && direction.isNotEmpty) direction,
      person.isNotEmpty ? person : RepairStrings.unfinishedNoResponsible,
    ].join(' · ');
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  RepairStatusPill(status: repair.status, compact: true),
                  const SizedBox(width: AppConstants.spacingSM),
                  Expanded(
                    child: Text(
                      RepairStrings.unfinishedStart(
                        id: repair.id,
                        scheduled: repair.isScheduled,
                        start: start,
                      ),
                      style:
                          tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(who, style: tt.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
