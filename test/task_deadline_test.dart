import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/model/task_access.dart';
import 'package:qr_scan_industry/src/tasks/task_deadline.dart';

/// Выданные задания (бэкенд `ec225a5`, `fd3f703`): сервер их сам не закрывает,
/// вышедший срок задание не отменяет. Обходчик видит все незакрытые, старые —
/// с пометкой «Просрочено».
void main() {
  final now = DateTime.utc(2026, 11, 6, 12);

  Task task({
    String uuid = 't-1',
    DateTime? deadline,
    String status = 'scheduled',
    TaskAccess? access,
  }) =>
      Task(
        uuid: uuid,
        resultStatus: status,
        targetType: 'periodic',
        periodicTask: null,
        equipmentUuid: 'eq-1',
        roles: const [],
        comment: null,
        access: access,
        deadlineAt: deadline,
      );

  const returned = TaskAccess(
    directionScope: 'single',
    directions: [],
    allowedActions: ['execute'],
    returned: true,
  );

  group('isCurrentScheduledTask — сервер с template_schedule', () {
    Map<String, dynamic> issued(
            {DateTime? created, String status = 'scheduled'}) =>
        {
          'result_status': status,
          'created_at': (created ?? now).toIso8601String(),
          'periodic_task': {
            'periodicity_rule': 'day',
            'next_due_at': null,
            'last_run_at': (created ?? now).toIso8601String(),
            'template_schedule': {'next_due_at': null, 'last_run_at': null},
          },
        };

    test('задание месячной давности остаётся', () {
      expect(
        isCurrentScheduledTask(
            issued(created: now.subtract(const Duration(days: 30))), now),
        isTrue,
      );
    });

    test('часы телефона отстают — новое задание не прячется', () {
      expect(
        isCurrentScheduledTask(
            issued(created: now.add(const Duration(minutes: 5))), now),
        isTrue,
      );
    });

    test('не плановое и осмотр без задачи — нет', () {
      expect(isCurrentScheduledTask(issued(status: 'open'), now), isFalse);
      expect(
        isCurrentScheduledTask(
            {'result_status': 'scheduled', 'periodic_task': null}, now),
        isFalse,
      );
    });
  });

  group('isCurrentScheduledTask — сервер прошлой версии', () {
    Map<String, dynamic> legacy({
      required Duration age,
      String rule = 'day',
      DateTime? lastRun,
      DateTime? nextDue,
    }) =>
        {
          'result_status': 'scheduled',
          'created_at': now.subtract(age).toIso8601String(),
          'periodic_task': {
            'periodicity_rule': rule,
            'last_run_at': lastRun?.toIso8601String(),
            'next_due_at': nextDue?.toIso8601String(),
          },
        };

    final dayAgo = now.subtract(const Duration(days: 1));

    test('периодическая — один период от выдачи', () {
      expect(
        isCurrentScheduledTask(
            legacy(
                age: const Duration(hours: 1), lastRun: dayAgo, nextDue: now),
            now),
        isTrue,
      );
      expect(
        isCurrentScheduledTask(
            legacy(age: const Duration(days: 2), lastRun: dayAgo, nextDue: now),
            now),
        isFalse,
      );
    });

    test('разовая — всегда', () {
      expect(
        isCurrentScheduledTask(
            legacy(age: const Duration(days: 90), rule: 'once'), now),
        isTrue,
      );
    });

    test('без следующего запуска — после выдачи', () {
      expect(
        isCurrentScheduledTask(
            legacy(age: const Duration(days: 90), lastRun: dayAgo), now),
        isTrue,
      );
      expect(
        isCurrentScheduledTask(
            legacy(age: const Duration(hours: -1), lastRun: dayAgo), now),
        isFalse,
      );
    });

    test('не запускалась и без следующего запуска — нет', () {
      expect(
        isCurrentScheduledTask(legacy(age: const Duration(hours: 1)), now),
        isFalse,
      );
    });
  });

  group('deadline_at', () {
    Map<String, dynamic> json(Object? deadline) => {
          'uuid': 't-1',
          'result_status': 'scheduled',
          'target_type': 'periodic',
          'periodic_task': null,
          'equipment_uuid': 'eq-1',
          'photos': const <dynamic>[],
          'deadline_at': deadline,
        };

    test('разбирается из ответа', () {
      expect(Task.fromJson(json('2026-11-06T10:00:00Z')).deadlineAt,
          DateTime.utc(2026, 11, 6, 10));
    });

    test('нет поля или null — срока нет', () {
      expect(Task.fromJson(json(null)).deadlineAt, isNull);
      expect(
        Task.fromJson(json(null)..remove('deadline_at')).deadlineAt,
        isNull,
      );
    });
  });

  group('просрочка', () {
    test('срок прошёл — просрочено, не наступил — нет', () {
      expect(
        task(deadline: now.subtract(const Duration(minutes: 1)))
            .isOverdueAt(now),
        isTrue,
      );
      expect(
        task(deadline: now.add(const Duration(minutes: 1))).isOverdueAt(now),
        isFalse,
      );
    });

    test('без срока — не просрочено', () {
      expect(task().isOverdueAt(now), isFalse);
    });

    test('доработка не считается просроченной', () {
      expect(
        task(
          status: 'closed',
          access: returned,
          deadline: now.subtract(const Duration(days: 3)),
        ).isOverdueAt(now),
        isFalse,
      );
    });
  });

  group('подпись срока', () {
    test('просроченное и текущее — разными словами', () {
      expect(
        taskDeadlineText(
            task(deadline: now.subtract(const Duration(hours: 1))), now),
        startsWith('Просрочено, срок '),
      );
      expect(
        taskDeadlineText(
            task(deadline: now.add(const Duration(hours: 1))), now),
        startsWith('Срок: '),
      );
    });

    test('без срока и у доработки подписи нет', () {
      expect(taskDeadlineText(task(), now), isNull);
      expect(
        taskDeadlineText(
            task(status: 'closed', access: returned, deadline: now), now),
        isNull,
      );
    });
  });

  group('строка срока', () {
    Future<void> pump(WidgetTester tester, Task value) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TaskDeadlineLine(task: value))),
        );

    testWidgets('просроченное — красным', (tester) async {
      await pump(
        tester,
        task(deadline: DateTime.now().subtract(const Duration(days: 1))),
      );

      final text = tester.widget<Text>(find.textContaining('Просрочено'));
      final context = tester.element(find.byType(TaskDeadlineLine));
      expect(text.style?.color, Theme.of(context).colorScheme.error);
    });

    testWidgets('срок не наступил — обычным цветом', (tester) async {
      await pump(
        tester,
        task(deadline: DateTime.now().add(const Duration(days: 1))),
      );

      final text = tester.widget<Text>(find.textContaining('Срок: '));
      final context = tester.element(find.byType(TaskDeadlineLine));
      expect(text.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
    });

    testWidgets('без срока строки нет', (tester) async {
      await pump(tester, task());

      expect(find.byType(Text), findsNothing);
    });
  });

  group('порядок в группе', () {
    test('сначала самый ранний срок, без срока — в конце', () {
      final sorted = [
        task(uuid: 'none-b'),
        task(uuid: 'later', deadline: now),
        task(uuid: 'none-a'),
        task(uuid: 'early', deadline: now.subtract(const Duration(days: 2))),
      ]..sort(compareTasksByDeadline);

      expect(sorted.map((t) => t.uuid), ['early', 'later', 'none-a', 'none-b']);
    });
  });

  group('Hive', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('task_deadline');
      Hive.init(dir.path);
      Hive.registerAdapter(TaskAdapter(), override: true);
    });

    tearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    });

    test('срок переживает запись', () async {
      final box = await Hive.openBox<Task>('tasks');
      await box.put('t-1', task(deadline: DateTime.utc(2026, 11, 6, 10)));
      await box.close();

      final stored = (await Hive.openBox<Task>('tasks')).get('t-1')!;

      expect(stored.deadlineAt?.toUtc(), DateTime.utc(2026, 11, 6, 10));
    });

    test('запись прошлой версии читается без срока', () async {
      Hive.registerAdapter(_LegacyTaskAdapter(), override: true);
      final box = await Hive.openBox<Task>('tasks');
      await box.put('t-1', task(deadline: now));
      await box.close();

      Hive.registerAdapter(TaskAdapter(), override: true);
      final stored = (await Hive.openBox<Task>('tasks')).get('t-1')!;

      expect(stored.uuid, 't-1');
      expect(stored.deadlineAt, isNull);
    });
  });
}

/// Адаптер прошлой версии: те же поля, но без срока в конце записи.
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
    writer.write(null);
    writer.write(obj.access?.encode());
  }
}
