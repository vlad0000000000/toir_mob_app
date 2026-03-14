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
      this.closedAt});

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
  }
}
