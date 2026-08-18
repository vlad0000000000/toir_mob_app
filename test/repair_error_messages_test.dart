import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';
import 'package:qr_scan_industry/src/utils/offline_error.dart';

/// Разбор отказов сервера по ремонтам.
///
/// От `isEquipmentBusyMessage` зависит, окончательным ли считается отказ
/// черновика: при занятом оборудовании карточка предлагает перенос и прячет
/// «Повторить», при любом другом — наоборот. Раньше вид отказа угадывался по
/// наличию занявшего ремонта, и повтор пропадал даже после сбоя сервера.
void main() {
  group('isEquipmentBusyMessage', () {
    test('узнаёт занятое оборудование по переводу', () {
      final reason = repairErrorMessage(
        Exception('Equipment is already in repair'),
      );

      expect(reason, repairEquipmentBusyMessage);
      expect(isEquipmentBusyMessage(reason), isTrue);
    });

    test('прочие отказы занятостью не считает', () {
      expect(
        isEquipmentBusyMessage(
            repairErrorMessage(Exception('Equipment not found'))),
        isFalse,
      );
      expect(
        isEquipmentBusyMessage(
            repairErrorMessage(Exception('Не удалось обновить ремонт'))),
        isFalse,
      );
      expect(isEquipmentBusyMessage(null), isFalse);
      expect(isEquipmentBusyMessage(''), isFalse);
    });
  });

  group('repairErrorMessage', () {
    test('английский переводится', () {
      expect(
        repairErrorMessage(Exception('Equipment not found')),
        'Оборудование не найдено',
      );
    });

    test('русский отдаётся как есть', () {
      expect(
        repairErrorMessage(
            Exception('Обходчик может редактировать только открытый ремонт')),
        'Обходчик может редактировать только открытый ремонт',
      );
    });

    test('непереведённый английский не показываем', () {
      expect(
        repairErrorMessage(Exception('Some internal failure')),
        'Не удалось выполнить действие',
      );
    });

    test('обрыв связи и протухший токен — свои формулировки', () {
      expect(
        repairErrorMessage(const SocketException('no route')),
        startsWith('Нет связи'),
      );
      expect(
        repairErrorMessage(AuthExpiredException()),
        startsWith('Сессия истекла'),
      );
    });
  });

  group('isRetryableRepairError', () {
    test('обрыв связи — повторяем', () {
      expect(isRetryableRepairError(const SocketException('no route')), isTrue);
    });

    test('занятое оборудование — не повторяем автоматически', () {
      expect(
        isRetryableRepairError(Exception('Equipment is already in repair')),
        isFalse,
      );
    });

    test('ключ идемпотентности ещё в работе — повторяем', () {
      expect(
        isRetryableRepairError(
          Exception('Idempotency key is being processed; retry the request'),
        ),
        isTrue,
      );
    });
  });

  _offlineClassificationTests();
}

/// Разбор сбоя связи. Именно здесь ломалось создание ремонта без сервера:
/// обрыв принимали за отказ по существу, и черновик не попадал в очередь.
void _offlineClassificationTests() {
  group('офлайн против отказа сервера', () {
    test('ClientException — это обрыв связи, а не отказ', () {
      // package:http заворачивает в неё разрыв соединения: сокетного типа в
      // ней нет, и по прежним признакам она не опознавалась.
      final error = http.ClientException(
        'Connection closed before full header was received',
        Uri.parse('https://example.org/v1/repairs/'),
      );
      expect(isOfflineError(error), isTrue);
      expect(isRetryableRepairError(error), isTrue);
      expect(repairErrorMessage(error),
          'Нет связи с сервером. Проверьте интернет и повторите.');
    });

    test('SocketException по-прежнему опознаётся', () {
      expect(
          isRetryableRepairError(const SocketException('Failed host lookup')),
          isTrue);
    });

    test('502 от шлюза — повторяем, а не показываем ошибку', () {
      final error =
          ServerFailureException(502, 'Не удалось создать ремонт: 502');
      expect(isRetryableRepairError(error), isTrue);
    });

    test('503 и 504 тоже временные', () {
      expect(isRetryableRepairError(ServerFailureException(503, 'x')), isTrue);
      expect(isRetryableRepairError(ServerFailureException(504, 'x')), isTrue);
    });

    test('409 «оборудование уже в ремонте» — отказ по существу', () {
      final error =
          ServerFailureException(409, 'Оборудование уже находится в ремонте');
      expect(isRetryableRepairError(error), isFalse);
      // Текст сервера обходчику показываем как есть.
      expect(repairErrorMessage(error), 'Оборудование уже находится в ремонте');
    });

    test('403 не повторяем', () {
      expect(isRetryableRepairError(ServerFailureException(403, 'Нет прав')),
          isFalse);
    });

    test('нет токена — черновик ждёт входа, а не отклоняется', () {
      expect(isRetryableRepairError(Exception('Not authenticated')), isTrue);
    });

    test('ServerFailureException печатается как прежний Exception', () {
      // На тексте держатся переводы ошибок — формат менять нельзя.
      expect(ServerFailureException(500, 'Сервер прилёг').toString(),
          'Exception: Сервер прилёг');
    });
  });
}
