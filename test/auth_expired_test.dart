import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/access_session.dart';

/// «Сессия истекла» по ответам синхронизации, а не только очередей: 401 на
/// любой запрос живой сессии поднимает флаг (стенд 05.11 — токен чужого
/// сервера, синхронизация молча падала на 401). Снимает его только новая
/// сессия: поздний 200 старого запроса не гасит свежий отказ.
void main() {
  bool raises(
    int statusCode, {
    String? requestToken = 'token-a',
    String? currentToken = 'token-a',
    int requestSession = 3,
    int currentSession = 3,
  }) =>
      raisesAuthExpired(
        statusCode: statusCode,
        requestToken: requestToken,
        currentToken: currentToken,
        requestSession: requestSession,
        currentSession: currentSession,
      );

  group('ответ живой сессии', () {
    test('401 поднимает флаг', () {
      expect(raises(401), isTrue);
    });

    test('успешный ответ флаг не снимает — снимает только новый вход', () {
      // Запрос, ушедший до 401, может ответить 200 позже него.
      for (final code in [200, 201, 204]) {
        expect(raises(code), isFalse, reason: 'код $code');
      }
    });

    test('прочие коды флаг не поднимают', () {
      // 403/404/409 может отдать и прокси, 5xx — сбой, а не ответ о сессии.
      for (final code in [307, 400, 403, 404, 409, 422, 429, 500, 502, 503]) {
        expect(raises(code), isFalse, reason: 'код $code');
      }
    });
  });

  group('ответ не текущей сессии флаг не поднимает', () {
    test('401 на запрос, ушедший до выхода и нового входа', () {
      expect(raises(401, requestSession: 2), isFalse);
    });

    test('повторный вход с тем же токеном — решает номер сессии', () {
      expect(raises(401, requestSession: 2, currentSession: 3), isFalse);
    });

    test('запрос с токеном другого пользователя', () {
      expect(raises(401, requestToken: 'token-b'), isFalse);
    });

    test('запрос входа: /user/me со свежим токеном до его сохранения', () {
      expect(raises(401, requestToken: 'fresh', currentToken: 'old'), isFalse);
    });

    test('запрос без токена — сам вход', () {
      expect(raises(401, requestToken: null), isFalse);
    });

    test('никто не вошёл', () {
      expect(raises(401, currentToken: null), isFalse);
    });
  });

  group('выход на вход по истёкшей сессии', () {
    bool due({bool expired = true, bool authorized = true, int forms = 0}) =>
        shouldSignOutExpiredSession(
          expired: expired,
          authorized: authorized,
          openForms: forms,
        );

    test('сессия истекла, форм нет — выводим', () {
      expect(due(), isTrue);
    });

    test('открыта форма — ждём, пока обходчик с неё уйдёт', () {
      expect(due(forms: 1), isFalse);
      expect(due(forms: 2), isFalse);
    });

    test('форму закрыли — выводим', () {
      expect(due(forms: 0), isTrue);
    });

    test('сессия жива — не выводим', () {
      expect(due(expired: false), isFalse);
    });

    test('уже вышли — второй раз не выводим', () {
      expect(due(authorized: false), isFalse);
    });
  });
}
