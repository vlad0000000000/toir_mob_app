import 'package:hive_ce/hive.dart';

class EquipmentState {
  final Map<String, String> states;

  EquipmentState({required this.states});

  factory EquipmentState.fromJson(Map<String, dynamic> json) {
    final statesMap = json['states'] as Map<String, dynamic>;
    return EquipmentState(
      states: Map<String, String>.from(
        statesMap.map((key, value) => MapEntry(key, value as String)),
      ),
    );
  }

  String? getStateName(String stateCode) {
    return states[stateCode];
  }
}

class EquipmentStateAdapter extends TypeAdapter<EquipmentState> {
  @override
  final int typeId = 18;

  @override
  EquipmentState read(BinaryReader reader) {
    final statesMap = reader.read() as Map<dynamic, dynamic>;
    return EquipmentState(
      states: Map<String, String>.from(
        statesMap.map((key, value) => MapEntry(key.toString(), value.toString())),
      ),
    );
  }

  @override
  void write(BinaryWriter writer, EquipmentState obj) {
    writer.write(obj.states);
  }
}
