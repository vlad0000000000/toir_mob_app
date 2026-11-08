import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/http/token_refresher.dart';
import 'package:qr_scan_industry/src/model/user.dart';

import 'support/test_data_provider.dart';

/// Сохранение пары после обмена `refresh_token` не должно пережить выход:
/// выход стирает `refresh_token` из записи логина, и запоздавшая запись
/// обмена вернула бы его — сессию можно было бы продлевать без пароля.
void main() {
  late Directory dir;

  User user(String access, String refresh) =>
      User(username: 'ttt', role: 'walker')
        ..JWTToken = access
        ..refreshToken = refresh;

  setUpAll(() => Hive.registerAdapter(UserAdapter(), override: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('refreshed_tokens');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('обмен без выхода — новая пара и у вошедшего, и в записи логина',
      () async {
    final provider = await testDataProvider();
    await provider.userBox.put('ttt', user('a1', 'r1'));
    await provider.userBox.put('auth_user', user('a1', 'r1'));

    await provider
        .saveRefreshedTokens(const TokenPair(access: 'a2', refresh: 'r2'));

    expect(provider.userBox.get('auth_user')!.refreshToken, 'r2');
    expect(provider.userBox.get('ttt')!.refreshToken, 'r2');
    expect(provider.userBox.get('ttt')!.JWTToken, 'a2');
  });

  test('выход посреди записи — refresh_token в записи логина не возвращается',
      () async {
    final provider = await testDataProvider();
    await provider.userBox.put('ttt', user('a1', 'r1'));
    await provider.userBox.put('auth_user', user('a1', 'r1'));

    // Запись пары началась, и в это время — выход, как в `signOut`: новая
    // сессия, пользователь снят, refresh_token стёрт из записи логина.
    final saving = provider
        .saveRefreshedTokens(const TokenPair(access: 'a2', refresh: 'r2'));
    provider.startAccessSession();
    final removing = provider.userBox.delete('auth_user');
    final forgetting = provider.forgetRefreshToken('ttt');
    await Future.wait([saving, removing, forgetting]);

    expect(provider.userBox.get('auth_user'), isNull);
    expect(provider.userBox.get('ttt')!.refreshToken, isNull);

    // И на диске, а не только в памяти.
    await provider.userBox.close();
    final reopened = await Hive.openBox<User>('users');
    expect(reopened.get('ttt')!.refreshToken, isNull);
  });
}
