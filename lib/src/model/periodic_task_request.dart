import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class PeriodicTaskRequest {
  final String equipmentUuid;
  final String? node;
  final String title;
  final String? description;
  final String periodicityRule;
  final List<int>? customRoleIds;
  final String nextDueAt;
  final Map<String, dynamic> params;
  final List<String>? photos;

  /// Постоянный ключ события — основа `Idempotency-Key` обоих запросов
  /// заявки ([createIdempotencyKey], [photosIdempotencyKey]). Создаётся
  /// вместе с записью и не меняется при повторах: потерянный ответ сервер
  /// узнаёт по ключу и вторую задачу не заводит. `null` — запись прошлой
  /// версии, ключ тогда выводится из [key].
  final String? eventId;

  /// Uuid задачи, уже созданной на сервере, — снимки ещё не приняты. Повтор
  /// такой записи создание пропускает и грузит только фото. В [key] не
  /// входит: запись остаётся под тем же ключом бокса.
  final String? serverUuid;

  /// Сервер отказал в создании задачи так, что фоновый повтор ответил бы тем
  /// же (404: оборудование чужого подразделения, пока сервер пускает к нему
  /// только сам осмотр). Запись остаётся в очереди с причиной; фоновая
  /// отправка её пропускает, а «Синхронизировать данные» и смена доступа
  /// снимают пометку и пробуют снова. `null` — не отклонена.
  final String? rejectedReason;

  bool get isRejected => rejectedReason != null;

  /// Ключ создания задачи. Сервер сверяет с ним и само тело запроса, поэтому
  /// [toJson] обязан давать одно и то же при каждом повторе.
  String get createIdempotencyKey => eventId ?? 'problem-report-${key()}';

  /// Ключ загрузки снимков — свой: у сервера это отдельная операция.
  String get photosIdempotencyKey => '$createIdempotencyKey:photos';

  String key() {
    return GlobalState.digest(jsonEncode({
      'equipment_uuid': equipmentUuid,
      'node': node,
      'title': title,
      'description': description,
      'periodicity_rule': periodicityRule,
      'custom_role_ids': customRoleIds,
      'next_due_at': nextDueAt,
      'params': params,
      'photos': photos,
    }));
  }

  @override
  String toString() {
    return "PeriodicTaskRequest(title: $title, equipmentUuid: $equipmentUuid)";
  }

  PeriodicTaskRequest({
    required this.equipmentUuid,
    this.node,
    required this.title,
    this.description,
    required this.periodicityRule,
    this.customRoleIds,
    required this.nextDueAt,
    required this.params,
    required this.photos,
    this.eventId,
    this.serverUuid,
    this.rejectedReason,
  });

  /// Та же заявка, уже созданная на сервере под [uuid].
  PeriodicTaskRequest withServerUuid(String uuid) => PeriodicTaskRequest(
        equipmentUuid: equipmentUuid,
        node: node,
        title: title,
        description: description,
        periodicityRule: periodicityRule,
        customRoleIds: customRoleIds,
        nextDueAt: nextDueAt,
        params: params,
        photos: photos,
        eventId: eventId,
        serverUuid: uuid,
        rejectedReason: rejectedReason,
      );

  /// Та же заявка с пометкой отказа [reason]; `null` — пометка снята.
  PeriodicTaskRequest withRejection(String? reason) => PeriodicTaskRequest(
        equipmentUuid: equipmentUuid,
        node: node,
        title: title,
        description: description,
        periodicityRule: periodicityRule,
        customRoleIds: customRoleIds,
        nextDueAt: nextDueAt,
        params: params,
        photos: photos,
        eventId: eventId,
        serverUuid: serverUuid,
        rejectedReason: reason,
      );

  // "equipment_uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  // "node": "string",
  // "title": "string",
  // "description": "string",
  // "periodicity_rule": "once",
  // "params": {
  // "target_type": "ad_hoc",
  // "result_status": "open",
  // "priority": "low"
  // }

  Map<String, dynamic> toJson() {
    return {
      'equipment_uuid': equipmentUuid,
      if (node != null) 'node': node,
      'title': title,
      if (description != null) 'description': description,
      'periodicity_rule': periodicityRule,
      // if (customRoleIds != null && customRoleIds!.isNotEmpty)
      //   'custom_role_ids': customRoleIds,
      // 'next_due_at': nextDueAt,
      'params': params
    };
  }
}

class PeriodicTaskRequestAdapter extends TypeAdapter<PeriodicTaskRequest> {
  @override
  final int typeId = 20;

  @override
  PeriodicTaskRequest read(BinaryReader reader) {
    return PeriodicTaskRequest(
      equipmentUuid: reader.read(),
      node: reader.read(),
      title: reader.read(),
      description: reader.read(),
      periodicityRule: reader.read(),
      customRoleIds: reader.read()?.cast<int>(),
      nextDueAt: reader.read(),
      params: Map<String, dynamic>.from(reader.read()),
      photos: reader.read().cast<String>(),
      // Поля добавлены позже — у записей прошлой версии их нет. Объект
      // верхнего уровня (свой бокс), поэтому дочитать конец записи безопасно.
      eventId: reader.availableBytes > 0 ? reader.read() as String? : null,
      serverUuid: reader.availableBytes > 0 ? reader.read() as String? : null,
      rejectedReason:
          reader.availableBytes > 0 ? reader.read() as String? : null,
    );
  }

  @override
  void write(BinaryWriter writer, PeriodicTaskRequest obj) {
    writer.write(obj.equipmentUuid);
    writer.write(obj.node);
    writer.write(obj.title);
    writer.write(obj.description);
    writer.write(obj.periodicityRule);
    writer.write(obj.customRoleIds);
    writer.write(obj.nextDueAt);
    writer.write(obj.params);
    writer.write(obj.photos);
    writer.write(obj.eventId);
    writer.write(obj.serverUuid);
    writer.write(obj.rejectedReason);
  }
}
