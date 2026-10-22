import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/section_access.dart';
import 'package:qr_scan_industry/src/model/access_profile.dart';

AccessProfile _profile(Set<String> permissions, {bool roleActive = true}) =>
    AccessProfile(
      permissions: permissions,
      role: const AccessRef(id: 7, uuid: 'role', name: 'Обходчик'),
      roleActive: roleActive,
      companyId: '1',
    );

SectionAccess _access(Set<String> permissions, {bool qrFree = false}) =>
    SectionAccess(profile: _profile(permissions), qrFreeEnabled: qrFree);

/// Набор мигрированного обходчика (`WALKER_PROFILE_CODES` в миграции
/// бэкенда, без экспорта) — у него не должно быть ни одного замка.
const _migratedWalker = {
  'tasks.view',
  'tasks.execute',
  'tasks.create',
  'tasks.edit',
  'equipment.view',
  'equipment.edit',
  'usage_parameters.create',
  'usage_parameters.edit',
  'divisions.view',
  'ppr.view',
  'inspection.view',
  'inspection.create',
  'inspection.edit',
  'repair.view',
  'repair.create',
  'repair.execute',
  'spare_parts.view',
  'notifications.view',
  'notifications.manage',
  'company.view',
};

void main() {
  test('мигрированному обходчику доступно всё', () {
    final access = _access(_migratedWalker);

    expect(access.scanner, isTrue);
    expect(access.tasks, isTrue);
    expect(access.inspection, isTrue);
    expect(access.repairs, isTrue);
    expect(access.repairCreate, isTrue);
    expect(access.repairWork, isTrue);
    expect(access.spareParts, isTrue);
    expect(access.notifications, isTrue);
    expect(access.changeState, isTrue);
    expect(access.usage, isTrue);
  });

  test('профиль неизвестен — ничего не запираем', () {
    const access = SectionAccess(profile: null, qrFreeEnabled: false);

    expect(access.scanner, isTrue);
    expect(access.repairs, isTrue);
    expect(access.usage, isTrue);
  });

  test('отключённая роль — заперто всё', () {
    final access = SectionAccess(
      profile: _profile(_migratedWalker, roleActive: false),
      qrFreeEnabled: true,
    );

    expect(access.scanner, isFalse);
    expect(access.tasks, isFalse);
    expect(access.repairs, isFalse);
  });

  group('сканер', () {
    test('нужно и найти оборудование, и что-то с ним сделать', () {
      expect(_access({'equipment.view'}).scanner, isFalse);
      expect(_access({'tasks.view', 'tasks.execute'}).scanner, isFalse);
      expect(
        _access({'equipment.view', 'tasks.view', 'tasks.execute'}).scanner,
        isTrue,
      );
      expect(
        _access({'equipment.view', 'inspection.view', 'inspection.create'})
            .scanner,
        isTrue,
      );
    });

    test('без справочника оборудования — через осмотр без QR', () {
      const codes = {'inspection.view', 'inspection.create'};

      expect(_access(codes).scanner, isFalse);
      expect(_access(codes, qrFree: true).scanner, isTrue);
    });
  });

  test('наработка — только с просмотром оборудования', () {
    expect(_access({'usage_parameters.edit'}).usage, isFalse);
    expect(
      _access({'equipment.view', 'usage_parameters.edit'}).usage,
      isTrue,
    );
  });

  test('смена состояния и создание ремонта — независимо друг от друга', () {
    final stateOnly = _access({'equipment.view', 'equipment.edit'});
    final repairOnly = _access({'repair.view', 'repair.create'});

    expect(stateOnly.changeState, isTrue);
    expect(stateOnly.repairCreate, isFalse);
    expect(repairOnly.changeState, isFalse);
    expect(repairOnly.repairCreate, isTrue);
  });

  test('ремонты: смотреть можно, работать — нет', () {
    final access = _access({'repair.view'});

    expect(access.repairs, isTrue);
    expect(access.repairWork, isFalse);
  });
}
