import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/sync_window.dart';
import 'package:qr_scan_industry/src/http/api.dart';

/// Выборка окна справочника: курсором, с откатом на `skip` для старого
/// сервера. Сервер здесь — функция, отвечающая заранее заданными страницами.
void main() {
  final since = DateTime.utc(2026, 10, 19);
  final until = DateTime.utc(2026, 10, 19, 12);
  void noGuard(int _) {}

  /// Запросы, которые сделал клиент, — чтобы проверить их форму.
  late List<({int offset, String? cursor, bool cursorMode})> calls;

  SyncPageFetch<String> server(
    SyncPage<String> Function(int offset, String? cursor) respond,
  ) {
    return ({
      int limit = 100,
      int offset = 0,
      DateTime? updatedSince,
      DateTime? syncUntil,
      bool cursorMode = false,
      String? cursor,
    }) async {
      calls.add((offset: offset, cursor: cursor, cursorMode: cursorMode));
      return respond(offset, cursor);
    };
  }

  setUp(() => calls = []);

  test('курсор: конец — только next_cursor=null, пустые items не конец',
      () async {
    final fetch = server((_, cursor) => switch (cursor) {
          null => SyncPage(
              items: ['a'],
              syncUntil: until,
              cursorMode: true,
              nextCursor: 'c1',
            ),
          // Изменения кончились, удаления ещё идут.
          'c1' => SyncPage(
              items: const [],
              deletedUuids: ['x'],
              syncUntil: until,
              cursorMode: true,
              nextCursor: 'c2',
            ),
          _ => SyncPage(
              items: const [],
              deletedUuids: ['y'],
              syncUntil: until,
              cursorMode: true,
            ),
        });

    final window = await loadSyncWindow(fetch,
        since: since, fullPass: false, guard: noGuard);

    expect(window.items, ['a']);
    expect(window.deleted, {'x', 'y'});
    expect(window.syncUntil, until);
    expect(calls.map((c) => c.cursor), [null, 'c1', 'c2']);
    // В курсорном режиме skip не шлём вовсе.
    expect(calls.every((c) => c.cursorMode && c.offset == 0), isTrue);
  });

  test('сервер курсор не умеет — прежний проход по skip', () async {
    final fetch = server((offset, _) => SyncPage(
          items: offset == 0 ? List.filled(100, 'p0') : ['last'],
          syncUntil: until,
        ));

    final window = await loadSyncWindow(fetch,
        since: since, fullPass: false, guard: noGuard);

    expect(window.items.length, 101);
    expect(calls.map((c) => c.offset), [0, 100]);
    expect(calls.last.cursorMode, isFalse);
  });

  test('инкрементальный проход: сервер не понял окна — дальше не качаем',
      () async {
    final fetch = server(
        (_, __) => SyncPage(items: List.filled(100, 'p'), syncUntil: null));

    final window = await loadSyncWindow(fetch,
        since: since, fullPass: false, guard: noGuard);

    expect(window.syncUntil, isNull);
    expect(calls, hasLength(1));
  });

  test('отклонённый курсор — окно заново, один раз', () async {
    var rejected = false;
    final fetch = server((_, cursor) {
      if (cursor == 'stale' && !rejected) {
        rejected = true;
        throw const SyncCursorRejected();
      }
      return switch (cursor) {
        null => SyncPage(
            items: ['a'],
            syncUntil: until,
            cursorMode: true,
            nextCursor: 'stale',
          ),
        _ => SyncPage(items: ['b'], syncUntil: until, cursorMode: true),
      };
    });

    final window = await loadSyncWindow(fetch,
        since: since, fullPass: false, guard: noGuard);

    expect(window.items, ['a', 'b']);
    expect(calls.map((c) => c.cursor), [null, 'stale', null, 'stale']);
  });

  test('ошибка посреди окна — ничего не возвращается', () async {
    final fetch = server((_, cursor) => cursor == null
        ? SyncPage(
            items: ['a'],
            syncUntil: until,
            cursorMode: true,
            nextCursor: 'c1',
          )
        : throw Exception('сеть'));

    await expectLater(
      loadSyncWindow(fetch, since: since, fullPass: true, guard: noGuard),
      throwsException,
    );
  });

  test('предохранитель обрывает выборку ошибкой', () async {
    final fetch = server((_, __) => SyncPage(
          items: ['a'],
          syncUntil: until,
          cursorMode: true,
          nextCursor: 'loop',
        ));

    await expectLater(
      loadSyncWindow(
        fetch,
        since: since,
        fullPass: true,
        guard: (loaded) {
          if (loaded >= 5) throw StateError('guard');
        },
      ),
      throwsStateError,
    );
  });
}
