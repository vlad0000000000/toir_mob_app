import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

@HiveType(typeId: 2)
class Scan {
  @HiveField(0)
  final List<String>? files;
  @HiveField(1)
  final String? periodicTaskUuid;
  @HiveField(2)
  final String? equipmentUuid;
  @HiveField(3)
  final String resultStatus;
  @HiveField(4)
  final String? comment;
  @HiveField(5)
  final String? faultUuid;
  @HiveField(6)
  final String? taskUuid;
  @HiveField(7)
  final String? priority;
  @HiveField(8)
  final String? usageParameterUuid;
  @HiveField(9)
  final int? usageParameterValue;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  @override
  String toString() {
    return "Scan(resultStatus: $resultStatus, equipmentUuid: $equipmentUuid)";
  }

  Scan({
    this.files,
    this.periodicTaskUuid,
    this.equipmentUuid,
    required this.resultStatus,
    this.comment,
    this.faultUuid,
    this.taskUuid,
    this.priority,
    this.usageParameterUuid,
    this.usageParameterValue,
  });

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
      'usage_parameter_uuid': usageParameterUuid,
      'usage_parameter_value': usageParameterValue,
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
      usageParameterUuid: reader.read(),
      usageParameterValue: reader.read(),
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
    writer.write(obj.usageParameterUuid);
    writer.write(obj.usageParameterValue);
  }
}
