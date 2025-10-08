import 'package:hive_ce/hive.dart';

class UsageUnit {
  final String value;
  final String displayName;
  final String shortName;

  UsageUnit({
    required this.value,
    required this.displayName,
    required this.shortName,
  });

  factory UsageUnit.fromJson(Map<String, dynamic> json) {
    return UsageUnit(
      value: json['value'] as String,
      displayName: json['display_name'] as String,
      shortName: json['short_name'] as String,
    );
  }
}

class UsageUnitAdapter extends TypeAdapter<UsageUnit> {
  @override
  final int typeId = 12; // Use a unique typeId

  @override
  UsageUnit read(BinaryReader reader) {
    return UsageUnit(
      value: reader.read(),
      displayName: reader.read(),
      shortName: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, UsageUnit obj) {
    writer.write(obj.value);
    writer.write(obj.displayName);
    writer.write(obj.shortName);
  }
}
