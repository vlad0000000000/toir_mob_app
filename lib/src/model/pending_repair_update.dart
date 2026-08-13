import 'package:hive_ce/hive.dart';

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
class PendingRepairUpdate {
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
  });

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

  /// Внимание: [lastError] и [serverStatus] здесь **не** «оставить прежнее».
  /// Не переданные, они очищаются — иначе разрешённый конфликт нельзя было бы
  /// вернуть в очередь. Передавайте их явно.
  PendingRepairUpdate copyWith({
    String? lastError,
    String? serverStatus,
    String? conflictKind,
    List<String>? photoPaths,
    List<String>? deletedPhotoUuids,
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
      lastError: lastError,
      serverStatus: serverStatus,
      conflictKind: conflictKind,
      // Работа с фотографиями пометкой об отказе не сбрасывается — в отличие
      // от lastError, который здесь именно очищается по умолчанию.
      photoPaths: photoPaths ?? this.photoPaths,
      deletedPhotoUuids: deletedPhotoUuids ?? this.deletedPhotoUuids,
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
  }
}
