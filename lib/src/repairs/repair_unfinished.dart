import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../exceptions/app_exceptions.dart';
import '../http/api.dart';
import '../model/pending_repair.dart';
import '../model/repair.dart';
import '../model/unfinished_repair_hint.dart';
import '../utils/offline_error.dart';
import 'repair_error_messages.dart';
import 'repair_status_pill.dart';

/// Незакрытые ремонты одного оборудования — подсказка «уже есть ремонты» на
/// форме создания (макет 14b) и на экране скана (14h).
///
/// Ремонтов по оборудованию может быть несколько (механика и электрика
/// сразу, бэкенд `7be3756`), и создание это не блокирует — блок только
/// показывает, кто уже работает и когда.
///
/// Строки — подсказки ([hints]) по всем службам. Ремонты, которые обходчик
/// может открыть, лежат ещё и целиком ([details]): карточка из блока должна
/// встать сразу полной, без мелькания.
class UnfinishedRepairs {
  /// По дате начала, затем по номеру: сначала идущие, потом запланированные.
  final List<UnfinishedRepairHint> hints;

  /// Полные ремонты по uuid — только для подсказок с `canOpen`. Нет записи —
  /// подробности не дочитались, карточка загрузит их сама.
  final Map<String, Repair> details;

  /// Черновики из очереди отправки, о которых сервер ещё не знает. Они уже
  /// держат оборудование «В ремонте» ([DataProvider.hasHoldingRepairDraft]),
  /// и без них в блоке обходчик видел запертое состояние, но не видел
  /// ремонта, который его запер.
  final List<PendingRepair> drafts;

  /// Связи нет — показаны ремонты из офлайн-кэша, то есть только свои.
  final bool fromCache;

  /// Сколько незакрытых ремонтов у оборудования всего, по всем службам, —
  /// из счётчиков справочника ([InventoryRecord.unfinishedRepairsTotal]).
  /// Только без связи: кэш знает свои, а это число — сколько их на самом
  /// деле. `null` — неизвестно.
  final int? offlineTotal;

  const UnfinishedRepairs({
    this.hints = const [],
    this.details = const {},
    this.drafts = const [],
    this.fromCache = false,
    this.offlineTotal,
  });

  static const UnfinishedRepairs empty = UnfinishedRepairs();

  bool get isEmpty =>
      hints.isEmpty && drafts.isEmpty && (offlineTotal ?? 0) == 0;

  /// Ремонтов других служб без связи не видно, но счётчики справочника о
  /// них знают — сколько не показано. `0` — показаны все.
  int get hiddenOffline {
    final total = offlineTotal;
    if (!fromCache || total == null || total <= hints.length) return 0;
    return total - hints.length;
  }
}

/// Незакрытые ремонты оборудования [equipmentUuid].
///
/// * **В сети** — `GET /v1/company/equipment/{uuid}/unfinished-repairs`
///   (бэкенд `8a88247`): ремонты всех служб. Чужой ремонт (`can_open:
///   false`) — строка с замком, без перехода.
/// * **Сервер прошлой версии** (адреса нет) — прежний
///   `GET /v1/repairs/?equipment_uuid=…`: только ремонты в области обходчика.
/// * **Без сети** — из кэша: там только ремонты самого обходчика, о чём блок
///   и говорит.
///
/// Блок рисуется в три шага, чтобы не ждать сети: экран начинает с
/// [cachedUnfinishedRepairs], [onList] получает ответ сервера (подробности —
/// из кэша, где они есть), а результат — с дочитанными подробностями.
Future<UnfinishedRepairs> loadUnfinishedRepairs(
  String equipmentUuid, {
  ValueChanged<UnfinishedRepairs>? onList,
}) async {
  var hints = <UnfinishedRepairHint>[];
  final details = <String, Repair>{};
  try {
    final fresh = await API().getEquipmentUnfinishedRepairs(equipmentUuid);
    if (fresh != null) {
      hints = _sortedHints(fresh.where((hint) => hint.isUnfinished));
      for (final hint in hints) {
        if (!hint.canOpen) continue;
        final cached = GlobalState.dataProvider.repairBox.get(hint.uuid);
        // Кэш годится, только если он не отстал от подсказки: подсказка
        // свежая, а синхронизации после правки в админке могло ещё не быть.
        // Отставший кэш карточка показала бы на миг со старым статусом и
        // формой, а потом перерисовала, — то же мелькание. Тогда дочитываем.
        if (cached != null &&
            cached.detailsLoaded &&
            cached.status == hint.status &&
            cached.startedAt.isAtSameMomentAs(hint.startedAt)) {
          details[hint.uuid] = cached;
        }
      }
    } else {
      final page = await API().getRepairsPage(
        statuses: const [
          RepairStatuses.scheduled,
          RepairStatuses.open,
          RepairStatuses.underReview,
        ],
        equipmentUuid: equipmentUuid,
      );
      final repairs =
          _unfinishedOf(equipmentUuid, page.items.map(_withCachedDetails));
      hints = [
        for (final repair in repairs) UnfinishedRepairHint.fromRepair(repair)
      ];
      for (final repair in repairs) {
        details[repair.uuid] = repair;
      }
    }
  } catch (e) {
    // Свои ремонты из кэша — в обоих случаях, но «Без связи» пишем, только
    // если связи и правда нет: на отказ сервера (500, 403) подпись звала бы
    // проверить интернет, который на месте.
    return cachedUnfinishedRepairs(equipmentUuid, offline: isOfflineError(e));
  }
  final missing = [
    for (final hint in hints)
      if (hint.canOpen && !(details[hint.uuid]?.detailsLoaded ?? false)) hint,
  ];
  if (missing.isEmpty) return _withDrafts(equipmentUuid, hints, details);
  onList?.call(_withDrafts(equipmentUuid, hints, Map.of(details)));

  final fetched = {
    for (final (index, result)
        in (await Future.wait(missing.map((h) => _fetchDetails(h.uuid))))
            .indexed)
      missing[index].uuid: result,
  };
  // Пока дочитывались подробности, ремонт могли закрыть, удалить, начать
  // досрочно или увести из области обходчика: полный ответ свежее
  // подсказки — по нему и решаем, что показывать.
  final next = <UnfinishedRepairHint>[];
  for (final hint in hints) {
    final result = fetched[hint.uuid];
    if (result == null) {
      next.add(hint);
      continue;
    }
    switch (result) {
      case _Details(:final repair):
        if (repair.equipmentUuid != equipmentUuid || !repair.isUnfinished) {
          details.remove(hint.uuid);
          continue;
        }
        details[hint.uuid] = repair;
        next.add(UnfinishedRepairHint.fromRepair(repair));
      case _Gone():
        details.remove(hint.uuid);
      case _Locked():
        details.remove(hint.uuid);
        next.add(hint.locked());
      case _Failed():
        // Нет связи и т. п. — строка остаётся, карточка дочитает сама.
        next.add(hint);
    }
  }
  return _withDrafts(equipmentUuid, _sortedHints(next), details);
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
  final provider = GlobalState.dataProvider;
  final repairs = _unfinishedOf(equipmentUuid, provider.repairs);
  int? total;
  if (offline) {
    for (final record in provider.inventoryRecords) {
      if (record.uuid == equipmentUuid) total = record.unfinishedRepairsTotal;
    }
  }
  return _withDrafts(
    equipmentUuid,
    [for (final repair in repairs) UnfinishedRepairHint.fromRepair(repair)],
    {for (final repair in repairs) repair.uuid: repair},
    fromCache: offline,
    offlineTotal: total,
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
    _withDrafts(equipmentUuid, data.hints, data.details,
        fromCache: data.fromCache, offlineTotal: data.offlineTotal);

/// Незакрытые ремонты оборудования [equipmentUuid] из [repairs], по дате
/// начала. Фильтр по оборудованию у сервера прошлой версии мог и не
/// сработать — сверяем сами.
List<Repair> _unfinishedOf(String equipmentUuid, Iterable<Repair> repairs) {
  return [
    for (final repair in repairs)
      if (repair.equipmentUuid == equipmentUuid && repair.isUnfinished) repair,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
}

/// Порядок сервера: по дате начала, затем по номеру.
List<UnfinishedRepairHint> _sortedHints(Iterable<UnfinishedRepairHint> hints) {
  return hints.toList()
    ..sort((a, b) {
      final byStart = a.startedAt.compareTo(b.startedAt);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
}

/// [hints] с [details] и черновики оборудования из очереди отправки.
///
/// Черновик, чей ремонт сервер уже создал (`serverUuid`), показываем, только
/// если самого ремонта в блоке нет — без связи кэш о нём мог ещё не узнать.
/// Иначе один ремонт стоял бы в блоке дважды.
UnfinishedRepairs _withDrafts(
  String equipmentUuid,
  List<UnfinishedRepairHint> hints,
  Map<String, Repair> details, {
  bool fromCache = false,
  int? offlineTotal,
}) {
  final known = {for (final hint in hints) hint.uuid};
  final drafts = [
    for (final draft in GlobalState.dataProvider.pendingRepairs)
      if (draft.equipmentUuid == equipmentUuid &&
          (draft.serverUuid == null || !known.contains(draft.serverUuid)))
        draft,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return UnfinishedRepairs(
    hints: hints,
    details: details,
    drafts: drafts,
    fromCache: fromCache,
    offlineTotal: offlineTotal,
  );
}

/// [repair] из списка с подробностями из кэша, если они там есть.
Repair _withCachedDetails(Repair repair) => repair.detailsLoaded
    ? repair
    : repair.withDetailsFrom(
        GlobalState.dataProvider.repairBox.get(repair.uuid),
      );

/// Итог дочитывания подробностей одного ремонта — см. [_fetchDetails].
sealed class _DetailsResult {
  const _DetailsResult();
}

class _Details extends _DetailsResult {
  final Repair repair;
  const _Details(this.repair);
}

/// Ремонта больше нет (404): в блоке ему не место.
class _Gone extends _DetailsResult {
  const _Gone();
}

/// Ремонт есть, но карточку сервер не отдаёт: строка остаётся с замком.
class _Locked extends _DetailsResult {
  const _Locked();
}

/// Не дочиталось по другой причине (нет связи).
class _Failed extends _DetailsResult {
  const _Failed();
}

/// Полный ремонт [uuid] — с комментарием, расходом и фото
/// (`GET /v1/repairs/{uuid}`).
///
/// Ни список ремонтов, ни подсказка их не отдают, а карточка, открытая без
/// них, на миг показывала полосу «данные могли устареть» и «расход
/// неизвестен», пока не приходил полный ответ, — мелькание. Свой ремонт
/// обычно уже лежит в кэше целиком, сюда попадают остальные (ремонтов у
/// оборудования единицы).
Future<_DetailsResult> _fetchDetails(String uuid) async {
  try {
    return _Details(await API().getRepair(uuid));
  } catch (e) {
    if (e is ServerFailureException &&
        e is! AccessDeniedException &&
        e.statusCode == 404 &&
        repairErrorMessage(e) != repairNoAccessMessage) {
      return const _Gone();
    }
    return isRepairOutOfScope(e) ? const _Locked() : const _Failed();
  }
}

/// Время вводится с точностью до минуты, поэтому и сравниваем по ней.
String _minute(DateTime value) =>
    DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());

/// Ремонты (всех служб), начинающиеся в ту же минуту, что [start].
List<UnfinishedRepairHint> sameStartRepairs(
  List<UnfinishedRepairHint> hints,
  DateTime start,
) {
  final target = _minute(start);
  return [
    for (final hint in hints)
      if (_minute(hint.startedAt) == target) hint,
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
/// ремонт — в том числе другой службы. Создание не блокирует — над одним
/// оборудованием могут работать мастера разных направлений. Тексты — как в
/// веб-админке; неотправленный черновик номера не имеет и называется
/// черновиком.
String? sameStartWarning(
  List<UnfinishedRepairHint> repairs, {
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

String _repairRef(UnfinishedRepairHint repair) {
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

  /// Нажатие на ремонт — открыть его карточку: uuid и, если дочитан, полный
  /// ремонт (иначе карточка загрузит его сама). `null` — строки не
  /// нажимаются. Ремонт другой службы не открывается вовсе — у него замок.
  final void Function(String uuid, Repair? repair)? onOpen;

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rows = <Widget>[
      for (final hint in data.hints)
        _UnfinishedRepairRow(
          hint: hint,
          onTap: onOpen == null || !hint.canOpen
              ? null
              : () => onOpen!(hint.uuid, data.details[hint.uuid]),
        ),
      for (final draft in data.drafts)
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
          RepairStrings.unfinishedTitle(rows.length + data.hiddenOffline),
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        if (data.fromCache) ...[
          const SizedBox(height: 4),
          Text(
            data.hiddenOffline > 0
                ? RepairStrings.unfinishedOfflineHidden(data.hiddenOffline)
                : RepairStrings.unfinishedOffline,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (rows.isNotEmpty) const SizedBox(height: AppConstants.spacingSM),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingSM),
          rows[i],
        ],
      ],
    );
  }
}

class _UnfinishedRepairRow extends StatelessWidget {
  final UnfinishedRepairHint hint;
  final VoidCallback? onTap;

  const _UnfinishedRepairRow({required this.hint, this.onTap});

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('dd.MM HH:mm').format(hint.startedAt.toLocal());
    final direction = hint.responsibleRoleName;
    final person = (hint.responsibleUserFullname ?? '').trim();
    final who = [
      if (direction != null && direction.isNotEmpty) direction,
      person.isNotEmpty ? person : RepairStrings.unfinishedNoResponsible,
      if (!hint.canOpen) RepairStrings.unfinishedNoAccess,
    ].join(' · ');
    return _UnfinishedRow(
      pill: RepairStatusPill(status: hint.status, compact: true),
      title: RepairStrings.unfinishedStart(
        id: hint.id,
        scheduled: hint.isScheduled,
        start: start,
      ),
      subtitle: who,
      onTap: onTap,
      // Чужой ремонт не прячем — подсказка, что над оборудованием уже
      // работают, нужна и без доступа к карточке. Заперт: замок и причина
      // по нажатию.
      lockedReason:
          hint.canOpen ? null : RepairStrings.unfinishedNoAccessReason,
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

/// Строка блока: пилюля и «№… · Начат …», ниже подпись, справа стрелка — или
/// замок, если строка заперта ([lockedReason]).
class _UnfinishedRow extends StatelessWidget {
  final Widget pill;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Почему строку не открыть. Задан — справа замок, нажатие показывает
  /// причину.
  final String? lockedReason;

  const _UnfinishedRow({
    required this.pill,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.lockedReason,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reason = lockedReason;
    final tap = reason == null
        ? onTap
        : () => ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(reason),
            behavior: SnackBarBehavior.floating,
          ));
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap,
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
              // Замок — строка заперта, ремонт другой службы.
              if (reason != null || onTap != null) ...[
                const SizedBox(width: AppConstants.spacingSM),
                Icon(
                  reason != null
                      ? Icons.lock_outline_rounded
                      : Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                  size: reason != null ? 20 : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
