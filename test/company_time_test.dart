import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart';
import 'package:qr_scan_industry/src/notifications/notification_formatters.dart';
import 'package:qr_scan_industry/src/utils/company_time.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

/// Время компании (бэкенд `71e3243`): обходчик видит и вводит время по поясу
/// компании, как в вебе. Моменты времени от этого не меняются.
void main() {
  tearDown(() => CompanyTime.configure(null));

  // 12:00 UTC: в Омске (UTC+6) 18:00, в Москве 15:00.
  final noonUtc = DateTime.utc(2026, 11, 6, 12);

  group('показ', () {
    test('цифры по поясу компании, момент тот же', () {
      CompanyTime.configure('Asia/Omsk');

      final shown = CompanyTime.of(noonUtc);

      expect(DateFormat('dd.MM.yyyy HH:mm').format(shown), '06.11.2026 18:00');
      expect(shown.isAtSameMomentAs(noonUtc), isTrue);
    });

    test('вечер UTC — уже следующий день у компании', () {
      CompanyTime.configure('Asia/Omsk');

      final shown = CompanyTime.of(DateTime.utc(2026, 11, 6, 20));

      expect(DateFormat('dd.MM HH:mm').format(shown), '07.11 02:00');
    });

    test('общий формат уведомлений, сроков и ремонтов — по поясу компании', () {
      CompanyTime.configure('Europe/Moscow');

      expect(
          NotificationFormatters.formatDateTime(noonUtc), '06.11.2026 15:00');
    });
  });

  group('пояс неизвестен — время телефона', () {
    final phone = DateFormat('HH:mm').format(noonUtc.toLocal());

    test('сервер прошлой версии', () {
      CompanyTime.configure(null);

      expect(CompanyTime.zoneName, isNull);
      expect(DateFormat('HH:mm').format(CompanyTime.of(noonUtc)), phone);
    });

    test('имени нет в базе поясов', () {
      CompanyTime.configure('Mars/Olympus');

      expect(CompanyTime.zoneName, isNull);
      expect(DateFormat('HH:mm').format(CompanyTime.of(noonUtc)), phone);
    });

    test('пояс можно снять', () {
      CompanyTime.configure('Asia/Omsk');
      CompanyTime.configure(null);

      expect(CompanyTime.zoneName, isNull);
    });
  });

  group('ввод', () {
    test('цифры формы — момент по поясу компании', () {
      CompanyTime.configure('Asia/Omsk');

      final picked = CompanyTime.fromFields(2026, 11, 6, 18, 30);

      expect(picked.toUtc(), DateTime.utc(2026, 11, 6, 12, 30));
      expect(picked.hour, 18);
    });

    test('обратно к показу — те же цифры', () {
      CompanyTime.configure('America/New_York');

      final picked = CompanyTime.fromFields(2026, 7, 1, 9, 15);
      final shown = CompanyTime.of(picked);

      expect(DateFormat('dd.MM HH:mm').format(shown), '01.07 09:15');
    });

    test('в прошлую и будущую дату пояс учитывает переход часов', () {
      CompanyTime.configure('America/New_York');

      expect(CompanyTime.fromFields(2026, 1, 15, 12).toUtc().hour, 17);
      expect(CompanyTime.fromFields(2026, 7, 15, 12).toUtc().hour, 16);
    });

    test('сравнение с «сейчас» идёт по моменту', () {
      CompanyTime.configure('Pacific/Kiritimati');

      final inAnHour = CompanyTime.of(
        DateTime.now().add(const Duration(hours: 1)),
      );

      expect(inAnHour.isAfter(DateTime.now()), isTrue);
    });

    test('в черновик уходит обычный DateTime с тем же моментом', () {
      CompanyTime.configure('Asia/Omsk');

      final plain = CompanyTime.plain(CompanyTime.fromFields(2026, 11, 6, 18));

      expect(plain.runtimeType, DateTime);
      expect(plain.isAtSameMomentAs(noonUtc), isTrue);
    });

    test('без пояса — поля телефона', () {
      final picked = CompanyTime.fromFields(2026, 11, 6, 18, 30);

      expect(picked, DateTime(2026, 11, 6, 18, 30));
    });
  });

  group('подпись пояса', () {
    test('Москва', () {
      expect(
        RepairStrings.timeZone(const Duration(hours: 3),
            zoneName: CompanyTime.moscow),
        'МСК (UTC+3)',
      );
    });

    test('другой пояс с тем же сдвигом — не МСК', () {
      expect(
        RepairStrings.timeZone(const Duration(hours: 3),
            zoneName: 'Europe/Istanbul'),
        'UTC+3',
      );
    });

    test('другой сдвиг', () {
      expect(
        RepairStrings.timeZone(const Duration(hours: 6), zoneName: 'Asia/Omsk'),
        'UTC+6',
      );
      expect(
        RepairStrings.timeZone(const Duration(hours: 5, minutes: 30),
            zoneName: 'Asia/Kolkata'),
        'UTC+5:30',
      );
    });

    test('пояс неизвестен — как раньше, по сдвигу телефона', () {
      expect(RepairStrings.timeZone(const Duration(hours: 3)), 'МСК (UTC+3)');
    });
  });

  group('на устройстве', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('company_time');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('смена аккаунта или сервера снимает пояс', () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('company_timezone', 'Asia/Omsk');
      CompanyTime.configure(provider.companyTimezone);
      expect(CompanyTime.zoneName, 'Asia/Omsk');

      await provider.clearCachedData();

      expect(CompanyTime.zoneName, isNull);
    });
  });
}
