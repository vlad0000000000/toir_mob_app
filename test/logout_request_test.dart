import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/http/api.dart';

/// Отзыв сессии при выходе (бэкенд `8b547e8`): сервер отзывает её по
/// `refresh_token` в теле или по Bearer access-токену. Шлём оба — отзыв
/// пройдёт, даже если один из них уже не действует.
void main() {
  test('оба токена — в теле и в заголовке', () {
    final request = logoutRequest(refreshToken: 'r-1', accessToken: 'a-1')!;
    expect(request.headers['Authorization'], 'Bearer a-1');
    expect(request.headers['Content-Type'], 'application/json');
    expect(jsonDecode(request.body!), {'refresh_token': 'r-1'});
  });

  test('только access — без тела', () {
    final request = logoutRequest(accessToken: 'a-1')!;
    expect(request.headers, {'Authorization': 'Bearer a-1'});
    expect(request.body, isNull);
  });

  test('только refresh — без Authorization', () {
    final request = logoutRequest(refreshToken: 'r-1')!;
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(request.body!), {'refresh_token': 'r-1'});
  });

  test('токенов нет — отзывать нечем', () {
    expect(logoutRequest(), isNull);
    expect(logoutRequest(refreshToken: '', accessToken: ''), isNull);
  });
}
