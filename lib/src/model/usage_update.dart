import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class UsageUpdate {
  final String? usageParameterUuid;
  final double? usageParameterValue;
  final String? equipmentUuid;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  @override
  String toString() {
    return "Scan(usageParameterUuid: $usageParameterUuid, usageParameterValue: $usageParameterValue, equipmentUuid: $equipmentUuid)";
  }

  UsageUpdate({
    this.usageParameterUuid,
    this.usageParameterValue,
    this.equipmentUuid,
  });

  Map<String, dynamic> toJson() {
    return {
      'usage_parameter_uuid': usageParameterUuid,
      'usage_parameter_value': usageParameterValue,
      'equipment_uuid': equipmentUuid,
    };
  }
}

class UsageUpdateAdapter extends TypeAdapter<UsageUpdate> {
  @override
  final int typeId = 14;

  @override
  UsageUpdate read(BinaryReader reader) {
    return UsageUpdate(
      usageParameterUuid: reader.read(),
      usageParameterValue: reader.read(),
      equipmentUuid: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, UsageUpdate obj) {
    writer.write(obj.usageParameterUuid);
    writer.write(obj.usageParameterValue);
    writer.write(obj.equipmentUuid);
  }
}
