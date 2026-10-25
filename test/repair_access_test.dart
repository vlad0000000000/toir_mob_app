import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/section_access.dart';
import 'package:qr_scan_industry/src/model/access_profile.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/repairs/repair_access.dart';

const _me = 'me-uuid';

Repair _repair({String? owner = _me, List<String>? actions}) => Repair(
      id: 1,
      uuid: 'repair-1',
      status: RepairStatuses.open,
      equipmentUuid: 'eq-1',
      equipmentName: 'Насос',
      createdAt: DateTime.utc(2026, 10, 23),
      startedAt: DateTime.utc(2026, 10, 23),
      responsibleUserUuid: owner,
      responsibleRoleUuid: 'dir-mech',
      allowedActions: actions,
    );

/// Адаптер ремонта до разрешений сервера — формат кэша прошлой версии.
class _LegacyRepairAdapter extends TypeAdapter<Repair> {
  @override
  final int typeId = 23;

  @override
  Repair read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, Repair obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.status);
    writer.write(obj.equipmentUuid);
    writer.write(obj.equipmentName);
    writer.write(obj.equipmentTypeModel);
    writer.write(obj.consumptionNormUuid);
    writer.write(obj.consumptionNormName);
    writer.write(obj.createdAt);
    writer.write(obj.startedAt);
    writer.write(obj.underReviewAt);
    writer.write(obj.completedAt);
    writer.write(obj.duration);
    writer.write(obj.comment);
    writer.write(obj.responsibleUserUuid);
    writer.write(obj.responsibleUserFullname);
    writer.write(obj.responsibleRoleUuid);
    writer.write(obj.responsibleRoleName);
    writer.write(obj.actualConsumptions);
    writer.write(obj.photos);
    writer.write(obj.normItems);
    writer.write(obj.detailsLoaded);
  }
}

void _registerNested() {
  Hive.registerAdapter(RepairConsumptionAdapter());
  Hive.registerAdapter(RepairPhotoAdapter());
  Hive.registerAdapter(RepairNormItemAdapter());
}

void main() {
  group('работа над ремонтом', () {
    RepairWorkBlock? block(Repair repair, {bool roleCanWork = true}) =>
        repairWorkBlock(repair, roleCanWork: roleCanWork, myUuid: _me);

    test('сервер разрешил — можно, даже без права в профиле', () {
      // Подсказку сервер считает по тем же правилам, что и само сохранение.
      expect(
        block(_repair(actions: [RepairActions.execute]), roleCanWork: false),
        isNull,
      );
    });

    test('сервер не разрешил свой ремонт — нет доступа', () {
      // Например, ремонт ушёл из направления или подразделения роли.
      expect(block(_repair(actions: const [])), RepairWorkBlock.noAccess);
    });

    test('сервер не разрешил чужой ремонт — назначен на другого', () {
      expect(
        block(_repair(owner: 'other', actions: const [])),
        RepairWorkBlock.notMine,
      );
    });

    test('без подсказки сервера — по праву роли и исполнителю', () {
      expect(block(_repair()), isNull);
      expect(block(_repair(), roleCanWork: false), RepairWorkBlock.noAccess);
      expect(block(_repair(owner: 'other')), RepairWorkBlock.notMine);
    });
  });

  group('взять и отправить', () {
    test('взять — по подсказке сервера, без неё — по праву', () {
      final free = _repair(owner: null, actions: [RepairActions.claim]);
      final outOfScope = _repair(owner: null, actions: const []);

      expect(canClaimRepair(free, roleCanWork: false), isTrue);
      expect(canClaimRepair(outOfScope, roleCanWork: true), isFalse);
      expect(canClaimRepair(_repair(owner: null), roleCanWork: true), isTrue);
    });

    test('отправить на рассмотрение — если сервер не запретил', () {
      expect(
        canSubmitRepair(_repair(actions: [RepairActions.submitReview])),
        isTrue,
      );
      expect(
        canSubmitRepair(_repair(actions: [RepairActions.execute])),
        isFalse,
      );
      expect(canSubmitRepair(_repair()), isTrue);
    });
  });

  group('разбор ответа', () {
    Map<String, dynamic> json({Object? actions}) => {
          'id': 1,
          'uuid': 'repair-1',
          'status': 'open',
          'created_at': '2026-10-23T10:00:00Z',
          'started_at': '2026-10-23T10:00:00Z',
          if (actions != null) 'allowed_actions': actions,
        };

    test('разрешения сервера', () {
      final repair = Repair.fromJson(json(actions: ['claim']));

      expect(repair.allows(RepairActions.claim), isTrue);
      expect(repair.allows(RepairActions.execute), isFalse);
    });

    test('сервер прошлой версии — разрешения неизвестны', () {
      final repair = Repair.fromJson(json());

      expect(repair.allowedActions, isNull);
      expect(repair.allows(RepairActions.execute), isNull);
    });

    test('из списка — разрешения свежие, подробности из кэша', () {
      final cached = Repair.fromJson({
        ...json(actions: ['execute']),
        'comment': 'заменил сальник',
        'actual_consumptions': <dynamic>[],
      });
      final fromList = Repair.fromJson(json(actions: const <String>[]));

      final merged = fromList.withDetailsFrom(cached);

      expect(merged.comment, 'заменил сальник');
      expect(merged.allowedActions, isEmpty);
    });
  });

  group('расход в правке ремонта', () {
    SectionAccess access(Set<String> permissions) => SectionAccess(
          profile: AccessProfile(
            permissions: permissions,
            role: const AccessRef(id: 7, uuid: 'role', name: 'Обходчик'),
            roleActive: true,
            companyId: '1',
          ),
        );

    test('с правом на ЗИП — уходит, даже пустой', () {
      expect(
        access({Perm.sparePartsView}).consumptionsToSend(const <int>[]),
        isEmpty,
      );
    });

    test('без права — поля нет вовсе, иначе сервер отклонит всю правку', () {
      expect(
        access({Perm.repairExecute}).consumptionsToSend(const <int>[]),
        isNull,
      );
    });

    test('расход внесён, а права уже нет — правку держим, а не урезаем', () {
      // Урезанная правка ушла бы, и запись с расходом удалилась бы как
      // доставленная — расход пропал бы безвозвратно.
      expect(
          access({Perm.repairExecute}).consumptionsBlocked(const [1]), isTrue);
      expect(
          access({Perm.repairExecute}).consumptionsBlocked(const []), isFalse);
      expect(access({Perm.sparePartsView}).consumptionsBlocked(const [1]),
          isFalse);
    });
  });

  group('кэш прошлой версии', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('repair_access_hive');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    });

    test('ремонт без разрешений читается — неизвестно, а не «ничего нельзя»',
        () async {
      // Подмена адаптера — через `override`, а не `resetAdapters()`: сброс
      // снимает и встроенный адаптер дат, и запись не прочиталась бы вовсе.
      Hive.registerAdapter(_LegacyRepairAdapter(), override: true);
      _registerNested();
      final legacy = await Hive.openBox<Repair>('repairs');
      await legacy.put('repair-1', _repair(actions: [RepairActions.claim]));
      await legacy.close();

      Hive.registerAdapter(RepairAdapter(), override: true);
      final reopened = await Hive.openBox<Repair>('repairs');
      final repair = reopened.get('repair-1')!;

      expect(repair.uuid, 'repair-1');
      expect(repair.responsibleUserUuid, _me);
      expect(repair.allowedActions, isNull);
    });
  });
}
