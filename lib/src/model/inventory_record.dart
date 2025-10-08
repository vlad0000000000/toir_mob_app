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
  });

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
  }
}

class UsageParameter {
  final int id;
  final String uuid;
  final String unitType;
  final double currentValue;
  final bool prohibitDecrease;
  final bool createMaintenanceTasks;
  final double lastMaintenanceValue;
  final double maintenanceInterval;
  final double nextMaintenanceValue;

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

  const UsageParameter({
    required this.id,
    required this.uuid,
    required this.unitType,
    required this.currentValue,
    required this.prohibitDecrease,
    required this.createMaintenanceTasks,
    required this.lastMaintenanceValue,
    required this.maintenanceInterval,
    required this.nextMaintenanceValue,
  });

  factory UsageParameter.fromJson(Map<String, dynamic> json) {
    return UsageParameter(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      unitType: json['unit_type'] as String,
      currentValue: double.parse(json['current_value']) as double,
      prohibitDecrease: json['prohibit_decrease'] as bool,
      createMaintenanceTasks: json['create_maintenance_tasks'] as bool,
      lastMaintenanceValue:
          double.parse(json['last_maintenance_value']) as double,
      maintenanceInterval: double.parse(json['maintenance_interval']) as double,
      nextMaintenanceValue:
          double.parse(json['next_maintenance_value']) as double,
    );
  }
}
