import 'package:hive_ce/hive.dart';

@HiveType(typeId: 8)
class Equipment {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String uuid;
  @HiveField(2)
  final String name;
  @HiveField(3)
  final String typeModel;

  Equipment({
    required this.id,
    required this.uuid,
    required this.name,
    required this.typeModel,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      typeModel: json['type_model'] as String,
    );
  }
}

class EquipmentAdapter extends TypeAdapter<Equipment> {
  @override
  final int typeId = 8;

  @override
  Equipment read(BinaryReader reader) {
    return Equipment(
      id: reader.read(),
      uuid: reader.read(),
      name: reader.read(),
      typeModel: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Equipment obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.name);
    writer.write(obj.typeModel);
  }
}

@HiveType(typeId: 9)
class CustomRole {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String? description;
  @HiveField(3)
  final bool isActive;

  CustomRole({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
  });

  factory CustomRole.fromJson(Map<String, dynamic> json) {
    return CustomRole(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool,
    );
  }
}

class CustomRoleAdapter extends TypeAdapter<CustomRole> {
  @override
  final int typeId = 9;

  @override
  CustomRole read(BinaryReader reader) {
    return CustomRole(
      id: reader.read(),
      name: reader.read(),
      description: reader.read(),
      isActive: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, CustomRole obj) {
    writer.write(obj.id);
    writer.write(obj.name);
    writer.write(obj.description);
    writer.write(obj.isActive);
  }
}

@HiveType(typeId: 10)
class Location {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String uuid;
  @HiveField(2)
  final String name;

  Location({
    required this.id,
    required this.uuid,
    required this.name,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      name: json['name'] as String,
    );
  }
}

class LocationAdapter extends TypeAdapter<Location> {
  @override
  final int typeId = 10;

  @override
  Location read(BinaryReader reader) {
    return Location(
      id: reader.read(),
      uuid: reader.read(),
      name: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Location obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.name);
  }
}

@HiveType(typeId: 11)
class PeriodicTask {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String uuid;
  @HiveField(2)
  final Equipment equipment;
  @HiveField(3)
  final String? node;
  @HiveField(4)
  final String title;
  @HiveField(5)
  final String? description;
  @HiveField(6)
  final String periodicityRule;
  @HiveField(7)
  final String periodicityRuleDisplay;
  @HiveField(8)
  final List<CustomRole> customRoles;
  @HiveField(9)
  final DateTime nextDueAt;
  @HiveField(10)
  final DateTime? lastRunAt;
  @HiveField(11)
  final bool isActive;
  @HiveField(12)
  final DateTime createdAt;
  @HiveField(13)
  final DateTime? updatedAt;

  PeriodicTask({
    required this.id,
    required this.uuid,
    required this.equipment,
    this.node,
    required this.title,
    this.description,
    required this.periodicityRule,
    required this.periodicityRuleDisplay,
    required this.customRoles,
    required this.nextDueAt,
    this.lastRunAt,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory PeriodicTask.fromJson(Map<String, dynamic> json) {
    return PeriodicTask(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      equipment: Equipment.fromJson(json['equipment'] as Map<String, dynamic>),
      node: json['node'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      periodicityRule: json['periodicity_rule'] as String,
      periodicityRuleDisplay: json['periodicity_rule_display'] as String,
      customRoles: (json['custom_roles'] as List<dynamic>)
          .map((e) => CustomRole.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextDueAt: DateTime.parse(json['next_due_at'] as String),
      lastRunAt: json['last_run_at'] != null
          ? DateTime.parse(json['last_run_at'] as String)
          : null,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}

class PeriodicTaskAdapter extends TypeAdapter<PeriodicTask> {
  @override
  final int typeId = 11;

  @override
  PeriodicTask read(BinaryReader reader) {
    return PeriodicTask(
      id: reader.read(),
      uuid: reader.read(),
      equipment: reader.read(),
      node: reader.read(),
      title: reader.read(),
      description: reader.read(),
      periodicityRule: reader.read(),
      periodicityRuleDisplay: reader.read(),
      customRoles: reader.read().cast<CustomRole>(),
      nextDueAt: reader.read(),
      lastRunAt: reader.read(),
      isActive: reader.read(),
      createdAt: reader.read(),
      updatedAt: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, PeriodicTask obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.equipment);
    writer.write(obj.node);
    writer.write(obj.title);
    writer.write(obj.description);
    writer.write(obj.periodicityRule);
    writer.write(obj.periodicityRuleDisplay);
    writer.write(obj.customRoles);
    writer.write(obj.nextDueAt);
    writer.write(obj.lastRunAt);
    writer.write(obj.isActive);
    writer.write(obj.createdAt);
    writer.write(obj.updatedAt);
  }
}
