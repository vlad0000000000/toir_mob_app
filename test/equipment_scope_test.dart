import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/equipment_scope.dart';
import 'package:qr_scan_industry/src/model/access_profile.dart';
import 'package:qr_scan_industry/src/model/inventory_record.dart';
import 'package:qr_scan_industry/strings.dart';

InventoryRecord _equipment({
  String? locationUuid,
  String location = 'Цех №1',
  String? divisionUuid,
}) =>
    InventoryRecord(
      id: 1,
      uuid: 'eq-1',
      name: 'Станок токарный 16К20',
      typeModel: '16К20',
      serialNumber: 'SN-1',
      location: location,
      locationUuid: locationUuid,
      divisionUuid: divisionUuid,
    );

AccessProfile _profile({bool allDivisions = false}) => AccessProfile(
      permissions: {
        'inspection.create',
        if (allDivisions) Perm.scopeAllDivisions,
      },
      role: const AccessRef(id: 7, uuid: 'role', name: 'Обходчик'),
      roleActive: true,
      divisions: const [AccessRef(id: 3, uuid: 'div-1', name: 'Производство')],
      companyId: '1',
    );

/// Адаптер оборудования с uuid помещения, но без подразделения — формат
/// кэша версии до бэкенда `06b145f`.
class _LocationOnlyInventoryAdapter extends _LegacyInventoryAdapter {
  @override
  void write(BinaryWriter writer, InventoryRecord obj) {
    super.write(writer, obj);
    writer.write(obj.locationUuid);
  }
}

/// Адаптер оборудования до uuid помещения — формат кэша прошлой версии.
class _LegacyInventoryAdapter extends TypeAdapter<InventoryRecord> {
  @override
  final int typeId = 1;

  @override
  InventoryRecord read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, InventoryRecord obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.name);
    writer.write(obj.typeModel);
    writer.write(obj.serialNumber);
    writer.write(obj.location);
    writer.write(obj.manufacturer);
    writer.write(obj.quantity);
    writer.write(obj.dateOfEntry);
    writer.write(obj.description);
    writer.write(obj.imageData);
    writer.write(obj.usageParameters);
    writer.write(obj.state);
    writer.write(obj.hasOpenRepair);
  }
}

/// «Моё оборудование» при «Осмотре без QR»: справочник приходит по всей
/// компании, своё отличаем по помещению — как сервер.
void main() {
  group('isMyEquipment', () {
    const mine = {'loc-1', 'loc-2'};

    bool my(InventoryRecord equipment,
            {AccessProfile? profile, Set<String>? locations = mine}) =>
        isMyEquipment(
          equipment,
          profile: profile ?? _profile(),
          myLocationUuids: locations,
        );

    test('помещение своего подразделения — моё', () {
      expect(my(_equipment(locationUuid: 'loc-1')), isTrue);
    });

    test('помещение чужого подразделения — не моё', () {
      expect(my(_equipment(locationUuid: 'loc-9')), isFalse);
    });

    test('без помещения — не моё, сервер тоже не относит его никуда', () {
      expect(my(_equipment(location: '')), isFalse);
    });

    test('роль «все подразделения» — всё своё', () {
      expect(
        my(_equipment(locationUuid: 'loc-9'),
            profile: _profile(allDivisions: true)),
        isTrue,
      );
    });

    test('сервер без ролей доступа — всё своё', () {
      expect(
        isMyEquipment(_equipment(locationUuid: 'loc-9'),
            profile: null, myLocationUuids: mine),
        isTrue,
      );
    });

    test('помещения ещё не загружены — не прячем', () {
      expect(my(_equipment(locationUuid: 'loc-9'), locations: null), isTrue);
    });

    test('запись прошлой версии без uuid помещения — не прячем', () {
      expect(my(_equipment()), isTrue);
    });

    group('по подразделению из справочника (бэкенд 06b145f)', () {
      test('своё подразделение — моё, даже если помещение чужое', () {
        expect(
          my(_equipment(locationUuid: 'loc-9', divisionUuid: 'div-1')),
          isTrue,
        );
      });

      test('чужое подразделение — не моё, даже если помещение своё', () {
        expect(
          my(_equipment(locationUuid: 'loc-1', divisionUuid: 'div-9')),
          isFalse,
        );
      });

      test('division: null — не моё: ни к одному не относится', () {
        expect(
            my(_equipment(locationUuid: 'loc-1', divisionUuid: '')), isFalse);
      });

      test('помещения не нужны: решает подразделение', () {
        expect(
          my(_equipment(divisionUuid: 'div-1'), locations: null),
          isTrue,
        );
        expect(
          my(_equipment(divisionUuid: 'div-9'), locations: null),
          isFalse,
        );
      });

      test('роль «все подразделения» — всё своё', () {
        expect(
          my(_equipment(divisionUuid: 'div-9'),
              profile: _profile(allDivisions: true)),
          isTrue,
        );
      });
    });
  });

  group('предупреждение при скане чужого оборудования', () {
    test('название и помещение', () {
      expect(
        ForeignEquipmentStrings.body('Компрессор GA22', 'Компрессорная'),
        startsWith('«Компрессор GA22» (Компрессорная) не относится'),
      );
    });

    test('без помещения — без скобок', () {
      expect(
        ForeignEquipmentStrings.body('Компрессор GA22', ''),
        startsWith('«Компрессор GA22» не относится'),
      );
    });
  });

  group('uuid помещения у оборудования', () {
    test('из ответа справочника', () {
      final record = InventoryRecord.fromJson({
        'id': 1,
        'uuid': 'eq-1',
        'name': 'Станок',
        'type_model': null,
        'serial_number': null,
        'location': {'uuid': 'loc-1', 'name': 'Цех №1'},
      });

      expect(record.locationUuid, 'loc-1');
      expect(record.location, 'Цех №1');
    });

    test('без помещения — нет и uuid', () {
      final record = InventoryRecord.fromJson({
        'id': 1,
        'uuid': 'eq-1',
        'name': 'Станок',
        'type_model': null,
        'serial_number': null,
        'location': null,
      });

      expect(record.locationUuid, isNull);
    });

    test('подразделение: есть, null и нет поля — три разных состояния', () {
      Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
            'id': 1,
            'uuid': 'eq-1',
            'name': 'Станок',
            'type_model': null,
            'serial_number': null,
            ...extra,
          };

      final withDivision = InventoryRecord.fromJson(json({
        'division': {'uuid': 'div-1', 'name': 'Производство'},
      }));
      final noDivision = InventoryRecord.fromJson(json({'division': null}));
      final oldServer = InventoryRecord.fromJson(json());

      expect(withDivision.divisionUuid, 'div-1');
      expect(noDivision.divisionUuid, '');
      expect(noDivision.hasDivisionField, isTrue);
      expect(oldServer.divisionUuid, isNull);
      expect(oldServer.hasDivisionField, isFalse);
    });
  });

  group('адаптер', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('inventory_hive');
      Hive.init(dir.path);
      Hive.registerAdapter(UsageParameterAdapter());
    });

    tearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    });

    test('uuid помещения переживает запись и чтение', () async {
      Hive.registerAdapter(InventoryAdapter());
      final box = await Hive.openBox<InventoryRecord>('inventory');
      await box.put('eq-1', _equipment(locationUuid: 'loc-1'));
      await box.close();

      final stored =
          (await Hive.openBox<InventoryRecord>('inventory')).get('eq-1')!;

      expect(stored.locationUuid, 'loc-1');
      expect(stored.location, 'Цех №1');
    });

    test('запись прошлой версии читается — uuid помещения нет', () async {
      Hive.registerAdapter(_LegacyInventoryAdapter(), override: true);
      final legacy = await Hive.openBox<InventoryRecord>('inventory');
      await legacy.put('eq-1', _equipment(locationUuid: 'loc-1'));
      await legacy.close();

      Hive.registerAdapter(InventoryAdapter(), override: true);
      final stored =
          (await Hive.openBox<InventoryRecord>('inventory')).get('eq-1')!;

      expect(stored.name, 'Станок токарный 16К20');
      expect(stored.locationUuid, isNull);
      expect(stored.hasOpenRepair, isFalse);
    });

    test('подразделение переживает запись и чтение, в т.ч. «нет»', () async {
      Hive.registerAdapter(InventoryAdapter());
      final box = await Hive.openBox<InventoryRecord>('inventory');
      await box.put('a', _equipment(divisionUuid: 'div-1'));
      await box.put('b', _equipment(divisionUuid: ''));
      await box.close();

      final reopened = await Hive.openBox<InventoryRecord>('inventory');

      expect(reopened.get('a')!.divisionUuid, 'div-1');
      expect(reopened.get('b')!.divisionUuid, '');
    });

    test('запись с помещением, но без подразделения — поля нет', () async {
      Hive.registerAdapter(_LocationOnlyInventoryAdapter(), override: true);
      final legacy = await Hive.openBox<InventoryRecord>('inventory');
      await legacy.put('eq-1', _equipment(locationUuid: 'loc-1'));
      await legacy.close();

      Hive.registerAdapter(InventoryAdapter(), override: true);
      final stored =
          (await Hive.openBox<InventoryRecord>('inventory')).get('eq-1')!;

      expect(stored.locationUuid, 'loc-1');
      expect(stored.hasDivisionField, isFalse);
    });
  });
}
