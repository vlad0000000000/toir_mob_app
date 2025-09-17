import 'package:hive_ce/hive.dart';

class InventoryRecord {
  final int id;
  final String uuid;
  final String qrCode;
  final String name;
  final String typeModel;
  final String serialNumber;
  final String location;
  final String? manufacturer;
  final String? quantity;
  final String? dateOfEntry;
  final String? description;
  final String imageData;

  String get descriptionText {
    final List<String> parts = [];
    parts.add('**Наименование**: $name');
    parts.add('**Модель**: $typeModel');
    parts.add('**Серийный номер**: $serialNumber');
    parts.add('**Местоположение**: $location');
    if (manufacturer != null && manufacturer!.isNotEmpty) {
      parts.add('**Производитель**: $manufacturer');
    }
    if (description != null && description!.isNotEmpty) {
      parts.add('**Описание**: $description');
    }
    return parts.join('\n');
  }

  const InventoryRecord({
    required this.id,
    required this.uuid,
    required this.qrCode,
    required this.name,
    required this.typeModel,
    required this.serialNumber,
    this.location = '',
    this.manufacturer,
    this.quantity,
    this.dateOfEntry,
    this.description,
    this.imageData = '',
  });

  String getQRValue() {
    return '{"record_uuid": "$uuid", "qr_code": "$qrCode"}';
  }

  @override
  String toString() {
    return "$id, $uuid, $qrCode, $name, $typeModel, $serialNumber, $location";
  }

  factory InventoryRecord.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'uuid': String uuid,
        'qr_code': String qrCode,
        'name': String name,
        'type_model': String typeModel,
        'serial_number': String serialNumber,
      } =>
        InventoryRecord(
          id: id,
          uuid: uuid,
          qrCode: qrCode,
          name: name,
          typeModel: typeModel,
          serialNumber: serialNumber,
          location: (json['location']?['name'] as String?) ?? '',
          manufacturer: json['manufacturer'] as String?,
          quantity: json['quantity'] as String?,
          dateOfEntry: json['date_of_entry'] as String?,
          description: json['description'] as String?,
          imageData: (json['photos'] as List<dynamic>?)?.isNotEmpty == true
              ? json['photos']![0] as String
              : '',
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
      qrCode: reader.read(),
      name: reader.read(),
      typeModel: reader.read(),
      serialNumber: reader.read(),
      location: reader.read(),
      manufacturer: reader.read(),
      quantity: reader.read(),
      dateOfEntry: reader.read(),
      description: reader.read(),
      imageData: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, InventoryRecord obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.qrCode);
    writer.write(obj.name);
    writer.write(obj.typeModel);
    writer.write(obj.serialNumber);
    writer.write(obj.location);
    writer.write(obj.manufacturer);
    writer.write(obj.quantity);
    writer.write(obj.dateOfEntry);
    writer.write(obj.description);
    writer.write(obj.imageData);
  }
}
