import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/model/user.dart';

/// Адаптер прошлой версии: семь полей, без `refreshToken`.
class _LegacyUserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 0;

  @override
  User read(BinaryReader reader) => throw UnimplementedError();

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

/// `refreshToken` добавлен в конец записи `User` (обмен при 401): новые
/// записи его хранят, записи прошлой версии читаются без него.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('user_adapter');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  User user() => User(username: 'ttt', role: 'walker')
    ..JWTToken = 'access'
    ..uuid = 'u-1'
    ..refreshToken = 'refresh';

  test('refreshToken сохраняется и читается', () async {
    Hive.registerAdapter(UserAdapter(), override: true);
    final box = await Hive.openBox<User>('users');
    await box.put('auth_user', user());
    await box.close();

    final reopened = await Hive.openBox<User>('users');
    final stored = reopened.get('auth_user')!;
    expect(stored.refreshToken, 'refresh');
    expect(stored.JWTToken, 'access');
    expect(stored.uuid, 'u-1');
  });

  test('запись прошлой версии читается, refreshToken — null', () async {
    Hive.registerAdapter(_LegacyUserAdapter(), override: true);
    final box = await Hive.openBox<User>('users');
    await box.put('auth_user', user());
    await box.close();

    Hive.registerAdapter(UserAdapter(), override: true);
    final reopened = await Hive.openBox<User>('users');
    final stored = reopened.get('auth_user')!;
    expect(stored.refreshToken, isNull);
    expect(stored.JWTToken, 'access');
    expect(stored.uuid, 'u-1');
  });
}
