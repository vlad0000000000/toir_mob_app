import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';

class Scan {
  final String publicId;
  final int quantity;
  final int ts;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  @override
  String toString() {
    return "${publicId.toString()}, ${quantity}, ${ts.toString()}";
  }

  const Scan(
      {required this.publicId, required this.quantity, required this.ts});

  Map<String, dynamic> toJson() {
    return {
      'record_public_id': publicId,
      'actual_qty': quantity,
    };
    // return {
    //   'public_id': publicId,
    //   'quantity': quantity,
    //   'ts': ts,
    // };
  }
}

class ScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2; // Уникальный ID для адаптера

  @override
  Scan read(BinaryReader reader) {
    return Scan(
        publicId: reader.read(), quantity: reader.read(), ts: reader.read());
  }

  @override
  void write(BinaryWriter writer, Scan obj) {
    writer.write(obj.publicId);
    writer.write(obj.quantity);
    writer.write(obj.ts);
  }
}
