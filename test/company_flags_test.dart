import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/company.dart';

/// Флаги компании из блока `company` ответа `GET /v1/user/me` — как его
/// собирает `build_me` на сервере (`MyCompanySchema`).
void main() {
  Map<String, dynamic> me(
          {Object? company = const {
            'uuid': 'company-uuid',
            'name': 'Тестовая',
            'logo_url': 'https://example.test/logo.png',
            'allow_requests_without_qr': true,
            'allow_multiple_tasks_per_qr_scan': false,
          }}) =>
      {
        'uuid': 'user-uuid',
        'access_scope': {'company_id': 42},
        if (company != null) 'company': company,
      };

  final cached = Company(
    id: 42,
    name: 'Старое имя',
    currentTariff: 'pro',
    tariffValidUntil: DateTime.utc(2027, 1, 1),
    allowRequestsWithoutQr: false,
  );

  group('CompanyFlags.fromMe', () {
    test('разбирает флаги и название', () {
      final flags = CompanyFlags.fromMe(me())!;

      expect(flags.allowRequestsWithoutQr, isTrue);
      expect(flags.allowMultipleTasksPerQrScan, isFalse);
      expect(flags.name, 'Тестовая');
    });

    test('сервер прошлой версии блока не присылает — флагов нет', () {
      // `null`, а не «всё выключено»: флаги тогда берутся из /company/me.
      expect(CompanyFlags.fromMe(me(company: null)), isNull);
    });

    test('блок без флагов — не разбираем', () {
      expect(CompanyFlags.fromMe(me(company: {'name': 'Без флагов'})), isNull);
    });
  });

  group('CompanyFlags.applyTo', () {
    test('флаги — новые, тариф — из прежнего кэша', () {
      final company =
          CompanyFlags.fromMe(me())!.applyTo(cached, companyId: 42)!;

      expect(company.allowRequestsWithoutQr, isTrue);
      expect(company.name, 'Тестовая');
      expect(company.currentTariff, 'pro');
      expect(company.tariffValidUntil, DateTime.utc(2027, 1, 1));
    });

    test('кэша нет — собираем по company_id из профиля', () {
      final company = CompanyFlags.fromMe(me())!.applyTo(null, companyId: 42)!;

      expect(company.id, 42);
      expect(company.allowRequestsWithoutQr, isTrue);
      expect(company.currentTariff, isNull);
    });

    test('ни кэша, ни company_id — собрать не из чего', () {
      expect(CompanyFlags.fromMe(me())!.applyTo(null, companyId: null), isNull);
    });
  });
}
