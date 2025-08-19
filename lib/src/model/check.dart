import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';

class Check {
  final int userId;
  final int machineId;
  final String description;
  final String priority;
  final String problem;
  final List<String> images;
  final int status;
  final int ts;
  final List<int> taskIds;
  bool isSyncing = false;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  @override
  String toString() {
    String imagesString = images
        .where((x) => x.length > 0)
        .toList()
        .map((x) => x.length.toString())
        .join(',');
    return "${userId.toString()}, ${machineId.toString()}, ${description}, ${problem}, ${priority}, ${status.toString()}, ${ts.toString()}, images: (${imagesString})";
  }

  Check(
      {required this.userId,
      required this.machineId,
      required this.description,
      required this.priority,
      required this.problem,
      required this.images,
      required this.status,
      required this.ts,
      required this.taskIds,
      this.isSyncing = false});

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'machine_id': machineId,
      'priority': priority,
      'problem': problem,
      'description': description,
      'status': status,
      'images': images,
      'ts': ts,
      'task_ids': taskIds
    };
  }
}

class MachineCheckAdapter extends TypeAdapter<Check> {
  @override
  final int typeId = 2; // Уникальный ID для адаптера

  @override
  Check read(BinaryReader reader) {
    return Check(
        userId: reader.read(),
        machineId: reader.read(),
        description: reader.read(),
        problem: reader.read(),
        priority: reader.read(),
        images: reader.read(),
        status: reader.read(),
        ts: reader.read(),
        taskIds: reader.read(),
        isSyncing: reader.read());
  }

  @override
  void write(BinaryWriter writer, Check obj) {
    writer.write(obj.userId);
    writer.write(obj.machineId);
    writer.write(obj.description);
    writer.write(obj.problem);
    writer.write(obj.priority);
    writer.write(obj.images);
    writer.write(obj.status);
    writer.write(obj.ts);
    writer.write(obj.taskIds);
    writer.write(obj.isSyncing);
  }
}
