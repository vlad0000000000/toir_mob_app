import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/task_visibility.dart';
import 'package:qr_scan_industry/src/model/access_profile.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/model/task_access.dart';

const _me = 'me-uuid';
const _mechanics = AccessRef(id: 3, uuid: 'dir-mech', name: 'Механик');
const _welders = AccessRef(id: 4, uuid: 'dir-weld', name: 'Сварщик');

AccessProfile _profile({AccessRef? direction = _mechanics}) => AccessProfile(
      permissions: const {'tasks.view', 'tasks.execute'},
      role: const AccessRef(id: 7, uuid: 'role', name: 'Обходчик'),
      roleActive: true,
      direction: direction,
      companyId: '1',
    );

/// Экземпляр задачи, как его отдаёт сервер обходчику с правом выполнения.
TaskAccess _instance({
  String scope = 'single',
  List<AccessRef> directions = const [_mechanics],
  String? inspector,
  List<String> actions = const ['take', 'execute', 'edit'],
}) =>
    TaskAccess(
      directionScope: scope,
      directions: scope == 'all' ? const [] : directions,
      inspectorUuid: inspector,
      allowedActions: actions,
    );

/// Адаптер задачи до появления [Task.access] — формат, что лежит в кэше
/// задач на устройствах с прошлой версией.
class _LegacyTaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 4;

  @override
  Task read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.write(obj.uuid);
    writer.write(obj.resultStatus);
    writer.write(obj.targetType);
    writer.write(obj.periodicTask);
    writer.write(obj.equipmentUuid);
    writer.write(obj.roles);
    writer.write(obj.responsibleUser);
    writer.write(obj.comment);
    writer.write(obj.equipmentFault);
    writer.write(obj.photos);
    writer.write(null); // spare_part_usage
  }
}

void main() {
  group('плановая задача видна обходчику', () {
    bool available(TaskAccess access, {AccessProfile? profile}) =>
        isScheduledTaskAvailable(access, userUuid: _me, profile: profile);

    test('своего направления', () {
      expect(available(_instance(), profile: _profile()), isTrue);
    });

    test('общая — даже обходчику без направления', () {
      // Раньше её не видел никто: у общей задачи список направлений пустой.
      expect(
        available(_instance(scope: 'all'), profile: _profile(direction: null)),
        isTrue,
      );
    });

    test('чужого направления — нет (задачи ППР приходят мимо фильтра)', () {
      expect(
        available(_instance(directions: const [_welders]), profile: _profile()),
        isFalse,
      );
    });

    test('старая задача нескольких направлений — если среди них моё', () {
      expect(
        available(
          _instance(
            scope: 'legacy_multiple',
            directions: const [_welders, _mechanics],
          ),
          profile: _profile(),
        ),
        isTrue,
      );
    });

    test('взятая мной — даже после смены направления', () {
      expect(
        available(
          _instance(directions: const [_welders], inspector: _me),
          profile: _profile(),
        ),
        isTrue,
      );
    });

    test('взятая другим исполнителем — нет', () {
      // Сервер в таком случае не даёт `execute`.
      expect(
        available(
          _instance(inspector: 'other', actions: const []),
          profile: _profile(),
        ),
        isFalse,
      );
    });

    test('без права выполнения — нет', () {
      expect(
        available(_instance(actions: const ['review']), profile: _profile()),
        isFalse,
      );
    });

    test('профиль ещё неизвестен — верим отбору сервера', () {
      expect(
        available(_instance(directions: const [_welders]), profile: null),
        isTrue,
      );
    });
  });

  group('назначенная задача', () {
    test('экземпляр — по праву выполнения', () {
      expect(isOpenTaskActionable(_instance()), isTrue);
    });

    test('прямой осмотр — по праву изменения', () {
      expect(
        isOpenTaskActionable(const TaskAccess(allowedActions: ['edit'])),
        isTrue,
      );
    });

    test('ни того, ни другого — не показываем', () {
      expect(isOpenTaskActionable(const TaskAccess()), isFalse);
    });
  });

  group('открытая задача в списке', () {
    bool available({String? responsible, TaskAccess? access}) =>
        isOpenTaskAvailable(
            responsibleUuid: responsible, access: access, userUuid: _me);

    test('назначена мне ответственным', () {
      expect(available(responsible: _me, access: _instance()), isTrue);
    });

    test('переназначена мне исполнителем — ответственного нет', () {
      // `reassign` на сервере ставит inspector и переводит задачу в open,
      // ответственного не трогает. Раньше такая задача не была видна.
      expect(available(access: _instance(inspector: _me)), isTrue);
    });

    test('переназначена другому — не моя, даже если я ответственный', () {
      expect(
        available(
          responsible: _me,
          access: _instance(inspector: 'other', actions: const []),
        ),
        isFalse,
      );
    });

    test('чужая задача — нет', () {
      expect(available(responsible: 'other', access: _instance()), isFalse);
      expect(available(access: _instance(inspector: 'other')), isFalse);
    });

    test('прямой осмотр, заведённый мной, но назначенный другому — не мой', () {
      // У прямого осмотра `inspector` — автор, а не исполнитель.
      expect(
        available(
          responsible: 'other',
          access:
              const TaskAccess(inspectorUuid: _me, allowedActions: ['edit']),
        ),
        isFalse,
      );
    });

    test('прямой осмотр, где я ответственный, — мой', () {
      expect(
        available(
          responsible: _me,
          access: const TaskAccess(
              inspectorUuid: 'author', allowedActions: ['edit']),
        ),
        isTrue,
      );
    });

    test('сервер без модели доступа — по ответственному', () {
      expect(available(responsible: _me), isTrue);
      expect(available(responsible: 'other'), isFalse);
    });
  });

  group('кто закрыл задачу (счётчик ППР)', () {
    test('по исполнителю', () {
      expect(isTaskDoneByMe(_instance(inspector: _me), _me), isTrue);
      expect(isTaskDoneByMe(_instance(inspector: 'other'), _me), isFalse);
    });

    test('исполнитель неизвестен — решает старое правило', () {
      expect(isTaskDoneByMe(_instance(), _me), isNull);
      expect(isTaskDoneByMe(null, _me), isNull);
    });
  });

  group('подпись задачи в списке', () {
    String? label(TaskAccess? access, {AccessProfile? profile}) =>
        taskScopeLabel(access, profile: profile, sharedLabel: 'Общая задача');

    test('общая', () {
      expect(
          label(_instance(scope: 'all'), profile: _profile()), 'Общая задача');
    });

    test('своё направление не подписываем', () {
      expect(label(_instance(), profile: _profile()), isNull);
    });

    test('чужое направление — его название', () {
      expect(
        label(_instance(directions: const [_welders]), profile: _profile()),
        'Сварщик',
      );
    });

    test('прямой осмотр и запись прошлой версии — без подписи', () {
      expect(label(const TaskAccess(), profile: _profile()), isNull);
      expect(label(null, profile: _profile()), isNull);
    });
  });

  group('TaskAccess', () {
    test('разбор ответа сервера', () {
      final access = TaskAccess.fromInspectionJson({
        'inspector': {'uuid': 'u-1', 'username': 'mech1'},
        'direction_scope': 'single',
        'direction': {'id': 3, 'uuid': 'dir-mech', 'name': 'Механик'},
        'directions': [
          {'id': 3, 'uuid': 'dir-mech', 'name': 'Механик'},
        ],
        'allowed_actions': ['execute', 'edit'],
      });

      expect(access.inspectorUuid, 'u-1');
      expect(access.directions.single.name, 'Механик');
      expect(access.can('execute'), isTrue);
      expect(access.isShared, isFalse);
    });

    test('прямой осмотр без исполнителя', () {
      final access = TaskAccess.fromInspectionJson({
        'inspector': null,
        'direction_scope': null,
        'directions': <dynamic>[],
        'allowed_actions': <dynamic>[],
      });

      expect(access.inspectorUuid, isNull);
      expect(access.directionScope, isNull);
      expect(access.allowedActions, isEmpty);
    });

    test('сервер без модели доступа — доступ неизвестен, а не «ничего нельзя»',
        () {
      // Старый бэкенд полей доступа не присылает. Пустой `allowed_actions`
      // спрятал бы все назначенные задачи — неизвестный их оставляет.
      expect(TaskAccess.fromServer({'uuid': 't-1', 'inspector': null}), isNull);
    });

    test('явный пустой список прав — сервер действительно запретил', () {
      final access = TaskAccess.fromServer({
        'uuid': 't-1',
        'allowed_actions': <dynamic>[],
      });

      expect(access, isNotNull);
      expect(access!.allowedActions, isEmpty);
    });

    test('строка переживает запись и чтение', () {
      final access = _instance(inspector: _me);

      final restored = TaskAccess.decode(access.encode())!;

      expect(restored.inspectorUuid, _me);
      expect(restored.directions.single.uuid, 'dir-mech');
      expect(restored.allowedActions, access.allowedActions);
    });

    test('пустая или битая строка — доступ неизвестен', () {
      expect(TaskAccess.decode(null), isNull);
      expect(TaskAccess.decode(''), isNull);
      expect(TaskAccess.decode('{не json'), isNull);
    });
  });

  group('адаптер Task', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('task_hive');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    });

    Task sample({TaskAccess? access}) => Task(
          uuid: 't-1',
          resultStatus: 'scheduled',
          targetType: 'periodic',
          periodicTask: null,
          equipmentUuid: 'eq-1',
          roles: const [],
          comment: null,
          photos: const ['https://example.test/1.jpg'],
          access: access,
        );

    test('доступ переживает запись и чтение', () async {
      Hive.registerAdapter(TaskAdapter());
      final box = await Hive.openBox<Task>('tasks');
      await box.put('t-1', sample(access: _instance(inspector: _me)));
      await box.close();

      final reopened = await Hive.openBox<Task>('tasks');
      final task = reopened.get('t-1')!;

      expect(task.access!.inspectorUuid, _me);
      expect(task.access!.can('execute'), isTrue);
      expect(task.photos.single, 'https://example.test/1.jpg');
    });

    test('запись прошлой версии читается — доступ неизвестен', () async {
      Hive.registerAdapter(_LegacyTaskAdapter());
      final legacy = await Hive.openBox<Task>('tasks');
      await legacy.put('t-1', sample());
      await legacy.close();
      Hive.resetAdapters();

      Hive.registerAdapter(TaskAdapter());
      final reopened = await Hive.openBox<Task>('tasks');
      final task = reopened.get('t-1')!;

      expect(task.uuid, 't-1');
      expect(task.access, isNull);
      expect(task.photos.single, 'https://example.test/1.jpg');
    });
  });
}
