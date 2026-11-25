import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/mobile_installation.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/mobile_support_status.dart';
import 'package:qr_scan_industry/src/model/user.dart';
import 'package:qr_scan_industry/src/notifications/push/notifications_task_handler.dart';
import 'package:qr_scan_industry/src/widgets/support_status_banner.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

/// Статус поддержки версии (бэкенд `81f644c`): плашка на главной и кнопка
/// RuStore. Сервер ничего не блокирует — ошибка здесь значит не тот текст
/// или ссылка, открытая не туда.
void main() {
  final ends = DateTime.utc(2026, 12, 1, 9);

  MobileSupportStatus status(String value, {DateTime? endsAt, String? url}) =>
      MobileSupportStatus(
        status: value,
        versionName: '1.0',
        supportEndsAt: endsAt,
        updateUrl: url,
      );

  group('разбор ответа', () {
    test('полный ответ сервера', () {
      final parsed = MobileSupportStatus.fromJson({
        'release_uuid': '00000000-0000-0000-0000-000000000001',
        'version_name': '1.0',
        'status': 'ending_soon',
        'support_ends_at': '2026-12-01T09:00:00Z',
        'support_updated_at': '2026-11-18T09:00:00Z',
        'update_url':
            'https://www.rustore.ru/catalog/app/pakgroup.qr.scanner.prod',
      })!;
      expect(parsed.status, 'ending_soon');
      expect(parsed.versionName, '1.0');
      expect(parsed.supportEndsAt, ends);
      expect(parsed.safeUpdateUri?.host, 'www.rustore.ru');
    });

    test('без даты и ссылки — поля пустые', () {
      final parsed = MobileSupportStatus.fromJson({'status': 'unknown'})!;
      expect(parsed.versionName, isNull);
      expect(parsed.supportEndsAt, isNull);
      expect(parsed.updateUrl, isNull);
    });

    test('без статуса или не объект — показывать нечего', () {
      expect(MobileSupportStatus.fromJson({}), isNull);
      expect(MobileSupportStatus.fromJson({'status': ''}), isNull);
      expect(MobileSupportStatus.fromJson(const []), isNull);
      expect(MobileSupportStatus.fromJson(null), isNull);
    });

    test('сохранённый статус читается обратно', () {
      final original = status('ending_soon',
          endsAt: ends, url: 'https://www.rustore.ru/catalog/app/x');
      final restored = MobileSupportStatus.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      )!;
      expect(restored.status, original.status);
      expect(restored.versionName, original.versionName);
      expect(restored.supportEndsAt, original.supportEndsAt);
      expect(restored.updateUrl, original.updateUrl);
    });
  });

  group('что показать', () {
    final before = ends.subtract(const Duration(days: 1));

    test('поддерживается или неизвестна — ничего', () {
      expect(status('supported').noticeAt(before), SupportNotice.none);
      expect(status('unknown').noticeAt(before), SupportNotice.none);
    });

    test('скоро завершится — до даты', () {
      expect(
        status('ending_soon', endsAt: ends).noticeAt(before),
        SupportNotice.endingSoon,
      );
      expect(status('ending_soon').noticeAt(before), SupportNotice.endingSoon);
    });

    test('дата прошла, пока телефон без связи, — «завершена»', () {
      expect(
        status('ending_soon', endsAt: ends).noticeAt(ends),
        SupportNotice.obsolete,
      );
    });

    test('завершена — «завершена»', () {
      expect(status('obsolete', endsAt: ends).noticeAt(before),
          SupportNotice.obsolete);
    });

    test('ограничение работы важнее дат поддержки (811c4dc)', () {
      for (final value in ['supported', 'ending_soon', 'obsolete']) {
        final blocked = MobileSupportStatus(status: value, workBlocked: true);
        expect(blocked.noticeAt(before), SupportNotice.workBlocked,
            reason: value);
      }
    });
  });

  group('отладочный показ плашки', () {
    final now = DateTime.utc(2026, 11, 23, 9);

    test('по умолчанию выключен — в обычной сборке плашка настоящая', () {
      expect(previewSupportStatusMode, isEmpty);
      expect(previewSupportStatus(now), isNull);
    });

    test('три вида плашки, у каждого кнопка RuStore', () {
      final cases = {
        'work_blocked': SupportNotice.workBlocked,
        'obsolete': SupportNotice.obsolete,
        'ending_soon': SupportNotice.endingSoon,
      };
      for (final entry in cases.entries) {
        final status = previewSupportStatus(now, mode: entry.key)!;
        expect(status.noticeAt(now), entry.value, reason: entry.key);
        expect(status.safeUpdateUri, isNotNull, reason: entry.key);
      }
    });

    test('неизвестное значение — показа нет', () {
      expect(previewSupportStatus(now, mode: 'blocked'), isNull);
    });
  });

  group('ограничение работы (811c4dc)', () {
    test('work_blocked разбирается и переживает сохранение', () {
      final parsed = MobileSupportStatus.fromJson({
        'status': 'supported',
        'work_blocked': true,
      })!;
      expect(parsed.workBlocked, isTrue);
      expect(
        MobileSupportStatus.fromJson(parsed.toJson())!.workBlocked,
        isTrue,
      );
    });

    test('сервер прошлой версии без поля — не ограничено', () {
      expect(
        MobileSupportStatus.fromJson({'status': 'obsolete'})!.workBlocked,
        isFalse,
      );
      expect(
        MobileSupportStatus.fromJson({
          'status': 'obsolete',
          'work_blocked': 'true',
        })!
            .workBlocked,
        isFalse,
      );
    });

    test('текст плашки: очередь уйдёт, RuStore — если есть ссылка', () {
      expect(MobileSupportStrings.workBlockedBody(true),
          contains('Обновите приложение в RuStore.'));
      expect(MobileSupportStrings.workBlockedBody(false),
          endsWith('Обновите приложение.'));
      expect(
          MobileSupportStrings.workBlockedBody(false), contains('отправятся'));
    });
  });

  group('ссылка на RuStore', () {
    test('только https', () {
      expect(status('obsolete', url: 'https://www.rustore.ru/x').safeUpdateUri,
          isNotNull);
      expect(status('obsolete', url: 'http://www.rustore.ru/x').safeUpdateUri,
          isNull);
      expect(status('obsolete', url: 'intent://x#Intent;end').safeUpdateUri,
          isNull);
      expect(status('obsolete', url: 'https://').safeUpdateUri, isNull);
      expect(status('obsolete').safeUpdateUri, isNull);
    });
  });

  group('тексты плашки', () {
    test('скоро завершится — с версией, датой и RuStore', () {
      expect(
        MobileSupportStrings.endingSoonBody(
          '1.0',
          formatSupportEnd(DateTime(2026, 12, 1, 12, 0)),
          true,
        ),
        'Поддержка версии 1.0 завершится 01.12.2026 в 12:00. '
        'Обновите приложение в RuStore.',
      );
    });

    test('без версии, даты и ссылки', () {
      expect(
        MobileSupportStrings.endingSoonBody(null, null, false),
        'Поддержка вашей версии скоро завершится. Обновите приложение.',
      );
      expect(
        MobileSupportStrings.obsoleteBody(null, false),
        'Ваша версия больше не поддерживается. Обновите приложение.',
      );
      expect(
        MobileSupportStrings.obsoleteBody('1.0', true),
        'Версия 1.0 больше не поддерживается. Обновите приложение в RuStore.',
      );
    });
  });

  test('сигналы служебных методов — не уведомления', () {
    expect(isClientSignalEvent('mobile_support_changed'), isTrue);
    expect(isClientSignalEvent('announcements_changed'), isTrue);
    expect(isClientSignalEvent('notification'), isFalse);
    expect(isClientSignalEvent('repair_changed'), isFalse);
  });

  group('сохранённый статус', () {
    late Directory dir;

    setUpAll(() => Hive.registerAdapter(UserAdapter(), override: true));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('support_status');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('у каждого обходчика свой, после выхода — нет', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      final a = User(username: 'a', role: 'walker')..uuid = 'user-a';
      final b = User(username: 'b', role: 'walker')..uuid = 'user-b';
      await provider.stringBox.put(
        supportStatusKey('user-a', API.baseUrl),
        encodeStoredSupportStatus(status('obsolete'), 'build-1'),
      );

      provider.loadSupportStatus(a, buildSignature: 'build-1');
      expect(provider.supportStatus.value?.status, 'obsolete');

      // Обновили приложение — статус прошлой сборки ждёт сервера.
      provider.loadSupportStatus(a, buildSignature: 'build-2');
      expect(provider.supportStatus.value, isNull);

      provider.loadSupportStatus(b, buildSignature: 'build-1');
      expect(provider.supportStatus.value, isNull);

      provider.loadSupportStatus(null);
      expect(provider.supportStatus.value, isNull);
    });

    test('битая запись — как отсутствующая', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      final a = User(username: 'a', role: 'walker')..uuid = 'user-a';
      await provider.stringBox
          .put(supportStatusKey('user-a', API.baseUrl), '{');

      provider.loadSupportStatus(a);
      expect(provider.supportStatus.value, isNull);
    });
  });
}
