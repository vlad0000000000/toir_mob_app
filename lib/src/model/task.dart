import 'package:flutter/cupertino.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/src/model/periodic_task_models.dart';

class Task {
  final String uuid;
  final String resultStatus;
  final String targetType;
  final PeriodicTask periodicTask;
  final String equipmentUuid;
  final String periodicityRule;
  final String periodicityRuleDisplay;

  Task({
    required this.uuid,
    required this.resultStatus,
    required this.targetType,
    required this.periodicTask,
    required this.equipmentUuid,
    required this.periodicityRule,
    required this.periodicityRuleDisplay,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      uuid: json['uuid'] as String,
      resultStatus: json['result_status'] as String,
      targetType: json['target_type'] as String,
      periodicTask: PeriodicTask.fromJson(json['periodic_task'] as Map<String, dynamic>),
      equipmentUuid: json['equipment_uuid'] as String,
      periodicityRule: json['periodic_task']['periodicity_rule'] as String,
      periodicityRuleDisplay: json['periodic_task']['periodicity_rule_display'] as String,
    );
  }
}

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 4;

  @override
  Task read(BinaryReader reader) {
    return Task(
      uuid: reader.read(),
      resultStatus: reader.read(),
      targetType: reader.read(),
      periodicTask: reader.read(),
      equipmentUuid: reader.read(),
      periodicityRule: reader.read(),
      periodicityRuleDisplay: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.write(obj.uuid);
    writer.write(obj.resultStatus);
    writer.write(obj.targetType);
    writer.write(obj.periodicTask);
    writer.write(obj.equipmentUuid);
    writer.write(obj.periodicityRule);
    writer.write(obj.periodicityRuleDisplay);
  }
}
