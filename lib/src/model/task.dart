import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../src/model/periodic_task_models.dart';
import '../../src/model/responsible_user.dart';
import '../../src/model/equipment_fault.dart';
import 'spare_part_usage.dart';

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

  /// Настройка расхода ЗИП по этой задаче. `null` — расход не настроен, и
  /// раздел фактического расхода при закрытии задачи показывать нельзя:
  /// сервер такой `PATCH` отклонит.
  final SparePartUsage? sparePartUsage;

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
    this.sparePartUsage,
  });

  /// Комментарий осмотра. Сервер отдаёт его либо строкой (старый формат),
  /// либо объектом `{text, timestamp}` — принимаем оба, иначе разбор задачи
  /// падает и список задач остаётся пустым.
  static String? _parseComment(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is Map) return raw['text'] as String?;
    return null;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      comment: _parseComment(json['comment']),
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
      sparePartUsage: json['spare_part_usage'] != null
          ? SparePartUsage.fromJson(
              json['spare_part_usage'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;
}

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 4;

  @override
  Task read(BinaryReader reader) {
    // Поля читаются в локальные переменные, а не прямо в конструктор: только
    // так последнее поле можно обернуть в try/catch и открыть записи,
    // сохранённые до его появления.
    var uuid = reader.read();
    var resultStatus = reader.read();
    var targetType = reader.read();
    var periodicTask = reader.read();
    var equipmentUuid = reader.read();
    var roles = reader.read();
    var responsibleUser = reader.read();
    var comment = reader.read();
    var equipmentFault = reader.read();
    var photos = reader.read();
    SparePartUsage? sparePartUsage;
    try {
      final raw = reader.read() as String?;
      if (raw != null && raw.isNotEmpty) {
        sparePartUsage =
            SparePartUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Старые записи без поля spare_part_usage: задача остаётся рабочей,
      // просто без раздела расхода — он появится после синхронизации.
      sparePartUsage = null;
    }
    return Task(
      uuid: uuid,
      resultStatus: resultStatus,
      targetType: targetType,
      periodicTask: periodicTask,
      equipmentUuid: equipmentUuid,
      roles: roles,
      responsibleUser: responsibleUser,
      comment: comment,
      equipmentFault: equipmentFault,
      photos: photos,
      sparePartUsage: sparePartUsage,
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
    // Блок расхода кладём строкой JSON, а не отдельными адаптерами: он
    // read-only и целиком приходит с сервера, а два новых typeId ради
    // сквозного поля — лишний риск для формата на устройствах.
    writer.write(obj.sparePartUsage == null
        ? null
        : jsonEncode(obj.sparePartUsage!.toJson()));
  }
}
