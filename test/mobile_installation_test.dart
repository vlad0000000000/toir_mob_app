import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/mobile_installation.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/mobile_build.dart';
import 'package:qr_scan_industry/src/model/mobile_support_status.dart';
import 'package:qr_scan_industry/src/model/user.dart';
import 'package:qr_scan_industry/src/notifications/push/notifications_task_handler.dart';
import 'package:qr_scan_industry/src/notifications/push/push_notifications_controller.dart';

import 'support/test_data_provider.dart';

/// Установка приложения (бэкенд `81f644c`): постоянный UUID, регистрация не
/// чаще раза в 5 минут и заголовок только после неё — иначе сервер перестал
/// бы отдавать объявления карточками 1.0, а показать их самим ещё нечем.
void main() {
  group('UUID установки', () {
    test('новый — UUID версии 4', () {
      final id = newInstallationId(Random(1));
      expect(isInstallationId(id), isTrue);
      expect(id[14], '4');
      expect('89ab'.contains(id[19]), isTrue);
    });

    test('каждый раз новый', () {
      final ids = {for (var i = 0; i < 100; i++) newInstallationId()};
      expect(ids.length, 100);
    });

    test('битое значение — как отсутствующее', () {
      expect(isInstallationId(null), isFalse);
      expect(isInstallationId(''), isFalse);
      expect(isInstallationId('not-a-uuid'), isFalse);
      expect(isInstallationId('ABCDEF00-0000-4000-8000-000000000000'), isFalse);
    });
  });

  group('сборка для сервера', () {
    test('данные пакета — в схему сервера', () {
      final build = MobileBuild.fromPackage(
        isIos: false,
        packageName: ' pakgroup.qr.scanner.prod ',
        version: '1.1.0',
        buildNumber: '1062',
      )!;
      expect(build.toJson(), {
        'platform': 'android',
        'package_name': 'pakgroup.qr.scanner.prod',
        'build_number': 1062,
        'version_name': '1.1.0',
      });
    });

    test(
        'без номера сборки или пакета — не регистрируем (сервер ответил бы '
        '422)', () {
      MobileBuild? build(String number,
              {String package = 'p', String v = '1'}) =>
          MobileBuild.fromPackage(
            isIos: false,
            packageName: package,
            version: v,
            buildNumber: number,
          );
      expect(build(''), isNull);
      expect(build('0'), isNull);
      expect(build('abc'), isNull);
      expect(build('5', package: ' '), isNull);
      expect(build('5', v: ''), isNull);
    });
  });

  group('когда регистрировать', () {
    const build = 'android|p|1062|1.1.0';
    final at = DateTime.utc(2026, 11, 18, 12);

    test('ещё не регистрировали — сразу', () {
      expect(
        needsInstallationRegistration(null, buildSignature: build, now: at),
        isTrue,
      );
      expect(installationRegistered(null), isFalse);
    });

    test('та же сборка — не чаще раза в 5 минут', () {
      final mark = encodeInstallationMark(build, at);
      expect(installationRegistered(mark), isTrue);
      bool after(Duration d) => needsInstallationRegistration(
            mark,
            buildSignature: build,
            now: at.add(d),
          );
      expect(after(const Duration(minutes: 4)), isFalse);
      expect(after(const Duration(minutes: 5)), isTrue);
    });

    test('обновили приложение — сразу, не дожидаясь интервала', () {
      final mark = encodeInstallationMark('android|p|1061|1.0', at);
      expect(
        needsInstallationRegistration(mark, buildSignature: build, now: at),
        isTrue,
      );
    });

    test('часы перевели назад — регистрируем', () {
      final mark = encodeInstallationMark(build, at);
      expect(
        needsInstallationRegistration(
          mark,
          buildSignature: build,
          now: at.subtract(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });

    test('битая отметка — как отсутствующая', () {
      expect(installationRegistered('{'), isFalse);
      expect(installationRegistered('{"build": "x"}'), isFalse);
      expect(
        needsInstallationRegistration('[]', buildSignature: build, now: at),
        isTrue,
      );
    });

    test('отметка своя у каждого обходчика и сервера', () {
      final a = installationMarkKey('user-a', 'http://a.test:8000');
      expect(a, installationMarkKey('user-a', 'http://a.test:8000/'));
      expect(a, isNot(installationMarkKey('user-b', 'http://a.test:8000')));
      expect(a, isNot(installationMarkKey('user-a', 'http://b.test:8000')));
    });
  });

  group('хранение и заголовок', () {
    late Directory dir;

    setUpAll(() => Hive.registerAdapter(UserAdapter(), override: true));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('installation');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('UUID создаётся один раз и переживает смену аккаунта', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;

      final first = await provider.ensureInstallationId();
      expect(await provider.ensureInstallationId(), first);

      await provider.clearCachedData();
      expect(provider.installationId, first);
    });

    test('заголовок — только после регистрации у вошедшего', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      final id = await provider.ensureInstallationId();
      await provider.userBox.put(
        'auth_user',
        User(username: 'ttt', role: 'walker')..uuid = 'user-a',
      );

      expect(provider.installationHeaderId, isNull);
      expect(API.installationHeaders(), isEmpty);

      // Зарегистрирован другой обходчик — у этого заголовка нет.
      await provider.stringBox.put(
        installationMarkKey('user-b', API.baseUrl),
        encodeInstallationMark('android|p|1|1', DateTime.now()),
      );
      expect(provider.installationHeaderId, isNull);

      await provider.stringBox.put(
        installationMarkKey('user-a', API.baseUrl),
        encodeInstallationMark('android|p|1|1', DateTime.now()),
      );
      expect(provider.installationHeaderId, id);

      API.installationId = () => provider.installationHeaderId;
      addTearDown(() => API.installationId = () => null);
      expect(API.installationHeaders(), {API.installationHeader: id});

      // Вышел — заголовка нет.
      await provider.userBox.delete('auth_user');
      expect(API.installationHeaders(), isEmpty);
    });
  });

  group('фоновый сервис уведомлений', () {
    const url = 'http://127.0.0.1:8000';
    const jwt = 'token-a';

    bool needs({String? saved, String? current}) => pushServiceNeedsRestart(
          savedUrl: url,
          savedJwt: jwt,
          currentUrl: url,
          currentJwt: jwt,
          savedInstallation: saved,
          currentInstallation: current,
        );

    test('установку зарегистрировали после запуска — перезапуск с заголовком',
        () {
      expect(needs(saved: '', current: 'id-1'), isTrue);
      expect(needs(saved: null, current: 'id-1'), isTrue);
    });

    test('та же установка или обе без заголовка — не трогаем', () {
      expect(needs(saved: 'id-1', current: 'id-1'), isFalse);
      expect(needs(saved: null, current: null), isFalse);
      expect(needs(saved: '', current: null), isFalse);
    });

    test('вышли — без заголовка, перезапуск', () {
      expect(needs(saved: 'id-1', current: null), isTrue);
    });

    test('заголовок изолята — только при непустом UUID', () {
      expect(pushInstallationHeaders(''), isEmpty);
      expect(
        pushInstallationHeaders('id-1'),
        {API.installationHeader: 'id-1'},
      );
    });
  });

  group('Рабочие запросы и сборка (бэкенд 811c4dc)', () {
    tearDown(() {
      API.rawInstallationId = () => null;
      API.installedBuild = () => null;
    });

    test('UUID и сборка уходят даже без регистрации', () {
      API.rawInstallationId = () => 'id-raw';
      API.installedBuild = () => 1062;
      expect(API.workHeaders(), {
        API.installationHeader: 'id-raw',
        API.buildHeader: '1062',
      });
    });

    test('без UUID — без заголовков, номер сборки один не шлём', () {
      API.installedBuild = () => 1062;
      expect(API.workHeaders(), isEmpty);
    });

    test('без номера сборки — только UUID', () {
      API.rawInstallationId = () => 'id-raw';
      expect(API.workHeaders(), {API.installationHeader: 'id-raw'});
    });

    const status = MobileSupportStatus(status: 'obsolete');

    test('статус своей сборки читается', () {
      final raw = encodeStoredSupportStatus(status, 'android|p|1062|1.1');
      expect(
        decodeStoredSupportStatus(raw, 'android|p|1062|1.1')?.status,
        'obsolete',
      );
    });

    test('статус прошлой сборки после обновления не показывается', () {
      final raw = encodeStoredSupportStatus(status, 'android|p|1062|1.1');
      expect(decodeStoredSupportStatus(raw, 'android|p|1063|1.2'), isNull);
      expect(decodeStoredSupportStatus(raw, null), isNull);
    });

    test('статус без отпечатка сборки и битая запись — нечего показать', () {
      expect(decodeStoredSupportStatus('{"status":"obsolete"}', 'b'), isNull);
      expect(decodeStoredSupportStatus('{битое', 'b'), isNull);
      expect(decodeStoredSupportStatus(null, 'b'), isNull);
    });
  });
}
