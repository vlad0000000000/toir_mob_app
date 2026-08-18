import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/http/api.dart';

/// Окно недоступности — то, из-за чего офлайн перестал «долго грузиться».
///
/// Без него каждое следующее действие заново открывало соединение к серверу,
/// которого нет, и ждало таймаута. Проверяем именно поведение отметки: сама
/// сеть тут не участвует.
void main() {
  setUp(API.markServerReachable);

  group('отметка недоступности сервера', () {
    test('по умолчанию сервер считается доступным', () {
      expect(API.isServerKnownUnreachable, isFalse);
    });

    test('после сбоя запросы отсекаются без обращения к сети', () {
      API.markServerUnreachable();
      expect(API.isServerKnownUnreachable, isTrue);
    });

    test('ответ сервера снимает отметку сразу', () {
      API.markServerUnreachable();
      API.markServerReachable();
      expect(API.isServerKnownUnreachable, isFalse);
    });

    test('явное действие обходчика снимает отметку', () {
      // Вход, «Синхронизировать данные», «Повторить»: обходчик мог только что
      // дойти до места со связью — отвечать ему по памяти нельзя.
      API.markServerUnreachable();
      API.retryConnectionNow();
      expect(API.isServerKnownUnreachable, isFalse);
    });

    test('окно живёт полминуты и не дольше', () {
      // Не бесконечная блокировка: по истечении окна следующий запрос обязан
      // сходить в сеть честно.
      expect(API.offlineWindow, const Duration(seconds: 30));
    });
  });
}
