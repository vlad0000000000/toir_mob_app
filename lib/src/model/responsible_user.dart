import 'package:hive_ce/hive.dart';

class ResponsibleUser {
  final int id;
  final String uuid;
  // final String surname;
  // final String firstName;
  // final String phone;
  // final String patronymic;
  // final String username;
  // final String effectiveRole;
  // final String rolePermissions;
  // final bool isCustomRole;
  // final String baseRole;
  // final int customRoleId;

  ResponsibleUser({
    required this.id,
    required this.uuid,
    // required this.surname,
    // required this.firstName,
    // required this.phone,
    // required this.patronymic,
    // required this.username,
    // required this.effectiveRole,
    // required this.rolePermissions,
    // required this.isCustomRole,
    // required this.baseRole,
    // required this.customRoleId,
  });

  factory ResponsibleUser.fromJson(Map<String, dynamic> json) {
    return ResponsibleUser(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      // surname: json['surname'] as String,
      // firstName: json['first_name'] as String,
      // phone: json['phone'] as String,
      // patronymic: json['patronymic'] as String,
      // username: json['username'] as String,
      // effectiveRole: json['effective_role'] as String,
      // rolePermissions: json['role_permissions'] as String,
      // isCustomRole: json['is_custom_role'] as bool,
      // baseRole: json['base_role'] as String,
      // customRoleId: json['custom_role_id'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      // 'surname': surname,
      // 'first_name': firstName,
      // 'phone': phone,
      // 'patronymic': patronymic,
      // 'username': username,
      // 'effective_role': effectiveRole,
      // 'role_permissions': rolePermissions,
      // 'is_custom_role': isCustomRole,
      // 'base_role': baseRole,
      // 'custom_role_id': customRoleId,
    };
  }
}

class ResponsibleUserAdapter extends TypeAdapter<ResponsibleUser> {
  @override
  final int typeId = 16;

  @override
  ResponsibleUser read(BinaryReader reader) {
    return ResponsibleUser(
      id: reader.read(),
      uuid: reader.read(),
      // surname: reader.read(),
      // firstName: reader.read(),
      // phone: reader.read(),
      // patronymic: reader.read(),
      // username: reader.read(),
      // effectiveRole: reader.read(),
      // rolePermissions: reader.read(),
      // isCustomRole: reader.read(),
      // baseRole: reader.read(),
      // customRoleId: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, ResponsibleUser obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    // writer.write(obj.surname);
    // writer.write(obj.firstName);
    // writer.write(obj.phone);
    // writer.write(obj.patronymic);
    // writer.write(obj.username);
    // writer.write(obj.effectiveRole);
    // writer.write(obj.rolePermissions);
    // writer.write(obj.isCustomRole);
    // writer.write(obj.baseRole);
    // writer.write(obj.customRoleId);
  }
}
