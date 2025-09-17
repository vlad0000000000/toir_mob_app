import 'package:hive_ce/hive.dart';

class Session {
  final int id;
  final String status;
  final String startTime;
  final String? endTime;

  bool isActive() {
    return status == 'active';
  }

  const Session(
      {required this.id,
      required this.status,
      required this.startTime,
      required this.endTime});

  factory Session.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'start_time': String startTime,
        'end_time': String? endTime,
        'status': String status
      } =>
        Session(id: id, status: status, endTime: endTime, startTime: startTime),
      _ => throw const FormatException('Failed to load session from json.'),
    };
  }
}

class SessionAdapter extends TypeAdapter<Session> {
  @override
  final int typeId = 3;

  @override
  Session read(BinaryReader reader) {
    return Session(
      id: reader.read(),
      startTime: reader.read(),
      endTime: reader.read(),
      status: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Session obj) {
    writer.write(obj.id);
    writer.write(obj.startTime);
    writer.write(obj.endTime);
    writer.write(obj.status);
  }
}
