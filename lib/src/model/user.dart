import 'package:hive_ce/hive.dart';

class User {
  final String username;
  String password = '';
  String role = '';
  String JWTToken = '';

  User({required this.username, required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'username': String username,
        'role': String role,
      } =>
        User(username: username, role: role),
      _ => throw const FormatException('Failed to load user.'),
    };
  }
}

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 0;

  @override
  User read(BinaryReader reader) {
    var user = User(username: reader.read(), role: reader.read());
    user.password = reader.read();
    user.JWTToken = reader.read();
    return user;
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer.write(obj.username);
    writer.write(obj.role);
    writer.write(obj.password);
    writer.write(obj.JWTToken);
  }
}
