import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';

/// Блокировка доступа по тарифу: сервер отвечает 403 с машиночитаемым
/// `code` на любой запрос, и работать в приложении при ней нельзя.
void main() {
  group('SubscriptionBlockedException.fromResponse', () {
    test('истёкший тариф', () {
      final blocked = SubscriptionBlockedException.fromResponse(
        403,
        '{"detail": "Срок действия тарифа истёк", '
        '"code": "subscription_expired", "days_left": -2}',
      );

      expect(blocked, isNotNull);
      expect(blocked!.accessState, 'subscription_expired');
      expect(blocked.isDeactivated, isFalse);
    });

    test('компанию отключили', () {
      final blocked = SubscriptionBlockedException.fromResponse(
        403,
        '{"detail": "Компания деактивирована. Обратитесь к администратору.", '
        '"code": "company_deactivated"}',
      );

      expect(blocked!.isDeactivated, isTrue);
    });

    test('обычный 403 «нет прав» — не блокировка', () {
      expect(
        SubscriptionBlockedException.fromResponse(
          403,
          '{"detail": "Недостаточно прав", "code": "permission_denied"}',
        ),
        isNull,
      );
    });

    test('другой код ответа, не JSON, без code — не блокировка', () {
      const body = '{"code": "subscription_expired"}';
      expect(SubscriptionBlockedException.fromResponse(401, body), isNull);
      expect(SubscriptionBlockedException.fromResponse(403, '<html>'), isNull);
      expect(
        SubscriptionBlockedException.fromResponse(
            403, '{"detail": "Срок действия тарифа истёк"}'),
        isNull,
      );
    });
  });

  group('очереди при блокировке не теряют данные', () {
    // Это и есть причина наследования от AuthExpiredException: все ветки
    // очередей, разбирающие протухший токен, разбирают и блокировку — запись
    // остаётся в очереди без пометки «отклонено» и уйдёт после продления.
    final blocked = SubscriptionBlockedException('subscription_expired');

    test('для очередей это протухший токен', () {
      expect(blocked, isA<AuthExpiredException>());
    });

    test('осмотр и наработка — повторить позже, не отказ', () {
      expect(isRetryableScanError(blocked), isTrue);
    });

    test('ремонт — повторить позже, не отказ', () {
      expect(isRetryableRepairError(blocked), isTrue);
    });
  });
}
