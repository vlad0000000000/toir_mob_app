import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';

class Machine {
  final int id;
  final String name;
  final String description;
  final String imageData;

  const Machine(
      {required this.id,
      required this.name,
      required this.imageData,
      required this.description});

  String getQRValue() {
    String projectName = dotenv.env["PROJECT_NAME"]!;
    return GlobalState.digest("${projectName}_machine" + id.toString());
  }

  factory Machine.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'name': String name,
        'description': String description,
        'image_data': String imageData
      } =>
        Machine(
            id: id, name: name, description: description, imageData: imageData),
      _ => throw const FormatException('Failed to load machine.'),
    };
  }
}

class MachineAdapter extends TypeAdapter<Machine> {
  @override
  final int typeId = 1;

  @override
  Machine read(BinaryReader reader) {
    return Machine(
        id: reader.read(),
        name: reader.read(),
        description: reader.read(),
        imageData: reader.read());
  }

  @override
  void write(BinaryWriter writer, Machine obj) {
    writer.write(obj.id);
    writer.write(obj.name);
    writer.write(obj.description);
    writer.write(obj.imageData);
  }
}
