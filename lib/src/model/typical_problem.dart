import 'package:hive_ce/hive.dart';

class TypicalProblem {
  final int id;
  final String title;
  final String uuid;
  final String? defaultPriority;
  final String equipmentUUID;

  static TypicalProblem other = TypicalProblem(
      id: 0,
      title: "Другое",
      defaultPriority: null,
      equipmentUUID: "-1",
      uuid: '');

  static TypicalProblem empty = TypicalProblem(
      id: -1,
      title: "Нет проблем",
      defaultPriority: null,
      equipmentUUID: "-1",
      uuid: '');

  TypicalProblem({
    required this.id,
    required this.title,
    required this.uuid,
    required this.defaultPriority,
    required this.equipmentUUID,
  });

  factory TypicalProblem.fromJson(Map<String, dynamic> json) {
    return TypicalProblem(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      title: json['title'] as String,
      defaultPriority: json['default_priority'] as String,
      equipmentUUID: json['equipment']['uuid'] as String,
    );
  }
}

class TypicalProblemAdapter extends TypeAdapter<TypicalProblem> {
  @override
  final int typeId = 6;

  @override
  TypicalProblem read(BinaryReader reader) {
    return TypicalProblem(
      id: reader.read(),
      uuid: reader.read(),
      title: reader.read(),
      defaultPriority: reader.read(),
      equipmentUUID: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, TypicalProblem obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.title);
    writer.write(obj.defaultPriority);
    writer.write(obj.equipmentUUID);
  }
}
