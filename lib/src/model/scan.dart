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
      this.taskUuid,
      this.priority,
      this.createdAt,
      this.closedAt});

  Map<String, dynamic> toJson() {
    return {
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
  }
}

class ScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2;

  @override
  Scan read(BinaryReader reader) {
    return Scan(
      files: reader.read().cast<String>(),
      periodicTaskUuid: reader.read(),
      equipmentUuid: reader.read(),
      resultStatus: reader.read(),
      comment: reader.read(),
      faultUuid: reader.read(),
      taskUuid: reader.read(),
      priority: reader.read(),
      createdAt: reader.read(),
      closedAt: reader.read(),
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
  }
}
