import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/cache_commit_queue.dart';

/// Очередь фиксации — то, на чём держится «чужой проход не пишет в кэш
/// нового аккаунта».
///
/// Кэш здесь — обычный список: важен не Hive, а порядок. Запись — несколько
/// шагов с `await` между ними, ровно как очистка бокса, заливка и курсор.
void main() {
  group('CacheCommitQueue', () {
    test('фиксация текущего поколения выполняется', () async {
      final queue = CacheCommitQueue();
      final cache = <String>[];

      final committed = await queue.commit(queue.generation, () async {
        cache.add('A');
      });

      expect(committed, isTrue);
      expect(cache, ['A']);
    });

    test('после смены аккаунта запись прошлого прохода отбрасывается',
        () async {
      final queue = CacheCommitQueue();
      final cache = <String>[];
      final generationA = queue.generation;

      queue.invalidate();
      final committed = await queue.commit(generationA, () async {
        cache.add('A');
      });

      expect(committed, isFalse);
      expect(cache, isEmpty);
    });

    test('запись A, начавшаяся до смены аккаунта, не ложится поверх данных B',
        () async {
      // Тот самый сценарий: проход A сверил поколение и начал писать, на
      // середине записи обходчик сменился, очистка и проход B пошли следом.
      final queue = CacheCommitQueue();
      final cache = <String>[];
      final generationA = queue.generation;
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();

      final commitA = queue.commit(generationA, () async {
        cache
          ..clear()
          ..add('A: данные');
        writeStarted.complete();
        // Посреди записи — как между `putAll` и курсором.
        await releaseWrite.future;
        cache.add('A: курсор');
      });
      await writeStarted.future;

      // Смена аккаунта: поколение растёт сразу, очистка встаёт в очередь.
      queue.invalidate();
      final clear = queue.run(() async => cache.clear());
      final generationB = queue.generation;
      final commitB = queue.commit(generationB, () async {
        cache
          ..clear()
          ..add('B: данные')
          ..add('B: курсор');
      });

      releaseWrite.complete();
      expect(await commitA, isTrue);
      await clear;
      expect(await commitB, isTrue);

      expect(cache, ['B: данные', 'B: курсор']);
    });

    test('задержанный ответ A после записи B ничего не меняет', () async {
      final queue = CacheCommitQueue();
      final cache = <String>[];
      final generationA = queue.generation;

      queue.invalidate();
      await queue.run(() async => cache.clear());
      await queue.commit(queue.generation, () async => cache.add('B'));
      final committed =
          await queue.commit(generationA, () async => cache.add('A'));

      expect(committed, isFalse);
      expect(cache, ['B']);
    });

    test('ошибка внутри фиксации не останавливает очередь', () async {
      final queue = CacheCommitQueue();
      final cache = <String>[];

      final failed = queue.commit(queue.generation, () async {
        throw StateError('диск');
      });
      await expectLater(failed, throwsStateError);

      final committed =
          await queue.commit(queue.generation, () async => cache.add('после'));

      expect(committed, isTrue);
      expect(cache, ['после']);
    });

    test('фиксации выполняются строго по одной, в порядке постановки',
        () async {
      final queue = CacheCommitQueue();
      final log = <String>[];

      Future<bool> step(String name) =>
          queue.commit(queue.generation, () async {
            log.add('$name: начало');
            await Future<void>.delayed(Duration.zero);
            log.add('$name: конец');
          });

      await Future.wait([step('1'), step('2')]);

      expect(log, ['1: начало', '1: конец', '2: начало', '2: конец']);
    });
  });
}
