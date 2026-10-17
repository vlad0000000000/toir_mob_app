import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/generation_pass.dart';

/// «Один проход на поколение кэша» — правило, по которому `mainSync`,
/// синхронизация ЗИП и ручная синхронизация присоединяются к идущему проходу.
///
/// Проход здесь — `Completer`: важно не что он делает, а когда закончится.
void main() {
  group('GenerationPass', () {
    test('повторный запрос того же поколения присоединяется к идущему',
        () async {
      final pass = GenerationPass<String>();
      final work = Completer<String>();
      var started = 0;
      Future<String> start() {
        started++;
        return work.future;
      }

      final first = pass.run(0, start);
      final second = pass.run(0, start);
      work.complete('A');

      expect(await first, 'A');
      expect(await second, 'A');
      expect(started, 1);
    });

    test('после окончания следующий запрос запускает новый проход', () async {
      final pass = GenerationPass<int>();
      var started = 0;
      Future<int> start() async => ++started;

      expect(await pass.run(0, start), 1);
      expect(await pass.run(0, start), 2);
      expect(pass.isRunningFor(0), isFalse);
    });

    test('к проходу прошлого аккаунта не присоединяемся', () async {
      final pass = GenerationPass<String>();
      final workA = Completer<String>();

      final a = pass.run(0, () => workA.future);
      final b = pass.run(1, () async => 'B');

      expect(await b, 'B');
      workA.complete('A');
      expect(await a, 'A');
    });

    test(
        'смена аккаунта во время ручной синхронизации: индикатор B не зависит '
        'от прохода A', () async {
      // Сценарий из ревью: синхронизация A идёт, обходчик выходит, входит Б.
      final indicator = <bool>[];
      var running = false;
      final pass = GenerationPass<String>(onRunningChanged: (value) {
        running = value;
        indicator.add(value);
      });
      final workA = Completer<String>();
      final workB = Completer<String>();

      final a = pass.run(0, () => workA.future);
      expect(running, isTrue);

      // Вход Б: `clearCachedData` забывает проход и гасит индикатор.
      pass.forget();
      running = false;
      expect(pass.isRunningFor(0), isFalse);

      // Кнопка Б доступна и запускает свой проход, а не ждёт A.
      final b = pass.run(1, () => workB.future);
      expect(running, isTrue);

      // Поздний конец A индикатор Б не трогает.
      workA.complete('A');
      await a;
      expect(running, isTrue);

      workB.complete('B');
      expect(await b, 'B');
      expect(running, isFalse);
      expect(indicator, [true, true, false]);
    });

    test('окончание прохода, сменённого другим, не сообщается', () async {
      final changes = <bool>[];
      final pass = GenerationPass<int>(onRunningChanged: changes.add);
      final workA = Completer<int>();

      final a = pass.run(0, () => workA.future);
      final b = pass.run(1, () async => 2);
      expect(await b, 2);
      workA.complete(1);
      await a;

      // true (A), true (B), false (конец B); конца A нет — его сменил B.
      expect(changes, [true, true, false]);
    });

    test('ошибка прохода снимает его и доходит до всех ждущих', () async {
      final pass = GenerationPass<int>();
      final work = Completer<int>();

      final first = pass.run(0, () => work.future);
      final second = pass.run(0, () => work.future);
      work.completeError(StateError('сеть'));

      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(pass.isRunningFor(0), isFalse);
    });
  });
}
