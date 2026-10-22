import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/model/access_profile.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';

/// Ответ `GET /v1/user/me` обходчика с ролью, направлением и подразделением —
/// в том виде, в каком его собирает `build_me` на сервере.
Map<String, dynamic> _me({
  Object? userRole = const {
    'id': 7,
    'uuid': 'role-uuid',
    'name': 'Обходчик — Механик',
    'is_active': true,
  },
  Object? direction = const {
    'id': 3,
    'uuid': 'dir-uuid',
    'name': 'Механик',
  },
  Object? companyId = 12,
  List<String> permissions = const ['tasks.view', 'tasks.execute'],
}) =>
    {
      'uuid': 'user-uuid',
      'username': 'mech1',
      'effective_role': 'Механик',
      'custom_role_id': direction == null ? null : 3,
      'user_role': userRole,
      'direction': direction,
      'permissions': permissions,
      'divisions': [
        {'id': 1, 'uuid': 'div-uuid', 'name': 'Литейный цех'},
      ],
      'access_scope': {
        'company_id': companyId,
        'all_directions': false,
        'direction_id': direction == null ? null : 3,
        'all_divisions': false,
        'division_uuids': ['div-uuid'],
      },
      'access_version': 'a1.r7:2.c2',
    };

void main() {
  group('AccessProfile.fromMeJson', () {
    test('обходчик с ролью и направлением', () {
      final profile = AccessProfile.fromMeJson(_me());

      expect(profile.hasBusinessAccess, isTrue);
      expect(profile.blockCode, isNull);
      expect(profile.role!.name, 'Обходчик — Механик');
      expect(profile.direction!.uuid, 'dir-uuid');
      expect(profile.divisions.single.name, 'Литейный цех');
      expect(profile.companyId, '12');
      expect(profile.accessVersion, 'a1.r7:2.c2');
      expect(profile.can(Perm.tasksExecute), isTrue);
      expect(profile.can(Perm.repairCreate), isFalse);
    });

    test('роль без направления — не ошибка', () {
      // Раньше на `custom_role_id: null` падал весь вход.
      final profile = AccessProfile.fromMeJson(_me(direction: null));

      expect(profile.direction, isNull);
      expect(profile.hasBusinessAccess, isTrue);
    });

    test('роль не назначена', () {
      final profile = AccessProfile.fromMeJson(_me(userRole: null));

      expect(profile.blockCode, NoBusinessAccessException.roleMissing);
      expect(profile.hasBusinessAccess, isFalse);
    });

    test('роль отключена — прав нет, даже если коды пришли', () {
      final profile = AccessProfile.fromMeJson(_me(userRole: {
        'id': 7,
        'uuid': 'role-uuid',
        'name': 'Обходчик — Механик',
        'is_active': false,
      }));

      expect(profile.blockCode, NoBusinessAccessException.roleInactive);
      expect(profile.permissions, contains(Perm.tasksExecute));
      expect(profile.can(Perm.tasksExecute), isFalse);
    });

    test('учётная запись без компании', () {
      final profile = AccessProfile.fromMeJson(_me(companyId: null));

      expect(profile.blockCode, NoBusinessAccessException.companyMissing);
    });

    test('коды блокировки совпадают с кодами отказа сервера', () {
      expect(
        {
          AccessProfile.codeCompanyMissing,
          AccessProfile.codeRoleMissing,
          AccessProfile.codeRoleInactive,
        },
        NoBusinessAccessException.blockedCodes,
      );
    });

    test('мусор в полях не роняет разбор', () {
      final profile = AccessProfile.fromMeJson({
        'user_role': 'не объект',
        'direction': {'name': 'без uuid'},
        'permissions': ['tasks.view', 42, null],
        'divisions': 'не список',
      });

      expect(profile.role, isNull);
      expect(profile.direction, isNull);
      expect(profile.permissions, {'tasks.view'});
      expect(profile.divisions, isEmpty);
      expect(profile.hasBusinessAccess, isFalse);
    });

    test('«все направления» и «все подразделения» — по правам области', () {
      final profile = AccessProfile.fromMeJson(_me(permissions: const [
        'scope.all_directions',
        'scope.all_divisions',
      ]));

      expect(profile.allDirections, isTrue);
      expect(profile.allDivisions, isTrue);
    });
  });

  group('хранение в stringBox', () {
    test('строка переживает запись и чтение', () {
      final profile = AccessProfile.fromMeJson(_me());

      final restored = AccessProfile.decode(profile.encode());

      expect(restored, profile);
      expect(restored!.direction!.name, 'Механик');
      expect(restored.can(Perm.tasksView), isTrue);
    });

    test('пустая или битая строка — профиль неизвестен', () {
      expect(AccessProfile.decode(null), isNull);
      expect(AccessProfile.decode(''), isNull);
      expect(AccessProfile.decode('{не json'), isNull);
      expect(AccessProfile.decode('[]'), isNull);
    });

    test('одинаковый ответ — равные профили', () {
      // Иначе ValueNotifier будил бы экраны на каждую синхронизацию.
      expect(
        AccessProfile.fromMeJson(_me()),
        AccessProfile.fromMeJson(_me()),
      );
    });
  });

  group('блокировка по отказу сервера', () {
    final profile = AccessProfile.fromMeJson(_me());

    test('роль сняли', () {
      expect(
        profile.blockedBy(NoBusinessAccessException.roleMissing).blockCode,
        NoBusinessAccessException.roleMissing,
      );
    });

    test('роль отключили', () {
      final blocked = profile.blockedBy(NoBusinessAccessException.roleInactive);

      expect(blocked.blockCode, NoBusinessAccessException.roleInactive);
      expect(blocked.role!.uuid, 'role-uuid');
    });

    test('неизвестный код профиль не меняет', () {
      expect(profile.blockedBy('permission_denied'), profile);
    });
  });

  group('NoBusinessAccessException.fromResponse', () {
    test('роль не назначена', () {
      final blocked = AccessBlockedException.fromResponse(
        403,
        '{"detail": "Роль доступа не назначена. Обратитесь к администратору.", '
        '"code": "access_role_missing"}',
      );

      expect(blocked, isA<NoBusinessAccessException>());
      expect(blocked!.code, NoBusinessAccessException.roleMissing);
    });

    test('тариф по-прежнему разбирается как тариф', () {
      final blocked = AccessBlockedException.fromResponse(
        403,
        '{"detail": "Срок действия тарифа истёк", '
        '"code": "subscription_expired"}',
      );

      expect(blocked, isA<SubscriptionBlockedException>());
    });

    test('«нет прав на действие» — не блокировка всего доступа', () {
      for (final code in [
        'permission_denied',
        'direction_denied',
        'division_denied',
      ]) {
        expect(
          AccessBlockedException.fromResponse(403, '{"code": "$code"}'),
          isNull,
          reason: code,
        );
      }
    });

    test('другой код ответа — не блокировка', () {
      expect(
        AccessBlockedException.fromResponse(
            401, '{"code": "access_role_missing"}'),
        isNull,
      );
    });
  });

  group('очереди при снятой роли не теряют данные', () {
    final blocked = NoBusinessAccessException(
      NoBusinessAccessException.roleInactive,
    );

    test('для очередей это протухший токен', () {
      expect(blocked, isA<AuthExpiredException>());
    });

    test('осмотр и наработка — повторить позже, не отказ', () {
      expect(isRetryableScanError(blocked), isTrue);
    });

    test('ремонт — повторить позже, не отказ', () {
      expect(isRetryableRepairError(blocked), isTrue);
    });
  });
}
