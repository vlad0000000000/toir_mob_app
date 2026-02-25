import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class PeriodicTaskRequest {
  final String equipmentUuid;
  final String? node;
  final String title;
  final String? description;
  final String periodicityRule;
  final List<int>? customRoleIds;
  final String nextDueAt;
  final Map<String, dynamic> params;
  final List<String>? photos;

  String key() {
    return GlobalState.digest(jsonEncode({
      'equipment_uuid': equipmentUuid,
      'node': node,
      'title': title,
      'description': description,
      'periodicity_rule': periodicityRule,
      'custom_role_ids': customRoleIds,
      'next_due_at': nextDueAt,
      'params': params,
      'photos': photos,
    }));
  }

  @override
  String toString() {
    return "PeriodicTaskRequest(title: $title, equipmentUuid: $equipmentUuid)";
  }

  PeriodicTaskRequest({
    required this.equipmentUuid,
    this.node,
    required this.title,
    this.description,
    required this.periodicityRule,
    this.customRoleIds,
    required this.nextDueAt,
    required this.params,
    required this.photos
  });

  // "equipment_uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  // "node": "string",
  // "title": "string",
  // "description": "string",
  // "periodicity_rule": "once",
  // "params": {
  // "target_type": "ad_hoc",
  // "result_status": "open",
  // "priority": "low"
  // }

  Map<String, dynamic> toJson() {
    return {
      'equipment_uuid': equipmentUuid,
      if (node != null) 'node': node,
      'title': title,
      if (description != null) 'description': description,
      'periodicity_rule': periodicityRule,
      // if (customRoleIds != null && customRoleIds!.isNotEmpty)
      //   'custom_role_ids': customRoleIds,
      // 'next_due_at': nextDueAt,
      'params': params
    };
  }
}

class PeriodicTaskRequestAdapter extends TypeAdapter<PeriodicTaskRequest> {
  @override
  final int typeId = 20;

  @override
  PeriodicTaskRequest read(BinaryReader reader) {
    return PeriodicTaskRequest(
      equipmentUuid: reader.read(),
      node: reader.read(),
      title: reader.read(),
      description: reader.read(),
      periodicityRule: reader.read(),
      customRoleIds: reader.read()?.cast<int>(),
      nextDueAt: reader.read(),
      params: Map<String, dynamic>.from(reader.read()),
      photos: reader.read().cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, PeriodicTaskRequest obj) {
    writer.write(obj.equipmentUuid);
    writer.write(obj.node);
    writer.write(obj.title);
    writer.write(obj.description);
    writer.write(obj.periodicityRule);
    writer.write(obj.customRoleIds);
    writer.write(obj.nextDueAt);
    writer.write(obj.params);
    writer.write(obj.photos);
  }
}
