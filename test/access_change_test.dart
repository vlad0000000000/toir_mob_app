import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/access_session.dart';
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

    /// Сервер, у которого доступ сменился после первой страницы полного
    /// прохода: продолжение приходит пустым, с `next_cursor: null` и
    /// `resync_required` — обрыв, неотличимый от конца окна без проверки.
    /// [changes] — сколько раз так случится, дальше окно отдаётся целиком.
    ({SyncPageFetch<String> fetch, List<String?> cursors}) midWindowServer(
        int changes) {
      final cursors = <String?>[];
      var left = changes;
      Future<SyncPage<String>> fetch({
        int limit = 100,
        int offset = 0,
        DateTime? updatedSince,
        DateTime? syncUntil,
        bool cursorMode = false,
        String? cursor,
      }) async {
        cursors.add(cursor);
        if (cursor == null) {
          return SyncPage(
            items: const ['a'],
            syncUntil: since,
            cursorMode: true,
            nextCursor: 'c1',
          );
        }
        if (left > 0) {
          left--;
          return const SyncPage(
            items: [],
            cursorMode: true,
            resyncRequired: true,
          );
        }
        return SyncPage(items: const ['b'], syncUntil: since, cursorMode: true);
      }

      return (fetch: fetch, cursors: cursors);
    }

    test('сменился посреди полного прохода — окно заново, не половина',
        () async {
      final server = midWindowServer(1);

      final window = await loadSyncWindow<String>(server.fetch,
          since: since, fullPass: true, guard: noGuard);

      expect(window.items, ['a', 'b']);
      expect(server.cursors, [null, 'c1', null, 'c1']);
    });

    test('сменился и при повторе — ошибка, записывать нечего', () async {
      final server = midWindowServer(2);

      await expectLater(
        loadSyncWindow<String>(server.fetch,
            since: since, fullPass: true, guard: noGuard),
        throwsA(isA<SyncAccessChanged>()),
      );
    });
  });

  group('ответ профиля доступа', () {
    // Профиль, запрошенный старой сессией, не должен лечь поверх новой:
    // выход, вход другим пользователем или блокировка этой же сессии.
    bool live({
      String? currentToken = 't1',
      String? blockedToken,
      int requestSession = 1,
      int currentSession = 1,
    }) =>
        isLiveAccessSession(
          requestToken: 't1',
          currentToken: currentToken,
          blockedToken: blockedToken,
          requestSession: requestSession,
          currentSession: currentSession,
        );

    test('та же сессия — применяем', () {
      expect(live(), isTrue);
    });

    test('сессия сменилась или вышли — выбрасываем', () {
      expect(live(currentToken: 't2'), isFalse);
      expect(live(currentToken: null), isFalse);
    });

    test('повторный вход с тем же токеном — запрос прошлой сессии выбрасываем',
        () {
      // Токен нового входа совпал с прежним (время в нём — до секунды), но
      // между запросом и ответом был вход: номер сессии сдвинулся.
      expect(live(requestSession: 1, currentSession: 3), isFalse);
    });

    test('два запроса одной сессии: запоздалый старый не ложится на новый', () {
      final order = AccessResponseOrder();
      final v1 = order.begin();
      final v2 = order.begin();

      // Ответ на второй запрос пришёл первым — записан.
      expect(order.tryApply(v2), isTrue);
      // Ответ на первый пришёл позже — старше записанного, выбрасываем.
      expect(order.tryApply(v1), isFalse);
    });

    test('ответы по порядку — записываются оба', () {
      final order = AccessResponseOrder();
      final v1 = order.begin();
      final v2 = order.begin();

      expect(order.tryApply(v1), isTrue);
      expect(order.tryApply(v2), isTrue);
    });

    test('эту сессию уже заблокировали — выбрасываем', () {
      expect(live(blockedToken: 't1'), isFalse);
    });

    test('поздний 403 прошлой сессии после входа с тем же токеном — мимо', () {
      // Вход сбросил отметку «блокировку уже обработали» и сдвинул номер
      // сессии. Отказ по запросу, ушедшему до выхода, несёт прежний номер —
      // ни блокировку не запишет, ни нового входа не выкинет.
      expect(live(blockedToken: null, requestSession: 2, currentSession: 4),
          isFalse);
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

  group('пометка «сессия истекла»', () {
    test('401 на запрос прошлой сессии после нового входа — не поднимает', () {
      var session = 1;
      final flag = SessionGuardedFlag(ValueNotifier(false), () => session);
      final sentBefore = session;
      session = 3; // выход и новый вход, пока осмотр был в пути

      flag.set(true, requestSession: sentBefore);

      expect(flag.flag.value, isFalse);
    });

    test('401 на запрос текущей сессии — поднимает, успех — снимает', () {
      var session = 2;
      final flag = SessionGuardedFlag(ValueNotifier(false), () => session);

      flag.set(true, requestSession: session);
      expect(flag.flag.value, isTrue);

      flag.set(false, requestSession: session);
      expect(flag.flag.value, isFalse);
    });
  });
}
