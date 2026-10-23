import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/task_visibility.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/model/task_access.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/strings.dart';

const _me = 'me-uuid';

/// Возврат результата на доработку: проверяющий возвращает уже сданную
/// задачу (`POST /fault_inspections/{uuid}/return`). Её статус остаётся
/// `closed`, признак возврата — блок `review` ответа.
void main() {
  /// Экземпляр задачи из ответа сервера — как его собирает
  /// `build_fault_inspection_list_item`.
  Map<String, dynamic> inspection({
    String state = 'returned',
    int revision = 1,
    String? inspector = _me,
    List<String> actions = const ['execute', 'edit'],
  }) =>
      {
        'uuid': 'task-1',
        'result_status': 'closed',
        'target_type': 'periodic',
        'equipment_uuid': 'eq-1',
        'comment': 'Заменил фильтр',
        'photos': <dynamic>[],
        'inspector': inspector == null ? null : {'uuid': inspector},
        'direction_scope': 'single',
        'directions': <dynamic>[],
        'allowed_actions': actions,
        'review': {
          'state': state,
          'return_comment': 'Нет фото фильтра',
          'returned_by': {'uuid': 'rev-1', 'fullname': 'Петров П. П.'},
          'revision': revision,
        },
      };

  group('разбор ответа', () {
    test('возвращённая задача — причина, кто вернул, версия результата', () {
      final access = TaskAccess.fromInspectionJson(inspection(revision: 2));

      expect(access.returned, isTrue);
      expect(access.returnComment, 'Нет фото фильтра');
      expect(access.returnedBy, 'Петров П. П.');
      expect(access.reviewRevision, 2);
    });

    test('подтверждённая или ждущая проверки — не возвращена', () {
      expect(
        TaskAccess.fromInspectionJson(inspection(state: 'pending')).returned,
        isFalse,
      );
    });

    test('прямой осмотр и сервер прошлой версии — блока проверки нет', () {
      final access = TaskAccess.fromInspectionJson({
        'inspector': null,
        'allowed_actions': <dynamic>[],
      });

      expect(access.returned, isFalse);
      expect(access.reviewRevision, 0);
    });

    test('сведения о возврате переживают запись в Hive строкой', () {
      final access = TaskAccess.fromInspectionJson(inspection(revision: 3));

      final restored = TaskAccess.decode(access.encode())!;

      expect(restored.returned, isTrue);
      expect(restored.returnComment, 'Нет фото фильтра');
      expect(restored.returnedBy, 'Петров П. П.');
      expect(restored.reviewRevision, 3);
    });

    test('строка прошлой версии — не возвращена', () {
      final restored = TaskAccess.decode(
          '{"inspector_uuid":"me-uuid","allowed_actions":["execute"]}')!;

      expect(restored.returned, isFalse);
      expect(restored.reviewRevision, 0);
    });

    test('задача знает, что её вернули — по статусу и признаку вместе', () {
      final returned = Task.fromJson(inspection());
      final done = Task.fromJson(inspection(state: 'confirmed'));

      expect(returned.isReturnedForRework, isTrue);
      expect(done.isReturnedForRework, isFalse);
      // Прежний результат — в самой задаче.
      expect(returned.comment, 'Заменил фильтр');
    });
  });

  group('видна обходчику', () {
    bool available(Map<String, dynamic> json) =>
        isReturnedTaskAvailable(TaskAccess.fromInspectionJson(json),
            userUuid: _me);

    test('её исполнителю, если сервер разрешает выполнять', () {
      expect(available(inspection()), isTrue);
    });

    test('чужая — нет', () {
      expect(available(inspection(inspector: 'other')), isFalse);
    });

    test('без права выполнения — нет', () {
      expect(available(inspection(actions: const [])), isFalse);
    });

    test('не возвращённая закрытая — нет', () {
      expect(available(inspection(state: 'confirmed')), isFalse);
    });
  });

  group('отметка «закрыто на этом телефоне»', () {
    TaskAccess returned(int revision) =>
        TaskAccess.fromInspectionJson(inspection(revision: revision));

    test('хранит версию результата и читается обратно', () {
      expect(parseClosedMark(closedMarkValue(2)), 2);
    });

    test('отметка прошлой версии — версия неизвестна, старше любой', () {
      expect(parseClosedMark('1'), -1);
      expect(parseClosedMark(null), -1);
    });

    test('обычную задачу отметка прячет, как и раньше', () {
      expect(isClosedMarkCurrent(markedRevision: -1), isTrue);
      expect(
        isClosedMarkCurrent(markedRevision: 0, access: const TaskAccess()),
        isTrue,
      );
    });

    test('сдал на этом телефоне, потом вернули — задача видна снова', () {
      // Закрыл плановую (версия 0), проверяющий вернул — версия 1.
      expect(
        isClosedMarkCurrent(markedRevision: 0, access: returned(1)),
        isFalse,
      );
      // Отметка прошлой версии приложения тоже не прячет.
      expect(
        isClosedMarkCurrent(markedRevision: -1, access: returned(1)),
        isFalse,
      );
    });

    test('доработку сдал — до ответа сервера задача спрятана', () {
      expect(
        isClosedMarkCurrent(markedRevision: 1, access: returned(1)),
        isTrue,
      );
    });
  });

  group('отказ сервера на доработке', () {
    test('результат вернули ещё раз, пока осмотр ждал связи', () {
      final reason = scanErrorMessage(Exception(
          '409: Обновите результат: укажите актуальную review_revision для '
          'доработки.'));

      expect(reason, ScanQueueStrings.errorReworkOutdated);
    });
  });
}
