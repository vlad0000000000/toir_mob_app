import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../http/api.dart';
import '../model/pending_repair.dart';
import '../model/repair.dart';
import 'repair_error_messages.dart';
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

  /// Черновики из очереди отправки, о которых сервер ещё не знает. Они уже
  /// держат оборудование «В ремонте» ([DataProvider.hasHoldingRepairDraft]),
  /// и без них в блоке обходчик видел запертое состояние, но не видел
  /// ремонта, который его запер.
  final List<PendingRepair> drafts;

  /// Связи нет — показаны ремонты из офлайн-кэша, то есть только свои.
  final bool fromCache;

  const UnfinishedRepairs(
    this.repairs, {
    this.drafts = const [],
    this.fromCache = false,
  });

  static const UnfinishedRepairs empty = UnfinishedRepairs([]);

  bool get isEmpty => repairs.isEmpty && drafts.isEmpty;
}

/// Незакрытые ремонты оборудования [equipmentUuid].
///
/// В сети — с сервера (`GET /v1/repairs/?equipment_uuid=…&status=…`). Сервер
/// отдаёт только ремонты в области пользователя: ремонт другого направления в
/// подсказку не попадёт (п. 2 `docs/backend-unplanned-repairs.md`). Без сети —
/// из кэша: там только ремонты самого обходчика, о чём блок и говорит.
///
/// Ремонты отдаются целиком, с подробностями (см. [_withDetails]): из блока
/// их открывают, и карточка должна сразу встать полной.
///
/// Блок рисуется в три шага, чтобы не ждать сети: экран начинает с
/// [cachedUnfinishedRepairs], [onList] получает ответ списка (подробности —
/// из кэша, где они есть), а результат — с дочитанными подробностями.
Future<UnfinishedRepairs> loadUnfinishedRepairs(
  String equipmentUuid, {
  ValueChanged<UnfinishedRepairs>? onList,
}) async {
  final List<Repair> repairs;
  try {
    final page = await API().getRepairsPage(
      statuses: const [
        RepairStatuses.scheduled,
        RepairStatuses.open,
        RepairStatuses.underReview,
      ],
      equipmentUuid: equipmentUuid,
    );
    repairs = _unfinishedOf(equipmentUuid, page.items.map(_withCachedDetails));
  } catch (_) {
    return cachedUnfinishedRepairs(equipmentUuid, offline: true);
  }
  if (repairs.every((repair) => repair.detailsLoaded)) {
    return _withDrafts(equipmentUuid, repairs);
  }
  onList?.call(_withDrafts(equipmentUuid, repairs));
  final detailed = await Future.wait(repairs.map(_withDetails));
  // Пока дочитывались подробности, ремонт могли закрыть, удалить или начать
  // досрочно: полный ответ свежее списка — фильтруем и сортируем ещё раз.
  return _withDrafts(
    equipmentUuid,
    _unfinishedOf(equipmentUuid, detailed.whereType<Repair>()),
  );
}

/// Незакрытые ремонты оборудования из офлайн-кэша — только свои, зато сразу
/// и целиком. С ними экран рисует блок вместе с карточкой, не дожидаясь
/// сервера.
///
/// [offline] — сервер не ответил: блок подпишет, что показаны только ваши
/// ремонты. Пока запрос летит, подписи нет — это ещё не «без связи».
UnfinishedRepairs cachedUnfinishedRepairs(
  String equipmentUuid, {
  bool offline = false,
}) {
  return _withDrafts(
    equipmentUuid,
    _unfinishedOf(equipmentUuid, GlobalState.dataProvider.repairs),
    fromCache: offline,
  );
}

/// [data] с черновиками, какие лежат в очереди сейчас. Ремонты те же — их
/// перечитывает [loadUnfinishedRepairs], а очередь локальная и читается
/// сразу: после возврата из карточки удалённый там черновик не должен
/// висеть в блоке, пока идёт запрос.
UnfinishedRepairs withCurrentDrafts(
  String equipmentUuid,
  UnfinishedRepairs data,
) =>
    _withDrafts(equipmentUuid, data.repairs, fromCache: data.fromCache);

/// Незакрытые ремонты оборудования [equipmentUuid] из [repairs], по дате
/// начала. Фильтр по оборудованию у сервера прошлой версии мог и не
/// сработать — сверяем сами.
List<Repair> _unfinishedOf(String equipmentUuid, Iterable<Repair> repairs) {
  return [
    for (final repair in repairs)
      if (repair.equipmentUuid == equipmentUuid && repair.isUnfinished) repair,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
}

/// [repairs] и черновики оборудования из очереди отправки.
///
/// Черновик, чей ремонт сервер уже создал (`serverUuid`), показываем, только
/// если самого ремонта в блоке нет — без связи кэш о нём мог ещё не узнать.
/// Иначе один ремонт стоял бы в блоке дважды.
UnfinishedRepairs _withDrafts(
  String equipmentUuid,
  List<Repair> repairs, {
  bool fromCache = false,
}) {
  final known = {for (final repair in repairs) repair.uuid};
  final drafts = [
    for (final draft in GlobalState.dataProvider.pendingRepairs)
      if (draft.equipmentUuid == equipmentUuid &&
          (draft.serverUuid == null || !known.contains(draft.serverUuid)))
        draft,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return UnfinishedRepairs(repairs, drafts: drafts, fromCache: fromCache);
}

/// [repair] из списка с подробностями из кэша, если они там есть.
Repair _withCachedDetails(Repair repair) => repair.detailsLoaded
    ? repair
    : repair.withDetailsFrom(
        GlobalState.dataProvider.repairBox.get(repair.uuid),
      );

/// [repair] из списка — с комментарием, расходом и фото.
///
/// Список (`RepairListSchema`) их не отдаёт, а карточка, открытая с таким
/// ремонтом, на миг показывала полосу «данные могли устареть» и «расход
/// неизвестен», пока не приходил полный ответ, — мелькание. Свой ремонт
/// обычно уже лежит в кэше целиком ([_withCachedDetails]), остальные
/// дочитываем (`GET /v1/repairs/{uuid}`; ремонтов у оборудования единицы).
///
/// `null` — ремонта больше нет или он ушёл из области обходчика (404, «нет
/// доступа»): открыть его всё равно нельзя, в блоке ему не место. Прочая
/// ошибка (нет связи) — остаётся запись из списка, карточка дочитает сама.
Future<Repair?> _withDetails(Repair repair) async {
  if (repair.detailsLoaded) return repair;
  try {
    return await API().getRepair(repair.uuid);
  } catch (e) {
    return isRepairOutOfScope(e) ? null : repair;
  }
}

/// Время вводится с точностью до минуты, поэтому и сравниваем по ней.
String _minute(DateTime value) =>
    DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());

/// Ремонты, начинающиеся в ту же минуту, что [start].
List<Repair> sameStartRepairs(List<Repair> repairs, DateTime start) {
  final target = _minute(start);
  return [
    for (final repair in repairs)
      if (_minute(repair.startedAt) == target) repair,
  ];
}

/// Черновики из очереди, начинающиеся в ту же минуту, что [start]: сервер о
/// них ещё не знает, но ремонт по ним уже заведён.
List<PendingRepair> sameStartDrafts(
    List<PendingRepair> drafts, DateTime start) {
  final target = _minute(start);
  return [
    for (final draft in drafts)
      if (_minute(draft.startedAt) == target) draft,
  ];
}

/// Предупреждение под датой начала (макет 14c-2): на это время уже есть
/// ремонт. Создание не блокирует — над одним оборудованием могут работать
/// мастера разных направлений. Тексты — как в веб-админке; неотправленный
/// черновик номера не имеет и называется черновиком.
String? sameStartWarning(
  List<Repair> repairs, {
  List<PendingRepair> drafts = const [],
}) {
  final total = repairs.length + drafts.length;
  if (total == 0) return null;
  if (total > 1) {
    return RepairStrings.sameStartMany([
      ...repairs.map(_repairRef),
      for (final _ in drafts) RepairStrings.sameStartDraftRef,
    ].join(', '));
  }
  if (drafts.isNotEmpty) return RepairStrings.sameStartDraft;
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
/// направление и ответственный; ниже — неотправленные черновики. Пусто —
/// блока нет.
class UnfinishedRepairsBlock extends StatelessWidget {
  final UnfinishedRepairs data;

  /// Нажатие на ремонт — открыть его карточку. `null` — строки не нажимаются.
  final ValueChanged<Repair>? onOpen;

  /// Нажатие на черновик — открыть его карточку. `null` — не нажимаются.
  final ValueChanged<PendingRepair>? onOpenDraft;

  const UnfinishedRepairsBlock({
    super.key,
    required this.data,
    this.onOpen,
    this.onOpenDraft,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final repairs = data.repairs;
    final drafts = data.drafts;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rows = <Widget>[
      for (final repair in repairs)
        _UnfinishedRepairRow(
          repair: repair,
          onTap: onOpen == null ? null : () => onOpen!(repair),
        ),
      for (final draft in drafts)
        _UnfinishedDraftRow(
          draft: draft,
          onTap: onOpenDraft == null ? null : () => onOpenDraft!(draft),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          RepairStrings.unfinishedTitle(rows.length),
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
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingSM),
          rows[i],
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
    final start = DateFormat('dd.MM HH:mm').format(repair.startedAt.toLocal());
    final direction = repair.responsibleRoleName;
    final person = (repair.responsibleUserFullname ?? '').trim();
    final who = [
      if (direction != null && direction.isNotEmpty) direction,
      person.isNotEmpty ? person : RepairStrings.unfinishedNoResponsible,
    ].join(' · ');
    return _UnfinishedRow(
      pill: RepairStatusPill(status: repair.status, compact: true),
      title: RepairStrings.unfinishedStart(
        id: repair.id,
        scheduled: repair.isScheduled,
        start: start,
      ),
      subtitle: who,
      onTap: onTap,
    );
  }
}

/// Черновик из очереди: номера у него нет, вместо ответственного — ждёт ли
/// он отправки или сервер его отклонил.
class _UnfinishedDraftRow extends StatelessWidget {
  final PendingRepair draft;
  final VoidCallback? onTap;

  const _UnfinishedDraftRow({required this.draft, this.onTap});

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('dd.MM HH:mm').format(draft.startedAt.toLocal());
    return _UnfinishedRow(
      pill: const RepairDraftPill(),
      title: RepairStrings.unfinishedDraftStart(
        scheduled: draft.isScheduledAt(DateTime.now()),
        start: start,
      ),
      subtitle: draft.isRejected
          ? RepairStrings.unfinishedDraftRejected
          : RepairStrings.unfinishedDraftWaiting,
      onTap: onTap,
    );
  }
}

/// Строка блока: пилюля и «№… · Начат …», ниже подпись, справа стрелка.
class _UnfinishedRow extends StatelessWidget {
  final Widget pill;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _UnfinishedRow({
    required this.pill,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        pill,
                        const SizedBox(width: AppConstants.spacingSM),
                        Expanded(
                          child: Text(
                            title,
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: tt.bodyMedium),
                  ],
                ),
              ),
              // Стрелка — как в вебе: строка нажимается и открывает ремонт.
              if (onTap != null) ...[
                const SizedBox(width: AppConstants.spacingSM),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
