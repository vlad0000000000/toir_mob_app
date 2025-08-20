import 'package:hive_ce/hive.dart';

class User {
  final int id;
  final String login;
  final String passwordHash;
  final int? role;

  const User(
      {required this.id,
      required this.login,
      required this.passwordHash,
      required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'password_hash': String passwordHash,
        'id': int id,
        'login': String login,
        'role': int? role
      } =>
        User(passwordHash: passwordHash, id: id, login: login, role: role),
      _ => throw const FormatException('Failed to load user.'),
    };
  }
}

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 0;

  @override
  User read(BinaryReader reader) {
    return User(
        id: reader.read(), login: reader.read(), passwordHash: reader.read(), role: reader.read());
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer.write(obj.id);
    writer.write(obj.login);
    writer.write(obj.passwordHash);
    writer.write(obj.role);
  }
}
