import 'package:hive_ce/hive.dart';

import 'access_profile.dart';

class User {
  final String username;
  String password = '';
  String role;
  String effectiveRole = '';
  String JWTToken = '';
  String uuid = '';
  int customRoleId = -1;

  /// Компания пользователя из `/user/me` (`access_scope.company_id`) — для
  /// блокировки офлайн-входа по компании (`SubscriptionBlocks`).
  ///
  /// В Hive **не пишется** (адаптер не трогаем): нужна только в момент входа,
  /// а связь «логин → компания» хранится отдельно в `stringBox`.
  String? companyId;

  /// Профиль доступа из `/user/me` — только что полученный с сервера.
  ///
  /// В Hive **не пишется**, как и [companyId]: профиль живёт в `stringBox`
  /// под uuid пользователя (`DataProvider.storedAccessProfile`). Пользователь
  /// из бокса этого поля не несёт.
  AccessProfile? accessProfile;

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
    user.effectiveRole = reader.read();
    user.customRoleId = reader.read();
    user.password = reader.read();
    user.JWTToken = reader.read();
    user.uuid = reader.read();
    return user;
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer.write(obj.username);
    writer.write(obj.role);
    writer.write(obj.effectiveRole);
    writer.write(obj.customRoleId);
    writer.write(obj.password);
    writer.write(obj.JWTToken);
    writer.write(obj.uuid);
  }
}
