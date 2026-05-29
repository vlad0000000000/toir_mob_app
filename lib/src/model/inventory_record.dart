import 'package:hive_ce/hive.dart';

class InventoryRecord {
  final int id;
  final String uuid;
  final String name;
  final String? typeModel;
  final String? serialNumber;
  final String? location;
  final String? manufacturer;
  final String? quantity;
  final String? dateOfEntry;
  final String? description;
  final String imageData;
  final List<UsageParameter> usageParameters;
  final String? state;

  String get descriptionText {
    final List<String> parts = [];
    parts.add('**Наименование оборудования**: $name');
    if (typeModel != null && typeModel!.isNotEmpty)
      parts.add('**Тип / модель**: $typeModel');
    if (serialNumber != null && serialNumber!.isNotEmpty)
      parts.add('**Серийный номер**: $serialNumber');
    if (location != null && location!.isNotEmpty)
      parts.add('**Местоположение**: $location');
    if (manufacturer != null && manufacturer!.isNotEmpty)
      parts.add('**Производитель**: $manufacturer');
    if (description != null && description!.isNotEmpty)
      parts.add('**Описание**: $description');
    return parts.join('\n\n');
  }

  String get descriptionTextSimple {
    final List<String> parts = [];
    parts.add('$name');

    // if (state != null && state!.isNotEmpty) {
    //   // Получаем название состояния из dataProvider
    //   final stateName = GlobalState.dataProvider.getEquipmentStateName(state!);
    //   if (stateName != null && stateName.isNotEmpty) {
    //     parts.add('($stateName)');
    //   }
    //   // else {
    //   //   parts.add('**Состояние**: $state');
    //   // }
    // }

    return parts.join('\n');
  }

  const InventoryRecord({
    required this.id,
    required this.uuid,
    required this.name,
    required this.typeModel,
    required this.serialNumber,
    this.location = '',
    this.manufacturer,
    this.quantity,
    this.dateOfEntry,
    this.description,
    this.imageData = '',
    this.usageParameters = const [],
    this.state,
  });

  InventoryRecord copyWith({
    int? id,
    String? uuid,
    String? name,
    String? typeModel,
    String? serialNumber,
    String? location,
    String? manufacturer,
    String? quantity,
    String? dateOfEntry,
    String? description,
    String? imageData,
    List<UsageParameter>? usageParameters,
    String? state,
  }) {
    return InventoryRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      typeModel: typeModel ?? this.typeModel,
      serialNumber: serialNumber ?? this.serialNumber,
      location: location ?? this.location,
      manufacturer: manufacturer ?? this.manufacturer,
      quantity: quantity ?? this.quantity,
      dateOfEntry: dateOfEntry ?? this.dateOfEntry,
      description: description ?? this.description,
      imageData: imageData ?? this.imageData,
      usageParameters: usageParameters ?? this.usageParameters,
      state: state ?? this.state,
    );
  }

  String getQRValue() {
    return '{"uuid": "$uuid", "name": "$name"}';
  }

  @override
  String toString() {
    return "$id, $uuid, $name, $typeModel, $serialNumber, $location";
  }

  factory InventoryRecord.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'uuid': String uuid,
        'name': String name,
        'type_model': String? typeModel,
        'serial_number': String? serialNumber,
      } =>
        InventoryRecord(
          id: id,
          uuid: uuid,
          name: name,
          typeModel: typeModel,
          serialNumber: serialNumber,
          location: (json['location']?['name'] as String?) ?? '',
          manufacturer: json['manufacturer'] as String?,
          quantity: json['quantity'] as String?,
          dateOfEntry: json['date_of_entry'] as String?,
          description: json['description'] as String?,
          imageData: (json['photos'] as List<dynamic>?)?.isNotEmpty == true
              ? json['photos']![0]['url'] as String
              : '',
          usageParameters: (json['usage_parameters'] as List<dynamic>?)
                  ?.map(
                      (e) => UsageParameter.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
          state: json['state'] as String?,
        ),
      _ => throw const FormatException('Failed to load InventoryRecord.'),
    };
  }
}

class InventoryAdapter extends TypeAdapter<InventoryRecord> {
  @override
  final int typeId = 1;

  @override
  InventoryRecord read(BinaryReader reader) {
    return InventoryRecord(
      id: reader.read(),
      uuid: reader.read(),
      name: reader.read(),
      typeModel: reader.read(),
      serialNumber: reader.read(),
      location: reader.read(),
      manufacturer: reader.read(),
      quantity: reader.read(),
      dateOfEntry: reader.read(),
      description: reader.read(),
      imageData: reader.read(),
      usageParameters: reader.read().cast<UsageParameter>(),
      state: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, InventoryRecord obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.name);
    writer.write(obj.typeModel);
    writer.write(obj.serialNumber);
    writer.write(obj.location);
    writer.write(obj.manufacturer);
    writer.write(obj.quantity);
    writer.write(obj.dateOfEntry);
    writer.write(obj.description);
    writer.write(obj.imageData);
    writer.write(obj.usageParameters);
    writer.write(obj.state);
  }
}

class MaintenanceRoleAdapter extends TypeAdapter<MaintenanceRole> {
  @override
  final int typeId = 19;

  @override
  MaintenanceRole read(BinaryReader reader) {
    return MaintenanceRole(
      uuid: reader.read(),
      name: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, MaintenanceRole obj) {
    writer.write(obj.uuid);
    writer.write(obj.name);
  }
}

class MaintenanceRole {
  final String uuid;
  final String name;

  const MaintenanceRole({
    required this.uuid,
    required this.name,
  });

  factory MaintenanceRole.fromJson(Map<String, dynamic> json) {
    return MaintenanceRole(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
    );
  }
}

class UsageParameterAdapter extends TypeAdapter<UsageParameter> {
  @override
  final int typeId = 13;

  @override
  UsageParameter read(BinaryReader reader) {
    return UsageParameter(
      id: reader.read(),
      uuid: reader.read(),
      unitType: reader.read(),
      currentValue: reader.read(),
      prohibitDecrease: reader.read(),
      createMaintenanceTasks: reader.read(),
      lastMaintenanceValue: reader.read(),
      maintenanceInterval: reader.read(),
      nextMaintenanceValue: reader.read(),
      maintenanceRole: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, UsageParameter obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.unitType);
    writer.write(obj.currentValue);
    writer.write(obj.prohibitDecrease);
    writer.write(obj.createMaintenanceTasks);
    writer.write(obj.lastMaintenanceValue);
    writer.write(obj.maintenanceInterval);
    writer.write(obj.nextMaintenanceValue);
    writer.write(obj.maintenanceRole);
  }
}

class UsageParameter {
  final int id;
  final String uuid;
  final String unitType;
  double currentValue;
  final bool prohibitDecrease;
  final bool createMaintenanceTasks;
  final double? lastMaintenanceValue;
  final double? maintenanceInterval;
  final double? nextMaintenanceValue;
  final MaintenanceRole? maintenanceRole;

  String? validate(value, {allowCurrentValue = false}) {
    if (value == null || value.isEmpty) {
      return 'Значение не может быть пустым';
    }
    double v = 0;
    try {
      v = double.parse(value);
    } catch (e) {
      return 'Значение должно быть числом';
    }
    if (allowCurrentValue) {
      if (v < currentValue) {
        return 'Значение должно быть больше текущего';
      }
    } else {
      if (v <= currentValue) {
        return 'Значение должно быть больше текущего';
      }
    }
    return null;
  }

  UsageParameter({
    required this.id,
    required this.uuid,
    required this.unitType,
    required this.currentValue,
    required this.prohibitDecrease,
    required this.createMaintenanceTasks,
    required this.lastMaintenanceValue,
    required this.maintenanceInterval,
    required this.nextMaintenanceValue,
    this.maintenanceRole,
  });

  factory UsageParameter.fromJson(Map<String, dynamic> json) {
    return UsageParameter(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      unitType: json['unit_type'] as String,
      currentValue: double.parse(json['current_value']),
      prohibitDecrease: json['prohibit_decrease'] as bool,
      createMaintenanceTasks: json['create_maintenance_tasks'] as bool,
      // lastMaintenanceValue: 0,
      // maintenanceInterval: 0,
      // nextMaintenanceValue: 0,
      lastMaintenanceValue: json['last_maintenance_value'] != null
          ? double.parse(json['last_maintenance_value'])
          : null,
      maintenanceInterval: json['maintenance_interval'] != null
          ? double.parse(json['maintenance_interval'])
          : null,
      nextMaintenanceValue: json['next_maintenance_value'] != null
          ? double.parse(json['next_maintenance_value'])
          : null,
      maintenanceRole: (json['maintenance_role'] is Map<String, dynamic>)
          ? MaintenanceRole.fromJson(
              json['maintenance_role'] as Map<String, dynamic>)
          : null,
    );
  }
}
