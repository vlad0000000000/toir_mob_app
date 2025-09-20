import 'package:hive_ce/hive.dart';

class PeriodicityRule {
  final String value;
  final String displayName;

  PeriodicityRule({
    required this.value,
    required this.displayName,
  });

  factory PeriodicityRule.fromJson(Map<String, dynamic> json) {
    return PeriodicityRule(
      value: json['value'] as String,
      displayName: json['display_name'] as String,
    );
  }
}

class PeriodicityRuleAdapter extends TypeAdapter<PeriodicityRule> {
  @override
  final int typeId = 7; // Use the same unique typeId as above

  @override
  PeriodicityRule read(BinaryReader reader) {
    return PeriodicityRule(
      value: reader.read(),
      displayName: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, PeriodicityRule obj) {
    writer.write(obj.value);
    writer.write(obj.displayName);
  }
}
