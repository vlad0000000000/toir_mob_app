import 'dart:convert';

import '../exceptions/app_exceptions.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../model/repair_conflict.dart';

// Основа правки ремонта для `If-Match` (бэкенд `d22727e`, решение 22.11).
//
// Карточка, открытая со связью, берёт ETag состояния ремонта
// (`GET /v1/repairs/{uuid}/edit-state`) и шлёт его с правкой. Изменили ремонт
// с тех пор — сервер отвечает 412 с актуальным состоянием, и обходчик решает:
// отправить свою правку поверх или отменить её. Правка, сделанная без связи,
// уходит без `If-Match`, как раньше.

/// ETag и тело `edit-state` строкой JSON — то, что видел обходчик.
typedef RepairEditBase = ({String etag, String state});

/// Состояние [current] из ответа 412 совпадает с основой [base] во всём,
/// кроме `updated_at`.
///
/// ETag сервер считает и по времени изменения ремонта, а его сдвигают не
/// только чужие правки: фото, загруженные очередью этой же правки, и прочие
/// служебные записи. Показывать обходчику «ремонт изменили», когда ничего
/// видимого не поменялось, незачем — правку можно отправить на новый ETag
/// молча. Не разобралось — считаем, что изменили: лишний вопрос лучше, чем
/// молча затереть чужое.
bool isSameRepairEditState(String? base, Map<String, dynamic> current) {
  if (base == null || base.isEmpty) return false;
  try {
    final decoded = jsonDecode(base);
    if (decoded is! Map) return false;
    return _canonical(_withoutTimestamp(decoded)) ==
        _canonical(_withoutTimestamp(current));
  } catch (_) {
    return false;
  }
}

Map<dynamic, dynamic> _withoutTimestamp(Map<dynamic, dynamic> state) =>
    Map<dynamic, dynamic>.of(state)..remove('updated_at');

/// JSON с ключами по алфавиту на всех уровнях: порядок полей в ответах
/// сервера не гарантирован.
String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return [for (final item in value) _sorted(item)];
  return value;
}

/// Что сейчас на сервере — для блока «Ремонт изменили»: статус, комментарий
/// и число позиций расхода (`null` — расход обходчику не виден).
typedef RepairServerSnapshot = ({
  String? status,
  String comment,
  int? consumptionCount,
});

/// Разбор состояния ремонта из ответа 412 (или сохранённого в правке).
/// `null` — нечего показать.
RepairServerSnapshot? repairServerSnapshot(Object? state) {
  Object? data = state;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  if (data is! Map) return null;
  final status = data['status'];
  final comment = data['comment'];
  final consumptions = data['actual_consumptions'];
  return (
    status: status is String ? status : null,
    comment: comment is String ? comment.trim() : '',
    consumptionCount: consumptions is List ? consumptions.length : null,
  );
}

/// Состояние `edit-state` [state] — про тот же ремонт, что [repair]: статус,
/// комментарий и расход совпадают.
///
/// ETag сервер отдаёт отдельным запросом (у `GET`/`PATCH` ремонта его нет), и
/// между двумя запросами ремонт мог измениться. Тогда ETag уже про другую
/// версию: с ним правка молча затёрла бы то, чего обходчик не видел. Поэтому
/// ETag берётся, только если его состояние совпадает с показанным в карточке
/// (или с ответом нашего же `PATCH`). Расход сверяется числами: `Decimal`
/// сервер отдаёт строкой. Расход скрыт правами (`null`) — не сверяется.
bool editStateMatchesRepair(String? state, Repair repair) {
  if (state == null || state.isEmpty) return false;
  try {
    final data = jsonDecode(state);
    if (data is! Map) return false;
    if (data['status'] != repair.status) return false;
    final comment = data['comment'];
    if ((comment is String ? comment : '').trim() !=
        (repair.comment ?? '').trim()) {
      return false;
    }
    final consumptions = data['actual_consumptions'];
    if (consumptions == null) return true;
    if (consumptions is! List) return false;
    final fromState = <String, double>{};
    for (final item in consumptions) {
      if (item is! Map) return false;
      final quantity = double.tryParse('${item['quantity']}');
      if (quantity == null) return false;
      if (quantity > 0) fromState['${item['spare_part_uuid']}'] = quantity;
    }
    final fromRepair = {
      for (final item in repair.actualConsumptions)
        if (item.quantity > 0) item.sparePartUuid: item.quantity,
    };
    if (fromState.length != fromRepair.length) return false;
    for (final entry in fromState.entries) {
      final other = fromRepair[entry.key];
      if (other == null || (other - entry.value).abs() > 1e-9) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// То же для правки, которую очередь уже отправила ([sentComment],
/// [sentConsumptions], [submitted] — отправка на проверку): ETag после неё —
/// про нашу же правку, только если состояние совпадает с отправленным.
bool editStateMatchesSentEdit(
  String? state, {
  required String sentComment,
  required List<RepairConsumption> sentConsumptions,
  required bool submitted,
}) {
  if (state == null || state.isEmpty) return false;
  try {
    final data = jsonDecode(state);
    if (data is! Map) return false;
    final status = data['status'];
    if (status is! String) return false;
    if (submitted && status != RepairStatuses.underReview) return false;
    return editStateMatchesRepair(
      state,
      Repair(
        id: 0,
        uuid: '',
        status: status,
        equipmentUuid: '',
        equipmentName: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        comment: sentComment,
        actualConsumptions: sentConsumptions,
      ),
    );
  } catch (_) {
    return false;
  }
}

/// ETag, который заведомо не совпадёт с серверным: им помечается правка,
/// чья основа неизвестна или устарела (ремонт изменили между загрузкой
/// карточки и запросом ETag, ETag после нашей отправки не удалось получить).
/// Сервер ответит 412 с актуальным состоянием, и обходчик решит сам — молча
/// затереть чужое изменение нельзя.
const String unknownBaseEtag = '"mobile-unknown-base"';

/// Ошибка `GET /repairs/{uuid}/edit-state` значит, что сервер его не знает
/// (прошлая версия бэкенда: 404/405) — тогда правка уходит без `If-Match`,
/// как раньше. Любая другая (нет связи, таймаут, 5xx) — временная: основа
/// становится «неизвестной» ([unknownBaseEtag]), а не пропадает.
bool isEditStateUnsupported(Object error) =>
    error is ServerFailureException &&
    (error.statusCode == 404 || error.statusCode == 405);

/// Откуда карточка берёт основу `If-Match` для правки ремонта.
enum EditBaseSource {
  /// ETag карточки (`edit-state`, загруженный с формой). Пока он грузится,
  /// сохранение ждёт его, — иначе правка ушла бы без проверки версии.
  card,

  /// Своя основа правки, уже лежащей в очереди.
  queued,

  /// Состояние из ответа 412, которое обходчик видел в блоке «Сейчас на
  /// сервере».
  serverConflict,

  /// Без `If-Match`: правка сделана без связи, основы нет.
  none,
}

/// Откуда брать основу для правки карточки: [queued] — правка этого ремонта
/// в очереди, [formSource] — версия ремонта, из которой заполнена форма.
///
/// Запись в очереди без своей основы, но с полями, равными серверным, — в ней
/// остались только снимки (после онлайн-сохранения): защищать в ней нечего,
/// основа — карточки, и сохранение ждёт её загрузки так же, как при пустой
/// очереди.
EditBaseSource editBaseSource({
  required PendingRepairUpdate? queued,
  required Repair? formSource,
}) {
  if (queued == null) return EditBaseSource.card;
  if (queued.isRejected &&
      queued.kind == RepairConflictKind.changedOnServer &&
      queued.serverEtag != null) {
    return EditBaseSource.serverConflict;
  }
  if (queued.baseEtag != null) return EditBaseSource.queued;
  final onlyPhotos = formSource != null &&
      !queued.submitForReview &&
      queued.sameFormAs(
        comment: formSource.comment ?? '',
        consumptions: formSource.actualConsumptions,
        submitForReview: false,
      );
  return onlyPhotos ? EditBaseSource.card : EditBaseSource.none;
}

/// У двух версий ремонта одни и те же редактируемые поля: статус, комментарий
/// и расход (позиции с нулевым количеством не считаются). Нужно, когда форма
/// перезаполняется из кэша без связи: другая версия — и ETag карточки уже не
/// про то, что видит обходчик.
bool sameEditableFields(Repair a, Repair b) {
  if (a.status != b.status) return false;
  if ((a.comment ?? '').trim() != (b.comment ?? '').trim()) return false;
  Map<String, double> quantities(Repair repair) => {
        for (final item in repair.actualConsumptions)
          if (item.quantity > 0) item.sparePartUuid: item.quantity,
      };
  final left = quantities(a);
  final right = quantities(b);
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null || (other - entry.value).abs() > 1e-9) return false;
  }
  return true;
}
