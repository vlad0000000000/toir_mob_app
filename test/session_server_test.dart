import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/session_server.dart';

/// Сессия привязана к серверу: токен другого сервера (прошлая сборка,
/// другой стенд) не восстанавливается и не пускает офлайн-вход.
void main() {
  const current = 'http://127.0.0.1:8000';

  test('вход этого сервера — свой', () {
    expect(isSameServer(stored: current, current: current), isTrue);
  });

  test('вход другого сервера — чужой', () {
    expect(
      isSameServer(
          stored: 'https://toir-api-dev.example.com', current: current),
      isFalse,
    );
  });

  test('отметки нет (прошлая версия приложения) — свой', () {
    expect(isSameServer(stored: null, current: current), isTrue);
  });

  test('слеш на конце, пробелы и регистр — тот же сервер', () {
    expect(
      isSameServer(
          stored: ' HTTPS://Host.example.com/ ',
          current: 'https://host.example.com'),
      isTrue,
    );
  });

  test('другой порт — другой сервер', () {
    expect(
      isSameServer(stored: 'http://127.0.0.1:8001', current: current),
      isFalse,
    );
  });

  test('ключ отметки — по логину', () {
    expect(userServerKey('ttt'), 'user_server:ttt');
  });
}
