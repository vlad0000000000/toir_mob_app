import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/sync_window.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';

/// Смена доступа на лету: инкрементальный курсор, выданный до неё, сервер
/// не принимает (`resync_required`), а ремонт, ушедший из области, карточка
/// показывает как недоступный, а не как «не загрузился».
void main() {
  /// Ответ инкрементального списка, чей курсор старше смены доступа, — как
  /// его собирает `resync_required_response` на сервере.
  const resyncBody = {
    'items': <dynamic>[],
    'deleted': <dynamic>[],
    'sync_until': null,
    'resync_required': true,
    'resync_reason': 'access_changed',
  };

  group('разбор resync_required', () {
    test('страница справочника', () {
      final page = parseSyncPage<String>(
          resyncBody, (json) => json['uuid'] as String, 'Справочник');

      expect(page.resyncRequired, isTrue);
      expect(page.syncUntil, isNull);
      expect(page.items, isEmpty);
    });

    test('обычный ответ — не требует полного прохода', () {
      final page = parseSyncPage<String>(
        {
          'items': <dynamic>[],
          'deleted': <dynamic>[],
          'sync_until': '2026-10-22T10:00:00Z',
          'resync_required': false,
        },
        (json) => json['uuid'] as String,
        'Справочник',
      );

      expect(page.resyncRequired, isFalse);
      expect(page.syncUntil, isNotNull);
    });

    test('признак — только явное true', () {
      expect(parseResyncRequired(resyncBody), isTrue);
      expect(parseResyncRequired({'resync_required': 'true'}), isFalse);
      expect(parseResyncRequired(<dynamic>[]), isFalse);
    });
  });

  group('окно справочника после смены доступа', () {
    final since = DateTime.utc(2026, 10, 19);
    void noGuard(int _) {}

    test('дальше не качаем — вызывающий перейдёт на полный проход', () async {
      var calls = 0;
      Future<SyncPage<String>> fetch({
        int limit = 100,
        int offset = 0,
        DateTime? updatedSince,
        DateTime? syncUntil,
        bool cursorMode = false,
        String? cursor,
      }) async {
        calls++;
        // Даже если бы сервер прислал next_cursor, идти по нему нельзя:
        // окно посчитано по старой области.
        return const SyncPage(
          items: ['stale'],
          cursorMode: true,
          nextCursor: 'next',
          resyncRequired: true,
        );
      }

      final window = await loadSyncWindow<String>(fetch,
          since: since, fullPass: false, guard: noGuard);

      expect(window.syncUntil, isNull);
      expect(window.items, isEmpty);
      expect(calls, 1);
    });
  });

  group('ремонт вне области обходчика', () {
    test('нет права на ремонты', () {
      expect(
        isRepairOutOfScope(AccessDeniedException(
            403, AccessDeniedException.permissionDenied, 'Недостаточно прав')),
        isTrue,
      );
    });

    test('передан другому — «No access to this repair»', () {
      expect(
        isRepairOutOfScope(
            ServerFailureException(403, 'No access to this repair')),
        isTrue,
      );
    });

    test('не найден — 404 отдаётся и на объект вне области', () {
      expect(
          isRepairOutOfScope(ServerFailureException(404, 'Объект не найден.')),
          isTrue);
    });

    test('нет связи и сбой сервера — не «нет доступа»', () {
      expect(isRepairOutOfScope(ServerFailureException(502, 'Bad gateway')),
          isFalse);
      expect(isRepairOutOfScope(Exception('Connection refused')), isFalse);
    });
  });
}
