import 'package:hive_ce/hive.dart';

class EquipmentFault {
  final int id;
  final String uuid;
  final String title;
  final String defaultPriority;

  EquipmentFault({
    required this.id,
    required this.uuid,
    required this.title,
    required this.defaultPriority,
  });

  factory EquipmentFault.fromJson(Map<String, dynamic> json) {
    return EquipmentFault(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      title: json['title'] as String,
      defaultPriority: json['default_priority'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'title': title,
      'default_priority': defaultPriority,
    };
  }
}

class EquipmentFaultAdapter extends TypeAdapter<EquipmentFault> {
  @override
  final int typeId = 17;

  @override
  EquipmentFault read(BinaryReader reader) {
    return EquipmentFault(
      id: reader.read(),
      uuid: reader.read(),
      title: reader.read(),
      defaultPriority: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, EquipmentFault obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.title);
    writer.write(obj.defaultPriority);
  }
}
