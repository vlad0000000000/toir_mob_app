import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/pending_repair.dart';
import 'package:qr_scan_industry/src/model/repair.dart';

/// Переходы состояния черновика ремонта.
///
/// Раньше `copyWith` сбрасывал пометку об отказе, если её не передали, и
/// безобидная с виду правка (`copyWith(photoPaths: …)` при добавлении снимка)
/// возвращала отклонённый черновик в очередь. Тесты закрепляют разделение:
/// `copyWith` пометку не трогает, менять её умеют только `markRejected` и
/// `clearRejection`.
void main() {
  PendingRepair rejectedDraft() => PendingRepair(
        localId: 'local-1',
        equipmentUuid: 'eq-1',
        equipmentName: 'Насос',
        startedAt: DateTime.utc(2026, 8, 18, 10),
        createdAt: DateTime.utc(2026, 8, 18, 10),
        comment: 'начал',
        attempts: 2,
        lastError: 'Для этого оборудования уже есть ремонт',
        conflictRepairUuid: 'repair-9',
        serverUuid: 'srv-1',
        photoPaths: const ['a.jpg'],
        submitForReview: true,
      );

  group('copyWith', () {
    test('не снимает пометку об отказе', () {
      final draft = rejectedDraft();
      final withPhoto =
          draft.copyWith(photoPaths: [...draft.photoPaths, 'b.jpg']);

      expect(withPhoto.isRejected, isTrue);
      expect(withPhoto.lastError, draft.lastError);
      expect(withPhoto.conflictRepairUuid, 'repair-9');
      expect(withPhoto.photoPaths, ['a.jpg', 'b.jpg']);
    });

    test('сохраняет уже созданный ремонт и намерение отправить', () {
      final next = rejectedDraft().copyWith(comment: 'дописал');

      expect(next.comment, 'дописал');
      expect(next.serverUuid, 'srv-1');
      expect(next.submitForReview, isTrue);
      expect(next.attempts, 2);
    });
  });

  group('markRejected', () {
    test('ставит причину, считает попытку', () {
      final draft = rejectedDraft().clearRejection();
      final next = draft.markRejected(
        reason: 'Недостаточно ЗИП на складе',
        conflictRepairUuid: null,
      );

      expect(next.isRejected, isTrue);
      expect(next.lastError, 'Недостаточно ЗИП на складе');
      expect(next.attempts, draft.attempts + 1);
    });

    test('не тянет чужой конфликтный ремонт из прошлого отказа', () {
      // Отказ мог быть по другой причине — прежний uuid к ней отношения не
      // имеет, и карточка предложила бы перенос не туда.
      final next = rejectedDraft().markRejected(reason: 'Ошибка сервера');

      expect(next.conflictRepairUuid, isNull);
    });
  });

  group('clearRejection', () {
    test('снимает причину и конфликт, остальное не трогает', () {
      final next = rejectedDraft().clearRejection();

      expect(next.isRejected, isFalse);
      expect(next.lastError, isNull);
      expect(next.conflictRepairUuid, isNull);
      expect(next.serverUuid, 'srv-1');
      expect(next.photoPaths, ['a.jpg']);
      expect(next.submitForReview, isTrue);
      expect(next.attempts, 2);
    });
  });

  group('тело создания', () {
    PendingRepair fresh() => PendingRepair(
          localId: 'local-2',
          equipmentUuid: 'eq-1',
          equipmentName: 'Насос',
          startedAt: DateTime.utc(2026, 10, 24, 9),
          createdAt: DateTime.utc(2026, 10, 24, 9),
          comment: '  течь сальника ',
          consumptionNormUuid: 'norm-1',
        );

    test('фиксируется при первой отправке — комментарий и норма', () {
      final frozen = fresh().freezeCreate(normUuid: 'norm-1');

      expect(fresh().isCreateFrozen, isFalse);
      expect(frozen.isCreateFrozen, isTrue);
      expect(frozen.createComment, 'течь сальника');
      expect(frozen.createNormUuid, 'norm-1');
    });

    test('без права на ЗИП — без нормы', () {
      final frozen = fresh().freezeCreate(normUuid: null);

      expect(frozen.isCreateFrozen, isTrue);
      expect(frozen.createNormUuid, isNull);
    });

    test('правка комментария после отправки тело не меняет', () {
      // Повтор с тем же ключом обязан совпасть с первым запросом — сервер
      // сверяет ключ с телом и иначе отвечает 409.
      final edited = fresh()
          .freezeCreate(normUuid: 'norm-1')
          .copyWith(comment: 'течь сальника, заменил');

      expect(edited.comment, 'течь сальника, заменил');
      expect(edited.createComment, 'течь сальника');
    });

    test('комментарий не менялся после создания — правка не нужна', () {
      expect(
        fresh().freezeCreate(normUuid: null).commentChangedSinceCreate,
        isFalse,
      );
    });

    test('комментарий поправили после создания — уходит правкой', () {
      final edited =
          fresh().freezeCreate(normUuid: null).copyWith(comment: 'заменил');

      expect(edited.commentChangedSinceCreate, isTrue);
    });

    test('черновик прошлой версии: очищенный комментарий тоже уходит', () {
      // Ремонт уже создан, а с каким комментарием — неизвестно (тело не
      // фиксировалось). Пустой текущий — не «без изменений»: иначе на
      // сервере остался бы прежний текст.
      final legacy = PendingRepair(
        localId: 'local-3',
        equipmentUuid: 'eq-1',
        equipmentName: 'Насос',
        startedAt: DateTime.utc(2026, 10, 24, 9),
        createdAt: DateTime.utc(2026, 10, 24, 9),
        comment: '',
        serverUuid: 'srv-1',
      );

      expect(legacy.isCreateFrozen, isFalse);
      expect(legacy.commentChangedSinceCreate, isTrue);
    });

    test('очистили зафиксированный комментарий — уходит правкой', () {
      final cleared =
          fresh().freezeCreate(normUuid: null).copyWith(comment: '');

      expect(cleared.commentChangedSinceCreate, isTrue);
    });

    test('отказ и его снятие тело не теряют', () {
      final frozen = fresh().freezeCreate(normUuid: 'norm-1');

      final rejected = frozen.markRejected(reason: 'нет прав');
      final cleared = rejected.clearRejection();

      expect(rejected.createComment, 'течь сальника');
      expect(cleared.createComment, 'течь сальника');
      expect(cleared.createNormUuid, 'norm-1');
    });
  });

  group('toRepair', () {
    test('черновик отличим от серверного ремонта', () {
      final repair = rejectedDraft().toRepair();

      expect(repair.id, 0);
      expect(repair.uuid, isEmpty);
      expect(repair.status, RepairStatuses.open);
    });
  });
}
