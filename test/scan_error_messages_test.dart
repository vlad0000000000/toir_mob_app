import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/strings.dart';

/// Классификация отказов очереди осмотров.
///
/// Ошибиться здесь дорого: если временный сбой принять за окончательный
/// отказ, осмотр перестанет отправляться сам и обходчик потеряет данные
/// обхода. Обратная ошибка дешевле, но приводит к бесконечным повторам.
void main() {
  group('isRetryableScanError', () {
    test('обрыв связи — повторяем', () {
      expect(
        isRetryableScanError(const SocketException('no route')),
        isTrue,
      );
      expect(
        isRetryableScanError(Exception('Failed host lookup: api')),
        isTrue,
      );
      expect(isRetryableScanError(Exception('TimeoutException after 15s')),
          isTrue);
    });

    test('нет токена — повторяем, а не помечаем отказом', () {
      // Цикл отправки крутится и после выхода из аккаунта. Если счесть это
      // отказом сервера, осмотр получит пометку и больше не уйдёт сам.
      expect(isRetryableScanError(Exception('Not authenticated')), isTrue);
      expect(isRetryableScanError(AuthExpiredException()), isTrue);
    });

    test('сбой сервера (5xx) — повторяем', () {
      expect(
        isRetryableScanError(Exception('Внутренняя ошибка [HTTP 500]')),
        isTrue,
      );
    });

    test('отказ по существу (4xx) — не повторяем', () {
      expect(
        isRetryableScanError(Exception('Задача не найдена [HTTP 404]')),
        isFalse,
      );
    });

    test('нехватка ЗИП — не повторяем: сама не рассосётся', () {
      expect(
        isRetryableScanError(
          InsufficientStockException('Недостаточно ЗИП на складе', const []),
        ),
        isFalse,
      );
    });

    test('ключ события ещё обрабатывается (409) — повторяем', () {
      // Параллельный запрос с тем же ключом не завершился: сервер просит
      // повторить, это не отказ.
      expect(
        isRetryableScanError(
            Exception('Idempotency-Key is being processed; retry the request '
                '[HTTP 409]')),
        isTrue,
      );
    });

    test('ключ с другим запросом (409) — отказ, не повторяем', () {
      expect(
        isRetryableScanError(Exception(
            'Idempotency-Key was already used with a different request '
            '[HTTP 409]')),
        isFalse,
      );
    });
  });

  group('scanErrorMessage', () {
    test('английский текст сервера переводится', () {
      expect(
        scanErrorMessage(Exception('Inspection was not found [HTTP 404]')),
        'Задача не найдена — возможно, её удалили',
      );
    });

    test('русский текст сервера отдаётся как есть, без метки кода', () {
      expect(
        scanErrorMessage(
            Exception('Закрытый осмотр нельзя изменить [HTTP 400]')),
        'Закрытый осмотр нельзя изменить',
      );
    });

    test('непереведённый английский уходит в общий фолбэк', () {
      expect(
        scanErrorMessage(Exception('Something went sideways [HTTP 418]')),
        'Сервер не принял осмотр',
      );
    });

    test('нехватка ЗИП — своя формулировка, а не текст сервера', () {
      // Сервер отдаёт `detail` по-английски и локализацию оставляет клиенту,
      // поэтому текст берётся из строк приложения, а не из исключения.
      expect(
        scanErrorMessage(
          InsufficientStockException(
              'Insufficient spare parts in warehouses', const []),
        ),
        ScanQueueStrings.errorInsufficientStock,
      );
    });

    test('английская причина из старой очереди переводится при показе', () {
      expect(
        scanStoredReason('Insufficient spare parts in warehouses'),
        ScanQueueStrings.errorInsufficientStock,
      );
    });

    test('непереведённое английское в очереди заменяется общей фразой', () {
      expect(scanStoredReason('Something odd'), 'Сервер не принял осмотр');
    });

    test('русская причина из очереди отдаётся как есть', () {
      expect(scanStoredReason('Задача не найдена'), 'Задача не найдена');
    });
  });

  group('isScanAlreadyDelivered', () {
    test('«осмотр уже закрыт» — это успех, а не отказ', () {
      // Ответ на успешный PATCH мог потеряться: повтор приходит на уже
      // закрытый осмотр. Данные на месте, помечать отказом нельзя.
      expect(
        isScanAlreadyDelivered(
            Exception('Закрытый осмотр нельзя изменить [HTTP 400]')),
        isTrue,
      );
    });

    test('прочие отказы успехом не считаются', () {
      expect(
        isScanAlreadyDelivered(Exception('Задача не найдена [HTTP 404]')),
        isFalse,
      );
    });

    test('410 по ключу события — доставлено: осмотр удалили на сервере', () {
      expect(
        isScanAlreadyDelivered(Exception(
            'The inspection for this Idempotency-Key no longer exists '
            '[HTTP 410]')),
        isTrue,
      );
    });
  });

  group('отказы по наработке в составе осмотра', () {
    test('уменьшение запрещено — по-русски', () {
      final message = scanErrorMessage(Exception(
          'Cannot decrease current_value when prohibit_decrease is True '
          '[HTTP 400]'));
      expect(message, contains('уменьшать её запрещено'));
    });

    test('чужой параметр — по-русски, без uuid', () {
      final message = scanErrorMessage(Exception(
          'Usage parameter 00000000-0000-0000-0000-000000000001 was not found '
          'for inspection equipment [HTTP 404]'));
      expect(message, contains('Параметр наработки не найден'));
      expect(message, isNot(contains('0000')));
    });

    test('закрытый осмотр не принимает наработку', () {
      final message = scanErrorMessage(Exception(
          'A closed inspection cannot accept new usage_updates [HTTP 409]'));
      expect(message, contains('Задача уже закрыта'));
    });
  });

  group('scanErrorStatusCode', () {
    test('код вынимается из метки', () {
      expect(scanErrorStatusCode(Exception('текст [HTTP 409]')), 409);
    });

    test('до сервера не дошли — кода нет', () {
      expect(scanErrorStatusCode(const SocketException('no route')), isNull);
    });
  });
}
