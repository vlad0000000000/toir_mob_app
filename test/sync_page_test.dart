import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/typical_problem.dart';

/// Разбор страницы инкрементального справочника.
///
/// Форма ответа определяется по самому ответу, а не по тому, что попросили:
/// сервер, который инкрементальный режим ещё не умеет, на незнакомый параметр
/// отдаёт обычный список. Принять такой список за «список изменений» нельзя —
/// клиент решил бы, что всё остальное удалено.
TypicalProblem _problem(Map<String, dynamic> json) => TypicalProblem(
      id: json['id'] as int,
      title: json['title'] as String,
      uuid: json['uuid'] as String,
      defaultPriority: null,
      equipmentUUID: '',
    );

void main() {
  group('parseSyncPage', () {
    test('обычный список: записи есть, границы окна нет', () {
      final page = parseSyncPage(
        [
          {'id': 1, 'title': 'Течь', 'uuid': 'u-1'},
          {'id': 2, 'title': 'Шум', 'uuid': 'u-2'},
        ],
        _problem,
        'Failed',
      );

      expect(page.items.map((e) => e.uuid), ['u-1', 'u-2']);
      expect(page.deletedUuids, isEmpty);
      // Без `sync_until` вызывающий остаётся на полных проходах.
      expect(page.syncUntil, isNull);
    });

    test('инкрементальный ответ: изменения, удаления и граница окна', () {
      final page = parseSyncPage(
        {
          'items': [
            {'id': 3, 'title': 'Вибрация', 'uuid': 'u-3'}
          ],
          'deleted': [
            {'uuid': 'u-9', 'deleted_at': '2026-10-17T10:00:00Z'}
          ],
          'sync_until': '2026-10-17T10:05:00Z',
        },
        _problem,
        'Failed',
      );

      expect(page.items.single.uuid, 'u-3');
      expect(page.deletedUuids, ['u-9']);
      expect(page.syncUntil, DateTime.utc(2026, 10, 17, 10, 5));
    });

    test('пустое окно — ни изменений, ни удалений, но граница есть', () {
      final page = parseSyncPage(
        {'items': [], 'deleted': [], 'sync_until': '2026-10-17T10:05:00Z'},
        _problem,
        'Failed',
      );

      expect(page.items, isEmpty);
      expect(page.deletedUuids, isEmpty);
      expect(page.syncUntil, isNotNull);
    });

    test('запись удаления без uuid пропускается молча', () {
      final page = parseSyncPage(
        {
          'items': [],
          'deleted': [
            {'deleted_at': '2026-10-17T10:00:00Z'},
            'мусор',
            {'uuid': 'u-7'},
          ],
          'sync_until': '2026-10-17T10:05:00Z',
        },
        _problem,
        'Failed',
      );

      expect(page.deletedUuids, ['u-7']);
    });

    test('курсорный ответ: next_cursor есть — режим курсора', () {
      final page = parseSyncPage(
        {
          'items': [],
          'deleted': [],
          'sync_until': '2026-10-17T10:05:00Z',
          'next_cursor': 'abc.def',
        },
        _problem,
        'Failed',
      );

      expect(page.cursorMode, isTrue);
      expect(page.nextCursor, 'abc.def');
    });

    test('next_cursor=null — тоже курсорный режим, окно выбрано целиком', () {
      final page = parseSyncPage(
        {
          'items': [],
          'deleted': [],
          'sync_until': '2026-10-17T10:05:00Z',
          'next_cursor': null,
        },
        _problem,
        'Failed',
      );

      expect(page.cursorMode, isTrue);
      expect(page.nextCursor, isNull);
    });

    test('ответ без next_cursor — сервер курсор не умеет', () {
      final page = parseSyncPage(
        {'items': [], 'deleted': [], 'sync_until': '2026-10-17T10:05:00Z'},
        _problem,
        'Failed',
      );

      expect(page.cursorMode, isFalse);
    });

    test('ответ неизвестной формы — ошибка, а не пустая страница', () {
      // Пустая страница здесь опаснее исключения: вызывающий счёл бы, что
      // справочник не менялся, и сдвинул бы курсор мимо реальных изменений.
      expect(
        () => parseSyncPage('не json-объект', _problem, 'Failed'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('syncPageParams', () {
    final since = DateTime.utc(2026, 10, 19);

    test('первая страница курсором — окно, без skip', () {
      final params = syncPageParams(
        limit: 100,
        offset: 0,
        updatedSince: since,
        cursorMode: true,
      );

      expect(params['pagination'], 'cursor');
      expect(params['updated_since'], since.toIso8601String());
      expect(params.containsKey('skip'), isFalse);
    });

    test('продолжение — только курсор: окно зашито в него сервером', () {
      final params = syncPageParams(
        limit: 100,
        offset: 0,
        updatedSince: since,
        cursorMode: true,
        cursor: 'abc.def',
      );

      expect(params,
          {'limit': '100', 'pagination': 'cursor', 'cursor': 'abc.def'});
    });

    test('прежний режим — skip и окно', () {
      final params =
          syncPageParams(limit: 100, offset: 200, updatedSince: since);

      expect(params['skip'], '200');
      expect(params.containsKey('pagination'), isFalse);
    });
  });
}
