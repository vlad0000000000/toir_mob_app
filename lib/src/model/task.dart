import 'package:hive_ce/hive.dart';
import '../../src/model/periodic_task_models.dart';
import '../../src/model/responsible_user.dart';
import '../../src/model/equipment_fault.dart';

class Task {
  final String uuid;
  final String resultStatus;
  final String targetType;
  final PeriodicTask? periodicTask;
  final String equipmentUuid;
  final String? comment;
  final List<String> roles;
  final ResponsibleUser? responsibleUser;
  final EquipmentFault? equipmentFault;
  final List<String> photos;

  Task({
    required this.uuid,
    required this.resultStatus,
    required this.targetType,
    required this.periodicTask,
    required this.equipmentUuid,
    required this.roles,
    this.responsibleUser,
    required this.comment,
    this.equipmentFault,
    this.photos = const [],
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      comment: json['comment'],
      uuid: json['uuid'] as String,
      resultStatus: json['result_status'] as String,
      targetType: json['target_type'] as String,
      periodicTask: json['periodic_task'] == null
          ? null
          : PeriodicTask.fromJson(
              json['periodic_task'] as Map<String, dynamic>),
      equipmentUuid: json['equipment_uuid'] as String,
      photos: (json['photos'] as List<dynamic>)
          .map(
            (e) => e['url'] as String,
          )
          .toList(),
      roles: (json['custom_roles'] == null
              ? []
              : json['custom_roles'] as List<dynamic>)
          .map((x) {
        return (x['name'] as String);
      }).toList(),
      responsibleUser: json['responsible_user'] != null
          ? ResponsibleUser.fromJson(
              json['responsible_user'] as Map<String, dynamic>)
          : null,
      equipmentFault: json['equipment_fault'] != null
          ? EquipmentFault.fromJson(
              json['equipment_fault'] as Map<String, dynamic>)
          : null,
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
      roles: reader.read(),
      responsibleUser: reader.read(),
      comment: reader.read(),
      equipmentFault: reader.read(),
      photos: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.write(obj.uuid);
    writer.write(obj.resultStatus);
    writer.write(obj.targetType);
    writer.write(obj.periodicTask);
    writer.write(obj.equipmentUuid);
    writer.write(obj.roles);
    writer.write(obj.responsibleUser);
    writer.write(obj.comment);
    writer.write(obj.equipmentFault);
    writer.write(obj.photos);
  }
}
