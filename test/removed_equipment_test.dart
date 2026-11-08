import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/periodic_task_models.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/tasks/removed_equipment.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

PeriodicTask _template(String equipmentUuid) => PeriodicTask(
      id: 1,
      uuid: 'template-$equipmentUuid',
      equipment: Equipment(
        id: 7,
        uuid: equipmentUuid,
        name: 'Насос',
        typeModel: 'К100',
      ),
      title: 'Осмотр',
      periodicityRule: 'once',
      periodicityRuleDisplay: 'Однократно',
      customRoles: const [],
      nextDueAt: null,
      isActive: false,
      createdAt: null,
    );

Task _task(String uuid, String equipmentUuid, {bool withTemplate = true}) =>
    Task(
      uuid: uuid,
      resultStatus: 'scheduled',
      targetType: 'periodic',
      periodicTask: withTemplate ? _template(equipmentUuid) : null,
      equipmentUuid: equipmentUuid,
      roles: const [],
      comment: null,
    );

/// Взятая задача по оборудованию, удалённому в вебе (решение 08.11.2026):
/// оборудование ушло из справочника, а задача остаётся в «Задачах», чтобы
/// обходчик мог её завершить. Подтверждение удаления — `deleted` синхронизации
/// и список `archived=true`.
void main() {
  group('updateRemovedEquipment', () {
    test('deleted добавляется, вернувшееся записью — убирается', () {
      expect(
        updateRemovedEquipment({'a', 'b'}, deleted: ['c'], restored: ['b']),
        {'a', 'c'},
      );
    });

    test('полный проход только снимает вернувшееся', () {
      expect(
        updateRemovedEquipment({'a', 'b'}, deleted: const [], restored: ['a']),
        {'b'},
      );
    });
  });

  group('removedEquipmentRecords', () {
    test('одна запись на оборудование, название и id — из ответа сервера', () {
      final records = removedEquipmentRecords(
        [
          _task('t1', 'eq-gone'),
          _task('t2', 'eq-gone'),
          _task('t3', 'eq-alive'),
        ],
        knownEquipment: const {'eq-alive'},
      );

      expect(records, hasLength(1));
      expect(records.single.uuid, 'eq-gone');
      expect(records.single.name, 'Насос');
      expect(records.single.id, 7);
      expect(records.single.state, isNull);
    });

    test('задача без шаблона — общее название и отрицательный id', () {
      final records = removedEquipmentRecords(
        [_task('t1', 'eq-gone', withTemplate: false)],
        knownEquipment: const {},
      );

      expect(records.single.name, RemovedEquipmentStrings.unknownName);
      expect(records.single.id, isNegative);
    });
  });

  group('collectPagedUuids', () {
    List<Map<String, Object?>> page(int from, int count) => [
          for (var i = from; i < from + count; i++) {'uuid': 'eq-$i'},
        ];

    test('собирает uuid со всех страниц, короткая — последняя', () async {
      final skips = <int>[];
      final uuids = await collectPagedUuids(limit: 2, (skip) async {
        skips.add(skip);
        return switch (skip) {
          0 => page(0, 2),
          2 => page(2, 2),
          _ => page(4, 1),
        };
      });

      expect(skips, [0, 2, 4]);
      expect(uuids, {'eq-0', 'eq-1', 'eq-2', 'eq-3', 'eq-4'});
    });

    test('сервер не уважает skip — останавливаемся по предохранителю',
        () async {
      var calls = 0;
      await collectPagedUuids(limit: 1, maxPages: 3, (_) async {
        calls++;
        return page(0, 1);
      });

      expect(calls, 3);
    });
  });

  group('на устройстве', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('removed_equipment');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('архив ещё не загружен; полный проход снимает отметку', () async {
      final provider = await testDataProvider();
      expect(provider.isArchivedEquipmentLoaded, isFalse);

      await provider.markArchivedEquipmentLoaded();
      expect(provider.isArchivedEquipmentLoaded, isTrue);

      await provider.markArchivedEquipmentStale();
      expect(provider.isArchivedEquipmentLoaded, isFalse);
    });

    test('подтверждения сохраняются; смена аккаунта их стирает', () async {
      final provider = await testDataProvider();
      await provider.markArchivedEquipmentLoaded();
      await provider.rememberRemovedEquipment(
        deleted: const ['eq-gone'],
        restored: const [],
      );
      expect(provider.removedEquipmentUuids, {'eq-gone'});

      await provider.rememberRemovedEquipment(
        deleted: const [],
        restored: const ['eq-gone'],
      );
      expect(provider.removedEquipmentUuids, isEmpty);

      await provider.rememberRemovedEquipment(
        deleted: const ['eq-2'],
        restored: const [],
      );
      await provider.clearCachedData();
      expect(provider.removedEquipmentUuids, isEmpty);
      expect(provider.isArchivedEquipmentLoaded, isFalse);
    });
  });
}
