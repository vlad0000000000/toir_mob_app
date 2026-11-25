import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/ppr_waiting.dart';
import 'package:qr_scan_industry/src/model/ppr.dart';
import 'package:qr_scan_industry/src/notifications/push/notifications_task_handler.dart';

import 'support/test_data_provider.dart';

/// Задачи ППР, ждущие оборудование «В работе» (бэкенд `6296b61`). Обходчику —
/// только задачи его области (решение 18.11): их отбирает сервер в ответе ППР
/// (подтверждено к `811c4dc`), отдельной проверки каждой задачи нет.
void main() {
  Map<String, dynamic> pprTask({
    bool active = true,
    bool waiting = true,
    Object? periodic = const {
      'uuid': 'pt-1',
      'title': 'Смазка подшипников',
      'equipment_name': 'Насос Н-1',
    },
    String? state = 'in_repair',
  }) =>
      {
        'active_membership': active,
        'waiting_for_equipment': waiting,
        'periodic_task': periodic,
        'equipment_state': state,
        'inspection': null,
      };

  group('разбор ответа ППР', () {
    test('ждущая задача — название, оборудование, состояние', () {
      final task = PprWaitingTask.fromPprTask(pprTask())!;
      expect(task.periodicTaskUuid, 'pt-1');
      expect(task.title, 'Смазка подшипников');
      expect(task.equipmentName, 'Насос Н-1');
      expect(task.equipmentState, 'in_repair');
    });

    test('не ждёт, вышла из ППР или без задачи — не ждущая', () {
      expect(PprWaitingTask.fromPprTask(pprTask(waiting: false)), isNull);
      expect(PprWaitingTask.fromPprTask(pprTask(active: false)), isNull);
      expect(PprWaitingTask.fromPprTask(pprTask(periodic: null)), isNull);
      expect(PprWaitingTask.fromPprTask('строка'), isNull);
    });

    test('без названия и оборудования — запасные подписи', () {
      final task = PprWaitingTask.fromPprTask(pprTask(
        periodic: const {'uuid': 'pt-2', 'title': ''},
        state: null,
      ))!;
      expect(task.title, 'Задача ППР');
      expect(task.equipmentName, isNull);
      expect(task.equipmentState, isNull);
    });
  });

  group('кэш ППР', () {
    test('ждущие задачи переживают сохранение', () {
      const ppr = Ppr(
        uuid: 'p-1',
        title: 'Осенний',
        status: Ppr.statusInProgress,
        periodicTaskUuids: {'pt-1'},
        waitingTasks: [
          PprWaitingTask(
            periodicTaskUuid: 'pt-1',
            title: 'Смазка',
            equipmentName: 'Насос',
            equipmentState: 'in_repair',
          ),
        ],
      );
      final restored = Ppr.fromJson(jsonDecode(jsonEncode(ppr.toJson())));
      expect(restored.waitingTasks.single.periodicTaskUuid, 'pt-1');
      expect(restored.waitingTasks.single.equipmentState, 'in_repair');
    });

    test('кэш прошлой версии — без ждущих', () {
      final restored = Ppr.fromJson({
        'uuid': 'p-1',
        'status': Ppr.statusInProgress,
        'periodic_task_uuids': ['pt-1'],
      });
      expect(restored.waitingTasks, isEmpty);
    });
  });

  group('область обходчика', () {
    Ppr ppr({String status = Ppr.statusInProgress}) => Ppr(
          uuid: 'p-1',
          title: null,
          status: status,
          periodicTaskUuids: const {'a', 'b'},
          waitingTasks: const [
            PprWaitingTask(periodicTaskUuid: 'a', title: 'Первая'),
            PprWaitingTask(periodicTaskUuid: 'b', title: 'Вторая'),
          ],
        );

    test('все ждущие из ответа ППР — сервер уже отобрал область', () {
      expect(
        visibleWaitingTasks(ppr()).map((t) => t.periodicTaskUuid),
        ['a', 'b'],
      );
    });

    test('ППР в очереди — ждущих нет', () {
      expect(visibleWaitingTasks(ppr(status: Ppr.statusQueued)), isEmpty);
    });

    test('доступ сменился, ППР не перечитаны — прежний состав не показываем',
        () {
      expect(visibleWaitingTasks(ppr(), accessStale: true), isEmpty);
    });
  });

  test('ppr_changed — технический сигнал, не служебный метод', () {
    expect(pprChangedEvent, 'ppr_changed');
    expect(isClientSignalEvent(pprChangedEvent), isFalse);
  });

  group('смена аккаунта', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ppr_waiting');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('кэш видимости прошлой версии стирается вместе с ППР', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      await provider.stringBox.put(legacyPprWaitingVisibilityKey, '{}');

      await provider.clearCachedData();

      expect(
        provider.stringBox.containsKey(legacyPprWaitingVisibilityKey),
        isFalse,
      );
    });

    test('после смены доступа ждущие скрыты до перечитывания ППР', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      const ppr = Ppr(
        uuid: 'p-1',
        title: null,
        status: Ppr.statusInProgress,
        periodicTaskUuids: {'a'},
        waitingTasks: [PprWaitingTask(periodicTaskUuid: 'a', title: 'A')],
      );
      expect(provider.pprWaitingTasksForUser(ppr), hasLength(1));

      provider.refreshAccess();
      expect(provider.pprWaitingTasksForUser(ppr), isEmpty);
    });
  });
}
