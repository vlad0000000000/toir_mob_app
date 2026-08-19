import 'package:hive_ce/hive.dart';

class Equipment {
  final int id;
  final String uuid;
  final String name;
  final String? typeModel;

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
      typeModel: json['type_model'] as String?,
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

class CustomRole {
  final int id;
  final String name;
  final String? description;
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

class Location {
  final int id;
  final String uuid;
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

class PeriodicTaskPhoto {
  final int id;
  final String uuid;
  final String url;
  final int order;

  PeriodicTaskPhoto({
    required this.id,
    required this.uuid,
    required this.url,
    required this.order,
  });

  factory PeriodicTaskPhoto.fromJson(Map<String, dynamic> json) {
    return PeriodicTaskPhoto(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      url: json['url'] as String,
      order: json['order'] as int,
    );
  }
}

class PeriodicTaskPhotoAdapter extends TypeAdapter<PeriodicTaskPhoto> {
  @override
  final int typeId = 21;

  @override
  PeriodicTaskPhoto read(BinaryReader reader) {
    return PeriodicTaskPhoto(
      id: reader.read(),
      uuid: reader.read(),
      url: reader.read(),
      order: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, PeriodicTaskPhoto obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.url);
    writer.write(obj.order);
  }
}

class PeriodicTask {
  final int id;
  final String uuid;
  final Equipment equipment;
  final String? node;
  final String title;
  final String? description;
  final String periodicityRule;
  final String periodicityRuleDisplay;
  final List<CustomRole> customRoles;
  final DateTime? nextDueAt;
  final DateTime? lastRunAt;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<PeriodicTaskPhoto> photos;

  /// Это задача технического обслуживания, а не обычная периодическая.
  ///
  /// Считает сервер (`PeriodicTask.is_maintenance`): по `target_type` в
  /// параметрах задачи, а для созданных до этого поля — по связке
  /// «параметр наработки + интервал периода + заголовок». Приложение раньше
  /// опознавало ТО само, по вхождению «Техническое обслуживание» в заголовок,
  /// и переименование задачи в админке эту догадку ломало.
  ///
  /// **В Hive не сохраняется.** Этот объект вложен в [Task] и пишется в общий
  /// с ним поток, а значит дописать поле в конец адаптера нельзя: лишний
  /// `read()` съел бы следующее поле родителя. Поэтому у задачи, прочитанной
  /// из кэша, флаг всегда `false` — до первой синхронизации работает разбор по
  /// заголовку, оставленный запасным в `DataProvider.addScan`.
  final bool isMaintenance;

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
    this.photos = const [],
    this.isMaintenance = false,
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
      nextDueAt: json['next_due_at'] != null
          ? DateTime.parse(json['next_due_at'] as String)
          : null,
      lastRunAt: json['last_run_at'] != null
          ? DateTime.parse(json['last_run_at'] as String)
          : null,
      isActive: json['is_active'] as bool,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      photos: (json['photos'] as List<dynamic>?)
              ?.map(
                  (e) => PeriodicTaskPhoto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      // Поле появилось в `1d99a25`; со старого сервера не придёт, и тогда
      // остаётся прежний разбор по заголовку.
      isMaintenance: json['is_maintenance'] as bool? ?? false,
    );
  }
}

class PeriodicTaskAdapter extends TypeAdapter<PeriodicTask> {
  @override
  final int typeId = 11;

  /// Формат намеренно не содержит `isMaintenance` — см. комментарий у поля.
  ///
  /// Дописать поле в конец, как в `TaskAdapter`, здесь **нельзя**: этот объект
  /// вложен в [Task], и оба пишутся в один поток. Лишний `read()` не упёрся бы
  /// в конец записи, а съел бы следующее поле родителя — дальше всё
  /// разъезжается, `Hive.openBox` падает на разборе, и приложение навсегда
  /// остаётся на заставке.
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
      photos: reader.read().cast<PeriodicTaskPhoto>(),
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
    writer.write(obj.photos);
  }
}
