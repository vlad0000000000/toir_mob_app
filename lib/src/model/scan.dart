import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class Scan {
  final List<String>? files;
  final String? periodicTaskUuid;
  final String? equipmentUuid;
  String resultStatus;
  final String? comment;
  final String? faultUuid;
  final bool? isOtherFault;
  final String? taskUuid;
  final String? priority;
  final String? createdAt;
  final String? closedAt;

  /// Фактический расход ЗИП — уже готовая строка JSON
  /// `[{"spare_part_uuid": "...", "quantity": 2}]`, ровно в том виде, в каком
  /// её ждёт `PATCH /v1/company/fault_inspections/{uuid}` (поле формы
  /// `actual_consumptions`).
  ///
  /// Строкой, а не списком объектов: расход собирается один раз при отправке
  /// и больше не редактируется, разбирать его обратно незачем. Заодно это
  /// избавляет от новых Hive-адаптеров.
  ///
  /// Заполняется только для закрываемой периодической задачи, у которой
  /// сервер прислал `spare_part_usage`.
  final String? actualConsumptions;

  /// Причина, по которой сервер отказался принять осмотр.
  ///
  /// Отличает «сервер ответил и отказал» от «связи нет»: во втором случае
  /// осмотр просто ждёт своей очереди, в первом — повторять бессмысленно,
  /// пока обходчик что-то не изменит. Хранится по-русски, потому что
  /// показывается ему же.
  ///
  /// Не финальное: отметка ставится и снимается очередью на уже лежащей в
  /// боксе записи. В [key] не входит — ключ обязан оставаться прежним, иначе
  /// запись потеряется в боксе.
  String? lastError;

  bool get isRejected => (lastError ?? '').isNotEmpty;

  String key() {
    return GlobalState.digest(jsonEncode({
      'files': files,
      'periodic_task_uuid': periodicTaskUuid,
      'equipment_uuid': equipmentUuid,
      'result_status': resultStatus,
      'comment': comment,
      'fault_uuid': faultUuid,
      'task_uuid': taskUuid,
      'priority': priority,
    }));
  }
  // Расход ЗИП в ключ намеренно не входит. Ключ — это идентификатор записи в
  // боксе, и он обязан оставаться прежним у уже поставленных в очередь
  // осмотров: иначе после обновления приложения `scanBox.delete(scan.key())`
  // не нашёл бы старую запись, и осмотр отправлялся бы бесконечно.
  // Схлопывания это не создаёт: `task_uuid` в ключе уже уникален для
  // закрываемой задачи, а у осмотра без задачи расхода не бывает.

  @override
  String toString() {
    return "Scan(resultStatus: $resultStatus, equipmentUuid: $equipmentUuid)";
  }

  Scan(
      {this.files,
      this.periodicTaskUuid,
      this.equipmentUuid,
      required this.resultStatus,
      this.comment,
      this.faultUuid,
      this.isOtherFault,
      this.taskUuid,
      this.priority,
      this.createdAt,
      this.closedAt,
      this.actualConsumptions,
      this.lastError});

  Map<String, dynamic> toJson() {
    var result = <String, dynamic>{
      'files': files,
      'periodic_task_uuid': periodicTaskUuid,
      'equipment_uuid': equipmentUuid,
      'result_status': resultStatus,
      'comment': comment,
      'fault_uuid': faultUuid,
      'task_uuid': taskUuid,
      'priority': priority,
      'app_created_at': createdAt,
      'app_closed_at': closedAt,
      // Пустую строку отправлять нельзя: сервер разбирает поле как JSON и
      // на пустом значении ответил бы 422. `sendScan` пустые и так отсеивает.
      'actual_consumptions': actualConsumptions,
    };
    if (isOtherFault == true) {
      result['is_other_fault'] = 'true';
    }
    return result;
  }
}

class ScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2;

  @override
  Scan read(BinaryReader reader) {
    var files = reader.read().cast<String>();
    var periodicTaskUuid = reader.read();
    var equipmentUuid = reader.read();
    var resultStatus = reader.read();
    var comment = reader.read();
    var faultUuid = reader.read();
    var taskUuid = reader.read();
    var priority = reader.read();
    var createdAt = reader.read();
    var closedAt = reader.read();
    bool? isOtherFault;
    try {
      isOtherFault = reader.read();
    } catch (_) {
      isOtherFault = null; // старые записи без поля is_other_fault
    }
    String? actualConsumptions;
    try {
      actualConsumptions = reader.read() as String?;
    } catch (_) {
      actualConsumptions = null; // записи до появления расхода ЗИП
    }
    String? lastError;
    try {
      lastError = reader.read() as String?;
    } catch (_) {
      lastError = null; // записи до появления отметки об отказе
    }
    return Scan(
      files: files,
      periodicTaskUuid: periodicTaskUuid,
      equipmentUuid: equipmentUuid,
      resultStatus: resultStatus,
      comment: comment,
      faultUuid: faultUuid,
      taskUuid: taskUuid,
      priority: priority,
      createdAt: createdAt,
      closedAt: closedAt,
      isOtherFault: isOtherFault,
      actualConsumptions: actualConsumptions,
      lastError: lastError,
    );
  }

  @override
  void write(BinaryWriter writer, Scan obj) {
    writer.write(obj.files);
    writer.write(obj.periodicTaskUuid);
    writer.write(obj.equipmentUuid);
    writer.write(obj.resultStatus);
    writer.write(obj.comment);
    writer.write(obj.faultUuid);
    writer.write(obj.taskUuid);
    writer.write(obj.priority);
    writer.write(obj.createdAt);
    writer.write(obj.closedAt);
    writer.write(obj.isOtherFault);
    // Новые поля — строго в конец и в этом порядке: read() читает их так же.
    writer.write(obj.actualConsumptions);
    writer.write(obj.lastError);
  }
}
