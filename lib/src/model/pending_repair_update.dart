import 'package:hive_ce/hive.dart';

import 'queue_owned.dart';
import 'repair.dart';
import 'repair_conflict.dart';

/// Неотправленные правки существующего ремонта: комментарий, фактический
/// расход и, если обходчик нажал «Отправить на проверку», перевод в статус
/// «На рассмотрении».
///
/// Отличие от [PendingRepair] принципиальное: черновик создаёт новую запись, и
/// повтор безопасен благодаря `Idempotency-Key`. Здесь же правка ложится на
/// **чужую** запись, которую за время лежания в очереди мог изменить
/// администратор — закрыть ремонт или вернуть на доработку. Поэтому у правки
/// есть [baseStatus]: статус, который обходчик видел, когда правил. Если к
/// моменту отправки на сервере другой статус, PATCH отклоняется, и это
/// конфликт, а не сбой связи — разрешать его должен человек.
///
/// Одному ремонту соответствует одна правка: ключ бокса — [repairUuid], и
/// повторное сохранение накрывает предыдущее. Складывать историю правок
/// незачем — отправляем всё равно последнее состояние формы целиком.
class PendingRepairUpdate implements QueueOwned {
  final String repairUuid;

  /// Номер ремонта — только для списка и экрана конфликта, серверу не уходит.
  final int repairId;
  final String equipmentName;

  final String comment;
  final List<RepairConsumption> consumptions;

  /// Обходчик нажал «Отправить на проверку», а не просто «Сохранить».
  final bool submitForReview;

  /// Статус ремонта на момент правки. Сравнивается с серверным при разборе
  /// конфликта.
  final String baseStatus;

  final DateTime createdAt;

  /// Причина отказа сервера, уже по-русски. Пусто — правка просто ждёт связи.
  final String? lastError;

  /// Статус, который ремонт имеет на сервере сейчас. Заполняется, когда
  /// правку отклонили и удалось перечитать карточку. `null` — перечитать не
  /// вышло (связь пропала сразу после отказа).
  final String? serverStatus;

  /// Вид конфликта, определённый в момент отказа (код
  /// [RepairConflictKind.code]). От него зависит, что экран разрешения
  /// предложит сделать.
  final String? conflictKind;

  /// Пути к снятым без связи фотографиям. Путь исчезает сразу после того, как
  /// **этот** файл принят сервером: загрузка не идемпотентна, и повтор после
  /// частичной отправки продублировал бы уже принятые снимки.
  final List<String> photoPaths;

  /// Снимки, удалённые обходчиком без связи. Хранятся uuid'ами — сами файлы
  /// лежат на сервере, локально их нет.
  final List<String> deletedPhotoUuids;

  /// Обходчик, поставивший правку в очередь, — см. [Scan.ownerUuid]. Не
  /// `final`: перенос старых записей ставит его на месте.
  @override
  String? ownerUuid;

  /// Сервер, на который правка должна уйти, — см. [Scan.ownerServer]. Не
  /// `final`: перенос старых записей ставит его на месте. Входит в ключ
  /// записи (`pendingRepairUpdateKey`).
  @override
  String? ownerServer;

  /// `Idempotency-Key` и точное тело `PATCH` (строка JSON) — фиксируются
  /// перед первой отправкой полей ([frozen]) и не меняются до подтверждения
  /// (бэкенд `81f644c`).
  ///
  /// Зачем: ответ на `PATCH` мог потеряться, а ремонт уже ушёл «На
  /// рассмотрение». Повтор без ключа получал 409 «ремонт не открыт», и правка
  /// вставала в конфликт, хотя дошла. С ключом сервер узнаёт повтор и
  /// отвечает прежним результатом. Тело — то же байт в байт: другое тело с
  /// тем же ключом сервер отклонит. Новая правка обходчика ([copyWith] с
  /// полями формы) сбрасывает оба — это уже другой запрос.
  ///
  /// `null` — ещё не отправлялась или запись прошлой версии.
  final String? mutationKey;
  final String? requestBody;

  /// ETag и состояние ремонта (`edit-state` строкой JSON), которые видел
  /// обходчик, — для `If-Match` (бэкенд `d22727e`, решение 22.11). Берутся,
  /// когда карточку открыли со связью; правка без связи — без них и уходит
  /// без `If-Match`, как раньше.
  final String? baseEtag;
  final String? baseState;

  /// Что на сервере сейчас — из ответа 412 ([RepairConflictKind.changedOnServer]):
  /// ETag и состояние строкой JSON. По ним блок «Не отправлено» показывает
  /// изменения без связи, а «Отправить мою правку» шлёт правку поверх них.
  final String? serverEtag;
  final String? serverState;

  PendingRepairUpdate({
    required this.repairUuid,
    required this.repairId,
    required this.equipmentName,
    required this.baseStatus,
    required this.createdAt,
    this.comment = '',
    this.consumptions = const [],
    this.submitForReview = false,
    this.lastError,
    this.serverStatus,
    this.conflictKind,
    this.photoPaths = const [],
    this.deletedPhotoUuids = const [],
    this.ownerUuid,
    this.ownerServer,
    this.mutationKey,
    this.requestBody,
    this.baseEtag,
    this.baseState,
    this.serverEtag,
    this.serverState,
  });

  /// Поля формы те же, что у этой правки: комментарий, отправка на проверку и
  /// расход (позиция и количество по порядку). Тогда новая запись той же
  /// правки — со снимком, после разбора отказа — наследует [mutationKey] и
  /// [requestBody]: иначе повтор дошедшего, но не подтверждённого PATCH ушёл
  /// бы с новым ключом и применился второй раз.
  bool sameFormAs({
    required String comment,
    required List<RepairConsumption> consumptions,
    required bool submitForReview,
  }) {
    if (comment != this.comment || submitForReview != this.submitForReview) {
      return false;
    }
    if (consumptions.length != this.consumptions.length) return false;
    for (var i = 0; i < consumptions.length; i++) {
      final a = consumptions[i];
      final b = this.consumptions[i];
      if (a.sparePartUuid != b.sparePartUuid || a.quantity != b.quantity) {
        return false;
      }
    }
    return true;
  }

  /// Правка с зафиксированными ключом и телом — пишется в бокс **до** запроса.
  PendingRepairUpdate frozen({required String key, required String body}) {
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment,
      consumptions: consumptions,
      submitForReview: submitForReview,
      lastError: lastError,
      serverStatus: serverStatus,
      conflictKind: conflictKind,
      photoPaths: photoPaths,
      deletedPhotoUuids: deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      mutationKey: key,
      requestBody: body,
      baseEtag: baseEtag,
      baseState: baseState,
      serverEtag: serverEtag,
      serverState: serverState,
    );
  }

  /// Ремонт для карточки, когда настоящего взять неоткуда: на сервере его нет
  /// (удалён, передан другому) и в кэше тоже. Без него правку было не открыть
  /// и не удалить — карточка показывала ошибку загрузки, а «Синхронизировать
  /// данные» вечно говорило «Не все ремонты отправлены». Только то, что знает
  /// правка: номер, оборудование, комментарий и расход.
  Repair toRepair() => Repair(
        id: repairId,
        uuid: repairUuid,
        status: serverStatus ?? baseStatus,
        equipmentUuid: '',
        equipmentName: equipmentName,
        createdAt: createdAt,
        startedAt: createdAt,
        comment: comment,
        actualConsumptions: consumptions,
        detailsLoaded: true,
      );

  RepairConflictKind get kind => RepairConflictKind.fromCode(conflictKind);

  /// Есть ли что делать с фотографиями до отправки самих полей.
  bool get hasPhotoWork =>
      photoPaths.isNotEmpty || deletedPhotoUuids.isNotEmpty;

  /// Сервер ответил и отказал — правку надо разобрать вручную.
  bool get isRejected => lastError != null && lastError!.isNotEmpty;

  /// Ремонт на сервере ушёл из того статуса, в котором его правили. Именно
  /// это делает отказ конфликтом, а не просто ошибкой.
  bool get isStatusConflict =>
      serverStatus != null && serverStatus != baseStatus;

  /// Обычная правка записи очереди. Пометку об отказе **не трогает**: менять
  /// её умеют только [markRejected] и [clearRejection].
  ///
  /// Раньше `lastError`, `serverStatus` и `conflictKind` были параметрами и
  /// очищались, если их не передали. По месту вызова это не читалось, и
  /// безобидное с виду обновление списка снимков снимало неразрешённый
  /// конфликт. Тот же разбор, что и у [PendingRepair].
  PendingRepairUpdate copyWith({
    String? comment,
    List<RepairConsumption>? consumptions,
    bool? submitForReview,
    List<String>? photoPaths,
    List<String>? deletedPhotoUuids,
  }) {
    // Поля формы поменялись — это новый запрос: ключ и тело прежней правки к
    // нему не относятся ([mutationKey]). Ход отправки снимков их не трогает.
    final bodyChanged =
        comment != null || consumptions != null || submitForReview != null;
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment ?? this.comment,
      consumptions: consumptions ?? this.consumptions,
      submitForReview: submitForReview ?? this.submitForReview,
      lastError: lastError,
      serverStatus: serverStatus,
      conflictKind: conflictKind,
      photoPaths: photoPaths ?? this.photoPaths,
      deletedPhotoUuids: deletedPhotoUuids ?? this.deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      mutationKey: bodyChanged ? null : mutationKey,
      requestBody: bodyChanged ? null : requestBody,
      baseEtag: baseEtag,
      baseState: baseState,
      serverEtag: serverEtag,
      serverState: serverState,
    );
  }

  /// Сервер ответил и отказал. [serverStatus] — статус, который удалось
  /// перечитать после отказа (`null`, если связь пропала сразу),
  /// [conflictKind] — код вида конфликта.
  ///
  /// [serverEtag] и [serverState] — что на сервере сейчас, только у отказа
  /// 412 ([RepairConflictKind.changedOnServer]).
  PendingRepairUpdate markRejected({
    required String reason,
    String? serverStatus,
    String? conflictKind,
    String? serverEtag,
    String? serverState,
  }) {
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment,
      consumptions: consumptions,
      submitForReview: submitForReview,
      lastError: reason,
      serverStatus: serverStatus,
      conflictKind: conflictKind,
      photoPaths: photoPaths,
      deletedPhotoUuids: deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      // Отказ откатил запрос на сервере — повтор той же правки идёт тем же
      // ключом и телом.
      mutationKey: mutationKey,
      requestBody: requestBody,
      baseEtag: baseEtag,
      baseState: baseState,
      serverEtag: serverEtag,
      serverState: serverState,
    );
  }

  /// Правка снова готова к отправке: конфликт разобран или форма изменена.
  PendingRepairUpdate clearRejection() {
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment,
      consumptions: consumptions,
      submitForReview: submitForReview,
      lastError: null,
      serverStatus: null,
      conflictKind: null,
      photoPaths: photoPaths,
      deletedPhotoUuids: deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      mutationKey: mutationKey,
      requestBody: requestBody,
      baseEtag: baseEtag,
      baseState: baseState,
    );
  }

  /// Та же правка без основы для `If-Match`: прежний ETag устарел нашей же
  /// отправкой (поля ушли, а запись осталась — обходчик поменял форму или
  /// добавил снимки, пока шёл запрос). Ключ и тело не трогаются: у той же
  /// формы повтор узнается сервером, у новой их и так нет.
  PendingRepairUpdate withoutBase() => withBase(etag: null, state: null);

  /// Та же правка с основой для `If-Match` [etag]/[state] (`null` — без неё).
  /// Ключ, тело и пометка об отказе не трогаются — в отличие от [rebased]:
  /// это не новый запрос, а ETag, взятый заново после нашей же отправки.
  PendingRepairUpdate withBase(
      {required String? etag, required String? state}) {
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment,
      consumptions: consumptions,
      submitForReview: submitForReview,
      lastError: lastError,
      serverStatus: serverStatus,
      conflictKind: conflictKind,
      photoPaths: photoPaths,
      deletedPhotoUuids: deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      mutationKey: mutationKey,
      requestBody: requestBody,
      baseEtag: etag,
      baseState: state,
      serverEtag: serverEtag,
      serverState: serverState,
    );
  }

  /// Правка поверх состояния [etag]/[state]: обходчик решил отправить её
  /// поверх чужих изменений («Отправить мою правку»), или изменился только
  /// `updated_at` (`isSameRepairEditState`). Пометка об отказе снимается.
  ///
  /// Ключ и тело — заново: прошлый запрос сервер отклонил и откатил, а
  /// новый уходит с другим `If-Match`, и это другой запрос.
  PendingRepairUpdate rebased({required String etag, required String state}) {
    return PendingRepairUpdate(
      repairUuid: repairUuid,
      repairId: repairId,
      equipmentName: equipmentName,
      baseStatus: baseStatus,
      createdAt: createdAt,
      comment: comment,
      consumptions: consumptions,
      submitForReview: submitForReview,
      photoPaths: photoPaths,
      deletedPhotoUuids: deletedPhotoUuids,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
      baseEtag: etag,
      baseState: state,
    );
  }
}

/// Адаптер написан руками: порядок чтения обязан совпадать с порядком записи,
/// новые поля — только в конец через try/catch. Список позиций пишется как
/// есть — у [RepairConsumption] свой зарегистрированный адаптер (typeId 24).
class PendingRepairUpdateAdapter extends TypeAdapter<PendingRepairUpdate> {
  @override
  final int typeId = 28;

  @override
  PendingRepairUpdate read(BinaryReader reader) {
    return PendingRepairUpdate(
      repairUuid: reader.read(),
      repairId: reader.read(),
      equipmentName: reader.read(),
      comment: reader.read(),
      consumptions: reader.read().cast<RepairConsumption>(),
      submitForReview: reader.read(),
      baseStatus: reader.read(),
      createdAt: reader.read(),
      lastError: reader.read(),
      serverStatus: reader.read(),
      // Поля добавлены позже — у правок прежней версии их в потоке нет.
      conflictKind: _readTrailing<String>(reader),
      photoPaths:
          _readTrailing<List<dynamic>>(reader)?.cast<String>() ?? const [],
      deletedPhotoUuids:
          _readTrailing<List<dynamic>>(reader)?.cast<String>() ?? const [],
      // Владелец — у правок до привязки очередей к аккаунту его нет.
      ownerUuid: _readTrailing<String>(reader),
      // Сервер — у правок до привязки очередей к серверу его нет.
      ownerServer: _readTrailing<String>(reader),
      // Ключ и тело PATCH — у правок до бэкенда `81f644c` их нет.
      mutationKey: _readTrailing<String>(reader),
      requestBody: _readTrailing<String>(reader),
      // Основа для If-Match и состояние сервера из 412 — у правок до
      // бэкенда `d22727e` их нет.
      baseEtag: _readTrailing<String>(reader),
      baseState: _readTrailing<String>(reader),
      serverEtag: _readTrailing<String>(reader),
      serverState: _readTrailing<String>(reader),
    );
  }

  static T? _readTrailing<T>(BinaryReader reader) {
    try {
      return reader.read() as T?;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(BinaryWriter writer, PendingRepairUpdate obj) {
    writer.write(obj.repairUuid);
    writer.write(obj.repairId);
    writer.write(obj.equipmentName);
    writer.write(obj.comment);
    writer.write(obj.consumptions);
    writer.write(obj.submitForReview);
    writer.write(obj.baseStatus);
    writer.write(obj.createdAt);
    writer.write(obj.lastError);
    writer.write(obj.serverStatus);
    writer.write(obj.conflictKind);
    writer.write(obj.photoPaths);
    writer.write(obj.deletedPhotoUuids);
    writer.write(obj.ownerUuid);
    writer.write(obj.ownerServer);
    writer.write(obj.mutationKey);
    writer.write(obj.requestBody);
    writer.write(obj.baseEtag);
    writer.write(obj.baseState);
    writer.write(obj.serverEtag);
    writer.write(obj.serverState);
  }
}
