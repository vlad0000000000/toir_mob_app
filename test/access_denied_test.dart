import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';
import 'package:qr_scan_industry/strings.dart';

/// Отказ сервера по модели доступа на одну операцию: «нет права» и «задачу
/// уже выполнил другой». Тела — как их собирает `AccessError.body` на
/// сервере: `detail` строкой и машинный `code` рядом.
void main() {
  AccessDeniedException parse(int status, String code, [String? detail]) =>
      AccessDeniedException.fromResponse(
        status,
        '{"detail": "${detail ?? 'Текст сервера'}", "code": "$code"}',
      )!;

  group('AccessDeniedException.fromResponse', () {
    test('задачу закрыл другой исполнитель', () {
      final denied = parse(
        409,
        'inspection_closed_by_other',
        'Результат уже записан другим исполнителем. Обновите список задач.',
      );

      expect(denied.isTakenByOther, isTrue);
      expect(denied.isClosedByOther, isTrue);
      expect(denied.isNoRights, isFalse);
      expect(denied.statusCode, 409);
    });

    test('задачу взял другой исполнитель — ещё не закрыта', () {
      final denied = parse(409, 'already_taken');

      expect(denied.isTakenByOther, isTrue);
      expect(denied.isClosedByOther, isFalse);
    });

    test('нет права, направления или подразделения', () {
      for (final code in [
        'permission_denied',
        'direction_denied',
        'division_denied',
      ]) {
        expect(parse(403, code).isNoRights, isTrue, reason: code);
      }
    });

    test('прочие коды и ответы — не наш отказ', () {
      expect(
        AccessDeniedException.fromResponse(
            409, '{"detail": "x", "detail_code": "insufficient_stock"}'),
        isNull,
      );
      expect(
        AccessDeniedException.fromResponse(
            403, '{"detail": "x", "code": "subscription_expired"}'),
        isNull,
        reason: 'закрытый доступ целиком ловит общий клиент',
      );
      expect(
        AccessDeniedException.fromResponse(
            404, '{"detail": "x", "code": "permission_denied"}'),
        isNull,
      );
      expect(AccessDeniedException.fromResponse(403, '<html>'), isNull);
    });

    test('печатается как прежний отказ сервера', () {
      // Переводы ошибок разбирают строку — формат менять нельзя.
      expect(parse(403, 'permission_denied', 'Недостаточно прав').toString(),
          'Exception: Недостаточно прав');
    });
  });

  group('очередь осмотров и наработки', () {
    final closed = parse(409, 'inspection_closed_by_other');
    final taken = parse(409, 'already_taken');
    final noRights = parse(403, 'direction_denied');

    test('повторять автоматически нельзя — это отказ по существу', () {
      expect(isRetryableScanError(closed), isFalse);
      expect(isRetryableScanError(taken), isFalse);
      expect(isRetryableScanError(noRights), isFalse);
      expect(scanErrorStatusCode(closed), 409);
    });

    test('причина — своими словами, по ним узнаётся вид отказа', () {
      final closedReason = scanErrorMessage(closed);
      final takenReason = scanErrorMessage(taken);
      final noRightsReason = scanErrorMessage(noRights);

      expect(closedReason, ScanQueueStrings.errorClosedByOther);
      expect(takenReason, ScanQueueStrings.errorTakenByOther);
      expect(noRightsReason, ScanQueueStrings.errorNoRights);
      expect(isClosedByOtherReason(closedReason), isTrue);
      expect(isTakenByOtherReason(closedReason), isFalse);
      expect(isTakenByOtherReason(takenReason), isTrue);
      expect(isClosedByOtherReason(takenReason), isFalse,
          reason: 'взятую задачу могут вернуть — повтор не прячем');
      expect(isNoRightsReason(noRightsReason), isTrue);
      expect(isNoRightsReason(closedReason), isFalse);
      expect(isNoRightsReason(takenReason), isFalse);
    });

    test('запись прошлой версии — не окончательная, повтор уточнит', () {
      // Раньше оба конфликта сохранялись одной строкой. Какой это был —
      // неизвестно: закрытой её считать нельзя, иначе переназначенную обратно
      // задачу не повторить.
      const legacy = 'Задачу уже выполнил другой исполнитель — ваш '
          'результат сервер не примет';

      expect(ScanQueueStrings.errorTakenOrClosedLegacy, legacy);
      expect(isTakenOrClosedLegacyReason(legacy), isTrue);
      expect(isClosedByOtherReason(legacy), isFalse);
      expect(isTakenByOtherReason(legacy), isFalse);
      // Новые отказы прошлой строкой не помечаются.
      expect(isTakenOrClosedLegacyReason(scanErrorMessage(closed)), isFalse);
      expect(isTakenOrClosedLegacyReason(scanErrorMessage(taken)), isFalse);
    });

    test('сохранённая причина показывается как есть', () {
      expect(scanStoredReason(ScanQueueStrings.errorNoRights),
          ScanQueueStrings.errorNoRights);
    });

    test('нехватка ЗИП — не «нет прав», при смене доступа не повторяется', () {
      expect(
          isNoRightsReason(ScanQueueStrings.errorInsufficientStock), isFalse);
    });

    test('закрытый тем же исполнителем — по-прежнему «уже доставлено»', () {
      // Сервер отвечает этим текстом только тому же исполнителю; чужому —
      // кодом inspection_closed_by_other.
      expect(
          isScanAlreadyDelivered(Exception('Закрытый осмотр нельзя изменить')),
          isTrue);
      expect(isScanAlreadyDelivered(closed), isFalse);
    });
  });

  group('очередь ремонтов', () {
    test('нет прав — своя причина, повтор после смены доступа', () {
      final reason = repairErrorMessage(parse(403, 'permission_denied'));

      expect(reason, repairNoRightsMessage);
      expect(isRepairNoRightsMessage(reason), isTrue);
      expect(isRetryableRepairError(parse(403, 'permission_denied')), isFalse);
    });

    test('ремонт взял другой — текстом сервера', () {
      expect(
        repairErrorMessage(parse(
            409, 'already_taken', 'Ремонт уже взят другим исполнителем.')),
        'Ремонт уже взят другим исполнителем.',
      );
    });

    test('занятое оборудование — не «нет прав»', () {
      expect(isRepairNoRightsMessage(repairEquipmentBusyMessage), isFalse);
    });
  });
}
