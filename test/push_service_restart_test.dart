import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/notifications/push/push_notifications_controller.dart';

/// Фоновый сервис уведомлений, поднятый Android после обновления сборки,
/// держит адрес и токен прошлой: такой нужно перезапустить с текущими
/// (стенд 05.11 — SSE ходил на адрес dev-сервера).
void main() {
  const url = 'http://127.0.0.1:8000';
  const jwt = 'token-a';

  bool needs({String? savedUrl = url, String? savedJwt = jwt}) =>
      pushServiceNeedsRestart(
        savedUrl: savedUrl,
        savedJwt: savedJwt,
        currentUrl: url,
        currentJwt: jwt,
      );

  test('адрес и токен совпадают — не трогаем', () {
    expect(needs(), isFalse);
  });

  test('адрес прошлой сборки — перезапуск', () {
    expect(needs(savedUrl: 'https://toir-api-dev.example.com'), isTrue);
  });

  test('токен прошлой сессии — перезапуск', () {
    expect(needs(savedJwt: 'token-old'), isTrue);
  });

  test('данных нет — перезапуск: сервис их сохранит', () {
    expect(needs(savedUrl: null), isTrue);
    expect(needs(savedJwt: null), isTrue);
  });

  test('пробелы по краям не считаются отличием', () {
    expect(needs(savedUrl: ' $url ', savedJwt: '$jwt\n'), isFalse);
  });
}
