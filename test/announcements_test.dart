import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/mobile_installation.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/announcement.dart';
import 'package:qr_scan_industry/src/model/user.dart';
import 'package:qr_scan_industry/src/notifications/announcements_service.dart';
import 'package:qr_scan_industry/src/notifications/push/notifications_task_handler.dart';

import 'support/test_data_provider.dart';

/// Сервисные объявления (бэкенд `81f644c`): разбор, порядок, срок показа,
/// таймер перечитки, локальный пуш важного и очередь «прочитано» без связи.
void main() {
  final now = DateTime.utc(2026, 11, 18, 12);

  Announcement a(
    String uuid, {
    String importance = 'normal',
    DateTime? readAt,
    DateTime? from,
    DateTime? until,
  }) =>
      Announcement(
        uuid: uuid,
        title: 'Заголовок $uuid',
        body: 'Текст',
        importance: importance,
        visibleFrom: from,
        visibleUntil: until,
        readAt: readAt,
      );

  group('разбор ответа', () {
    test('объявление о новой версии', () {
      final parsed = Announcement.fromJson({
        'announcement_uuid': 'a-1',
        'title': 'Обновление',
        'body': 'Исправлены ошибки',
        'importance': 'important',
        'audience': 'all',
        'kind': 'release',
        'visible_from': '2026-11-18T09:00:00Z',
        'visible_until': '2026-11-25T09:00:00Z',
        'target_versions': [],
        'target_release': {'release_uuid': 'r-2', 'version_name': '1.1.0'},
        'update_url':
            'https://www.rustore.ru/catalog/app/pakgroup.qr.scanner.prod',
        'read_at': null,
      })!;
      expect(parsed.isRelease, isTrue);
      expect(parsed.isImportant, isTrue);
      expect(parsed.isRead, isFalse);
      expect(parsed.targetVersion, '1.1.0');
      expect(parsed.safeUpdateUri?.host, 'www.rustore.ru');
      expect(parsed.visibleUntil, DateTime.utc(2026, 11, 25, 9));
    });

    test('сохранённое читается обратно', () {
      final original = Announcement.fromJson({
        'announcement_uuid': 'a-1',
        'title': 'Т',
        'body': 'Б',
        'kind': 'release',
        'target_release': {'version_name': '1.1.0'},
        'read_at': '2026-11-18T10:00:00Z',
      })!;
      final restored =
          Announcement.fromJson(jsonDecode(jsonEncode(original.toJson())))!;
      expect(restored.kind, 'release');
      expect(restored.targetVersion, '1.1.0');
      expect(restored.readAt, original.readAt);
    });

    test('битые записи пропускаются', () {
      final items = parseAnnouncements([
        {'announcement_uuid': 'ok', 'title': 'Т'},
        {'title': 'без uuid'},
        {'announcement_uuid': 'без заголовка'},
        'строка',
      ]);
      expect(items.map((e) => e.uuid), ['ok']);
      expect(parseAnnouncements(null), isEmpty);
    });

    test('ссылка — только https', () {
      Announcement withUrl(String url) =>
          Announcement(uuid: 'u', title: 'т', body: '', updateUrl: url);
      expect(withUrl('http://x.ru/a').safeUpdateUri, isNull);
      expect(withUrl('intent://a#Intent;end').safeUpdateUri, isNull);
      expect(withUrl('https://x.ru/a').safeUpdateUri, isNotNull);
    });

    test('отметка прочтения не перезаписывает прежнюю', () {
      final read =
          a('1', readAt: now).markedRead(now.add(const Duration(hours: 1)));
      expect(read.readAt, now);
      expect(a('2').markedRead(now).readAt, now);
    });
  });

  group('порядок и срок показа', () {
    test('важные первыми, внутри — непрочитанные, затем свежие', () {
      final sorted = sortAnnouncements([
        a('normal-read', readAt: now),
        a('normal-new-old', from: now.subtract(const Duration(days: 2))),
        a('important-read', importance: 'important', readAt: now),
        a('normal-new-fresh', from: now),
        a('important-new', importance: 'important'),
      ]);
      expect(sorted.map((e) => e.uuid), [
        'important-new',
        'important-read',
        'normal-new-fresh',
        'normal-new-old',
        'normal-read',
      ]);
    });

    test('истёкшие и ещё не начавшиеся не показываем', () {
      final shown = visibleAnnouncements([
        a('now',
            from: now.subtract(const Duration(hours: 1)),
            until: now.add(const Duration(hours: 1))),
        a('expired', until: now),
        a('future', from: now.add(const Duration(minutes: 1))),
        a('open'),
      ], now);
      expect(shown.map((e) => e.uuid), ['now', 'open']);
    });

    test('таймер перечитки — от 1 секунды до суток', () {
      expect(announcementRefreshDelay(null, now), isNull);
      expect(
        announcementRefreshDelay(now.subtract(const Duration(minutes: 1)), now),
        const Duration(seconds: 1),
      );
      expect(
        announcementRefreshDelay(now.add(const Duration(hours: 2)), now),
        const Duration(hours: 2),
      );
      expect(
        announcementRefreshDelay(now.add(const Duration(days: 3)), now),
        const Duration(days: 1),
      );
    });
  });

  test('локальный пуш — только важные непрочитанные и по одному разу', () {
    final items = [
      {'announcement_uuid': 'imp-new', 'title': 'т', 'importance': 'important'},
      {
        'announcement_uuid': 'imp-read',
        'title': 'т',
        'importance': 'important',
        'read_at': '2026-11-18T10:00:00Z',
      },
      {'announcement_uuid': 'normal', 'title': 'т'},
      {
        'announcement_uuid': 'imp-pushed',
        'title': 'т',
        'importance': 'important'
      },
    ];
    expect(
      announcementsToPush(items, {'imp-pushed'}).map((e) => e.uuid),
      ['imp-new'],
    );
  });

  test('кэш и очередь — свои у каждого обходчика и сервера', () {
    expect(
      announcementsCacheKey('u', 'http://a.test'),
      isNot(announcementsCacheKey('u', 'http://b.test')),
    );
    expect(
      announcementReadsKey('u', 'http://a.test'),
      isNot(announcementReadsKey('v', 'http://a.test')),
    );
    expect(
      announcementsCacheKey('u', 'http://a.test'),
      isNot(announcementReadsKey('u', 'http://a.test')),
    );
  });

  group('без связи', () {
    late Directory dir;
    final service = AnnouncementsService.instance;

    setUpAll(() => Hive.registerAdapter(UserAdapter(), override: true));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('announcements');
      Hive.init(dir.path);
      API.simulateOffline = true;
    });

    tearDown(() async {
      service.onLogout();
      API.simulateOffline = false;
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Future<void> signIn({bool registered = true}) async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      await provider.ensureInstallationId();
      await provider.userBox.put(
        'auth_user',
        User(username: 'ttt', role: 'walker')..uuid = 'user-a',
      );
      if (registered) {
        await provider.stringBox.put(
          installationMarkKey('user-a', API.baseUrl),
          encodeInstallationMark('android|p|1|1', DateTime.now()),
        );
      }
      await provider.stringBox.put(
        announcementsCacheKey('user-a', API.baseUrl),
        jsonEncode([
          a('normal').toJson(),
          a('important', importance: 'important').toJson(),
          a('old', until: DateTime.now().subtract(const Duration(days: 1)))
              .toJson(),
        ]),
      );
    }

    test('показываем сохранённое, кроме истёкшего', () async {
      await signIn();
      await service.bootstrap();

      expect(service.current.value.map((e) => e.uuid), ['important', 'normal']);
      expect(service.unreadCount.value, 2);
    });

    test('без регистрации установки — блока нет: объявления в ленте 1.0',
        () async {
      await signIn(registered: false);
      await service.bootstrap();

      expect(service.current.value, isEmpty);
      expect(service.unreadCount.value, 0);
    });

    test('«прочитано» — сразу на экране, в очереди на диске, переживает выход',
        () async {
      await signIn();
      await service.bootstrap();

      await service.markRead('important');
      expect(service.unreadCount.value, 1);
      expect(
        service.current.value.firstWhere((e) => e.uuid == 'important').isRead,
        isTrue,
      );
      final box = GlobalState.dataProvider.stringBox;
      expect(
        jsonDecode(box.get(announcementReadsKey('user-a', API.baseUrl))!),
        ['important'],
      );

      service.onLogout();
      expect(service.current.value, isEmpty);
      expect(service.unreadCount.value, 0);

      await service.bootstrap();
      expect(service.unreadCount.value, 1);
      expect(
        service.current.value.firstWhere((e) => e.uuid == 'important').isRead,
        isTrue,
      );
    });
  });

  group('отладочное объявление о новой версии', () {
    test('по умолчанию выключено — в обычной сборке его нет', () {
      expect(previewReleaseAnnouncementEnabled, isFalse);
    });

    test('как настоящее: «Обновление приложения», версия и RuStore', () {
      final shownAt = DateTime.utc(2026, 11, 23, 9);
      final preview = previewReleaseAnnouncement(shownAt);
      expect(preview.isRelease, isTrue);
      expect(preview.isRead, isFalse);
      expect(preview.targetVersion, '1.1.0');
      expect(preview.safeUpdateUri?.host, 'www.rustore.ru');
      expect(
        visibleAnnouncements([preview], shownAt.add(const Duration(days: 1))),
        [preview],
      );
      expect(
        previewReleaseAnnouncement(shownAt, readAt: shownAt).isRead,
        isTrue,
      );
    });
  });

  group('границы показа и прочтения на телефоне (ревью 25.11)', () {
    final now = DateTime.utc(2026, 11, 25, 9);
    Announcement at(String uuid,
            {DateTime? from, DateTime? until, DateTime? read}) =>
        Announcement(
          uuid: uuid,
          title: uuid,
          body: '',
          visibleFrom: from,
          visibleUntil: until,
          readAt: read,
        );

    test('ближайшая будущая граница — начало или конец показа', () {
      final items = [
        at('a',
            from: now.subtract(const Duration(days: 1)),
            until: now.add(const Duration(hours: 5))),
        at('b', from: now.add(const Duration(hours: 2))),
      ];
      expect(nextVisibilityBoundary(items, now),
          now.add(const Duration(hours: 2)));
    });

    test('прошедшие границы не считаются, без границ — null', () {
      final items = [
        at('a', until: now.subtract(const Duration(minutes: 1))),
        at('b'),
      ];
      expect(nextVisibilityBoundary(items, now), isNull);
    });

    test('запоздалый ответ не снимает прочтение, сделанное на телефоне', () {
      final merged = withLocalReads(
        [at('a'), at('b')],
        {'a': now},
      );
      expect(merged.first.isRead, isTrue);
      expect(merged.first.readAt, now);
      expect(merged.last.isRead, isFalse);
    });

    test(
        'локальные прочтения держатся, только пока сервер отдаёт непрочитанным',
        () {
      final reads = {'unread': now, 'confirmed': now, 'gone': now};
      pruneLocalReads(reads, [
        at('unread'),
        at('confirmed', read: now),
      ]);
      expect(reads.keys, ['unread']);
    });

    test('прочитанное сервером остаётся как есть', () {
      final serverRead = now.subtract(const Duration(hours: 1));
      final merged = withLocalReads([at('a', read: serverRead)], {'a': now});
      expect(merged.single.readAt, serverRead);
    });
  });

  test('фоновая проверка: повтор только после временного сбоя', () {
    for (final code in [500, 502, 503, 408, 429]) {
      expect(isTransientAnnouncementStatus(code), isTrue, reason: '$code');
    }
    for (final code in [200, 401, 403, 404]) {
      expect(isTransientAnnouncementStatus(code), isFalse, reason: '$code');
    }
    expect(announcementRetryDelay, const Duration(minutes: 1));
  });
}
