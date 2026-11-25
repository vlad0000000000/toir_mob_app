import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/repair_update_queue.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/model/repair_conflict.dart';
import 'package:qr_scan_industry/strings.dart';

/// Очередь правок ремонта после ответа сервера (ревью 23.11): итог запроса
/// ложится на запись из бокса, а не на отправленную копию. Ошибка здесь —
/// потерянная правка или снимок, которые обходчик добавил, пока шла
/// отправка, либо запись, которая вечно крутится в очереди.
void main() {
  PendingRepairUpdate edit({
    String comment = 'Заменил подшипник',
    bool submit = false,
    List<String> photos = const [],
    List<String> deleted = const [],
    String? baseEtag = 'W/"e1"',
  }) =>
      PendingRepairUpdate(
        repairUuid: 'r-1',
        repairId: 7,
        equipmentName: 'Насос',
        baseStatus: 'open',
        createdAt: DateTime.utc(2026, 11, 23),
        comment: comment,
        consumptions: [
          RepairConsumption(
            sparePartUuid: 'sp-1',
            sparePartName: 'Подшипник',
            quantity: 2,
          ),
        ],
        submitForReview: submit,
        photoPaths: photos,
        deletedPhotoUuids: deleted,
        mutationKey: 'k-1',
        requestBody: '{"comment":"x"}',
        baseEtag: baseEtag,
        baseState: baseEtag == null ? null : '{}',
      );

  group('та же правка', () {
    test('поля те же — та же правка, даже со снимками', () {
      expect(isSameQueuedEdit(edit(photos: const ['a.jpg']), edit()), isTrue);
    });

    test('комментарий или отправку поменяли — другая, записи нет — тоже', () {
      expect(isSameQueuedEdit(edit(comment: 'Другое'), edit()), isFalse);
      expect(isSameQueuedEdit(edit(submit: true), edit()), isFalse);
      expect(isSameQueuedEdit(null, edit()), isFalse);
    });
  });

  group('поля уже на сервере', () {
    test('запись не меняли — снять', () {
      final outcome = afterSentUpdate(edit(), edit())!;
      expect(outcome.delete, isTrue);
      expect(outcome.keep, isNull);
    });

    test('записи уже нет — делать нечего', () {
      expect(afterSentUpdate(null, edit()), isNull);
    });

    test('правку поменяли — остаётся новая, без прежней основы', () {
      final outcome = afterSentUpdate(edit(comment: 'Дописал'), edit())!;
      expect(outcome.delete, isFalse);
      expect(outcome.keep!.comment, 'Дописал');
      expect(outcome.keep!.baseEtag, isNull);
      expect(outcome.keep!.isRejected, isFalse);
    });

    test('сохранение, а снимки добавили — остаются ждать отправки', () {
      final outcome = afterSentUpdate(edit(photos: const ['new.jpg']), edit())!;
      expect(outcome.delete, isFalse);
      expect(outcome.keep!.photoPaths, ['new.jpg']);
      expect(outcome.keep!.isRejected, isFalse);
      // Та же форма — тот же ключ: повтор полей сервер узнает.
      expect(outcome.keep!.mutationKey, 'k-1');
    });

    test('отправка на проверку, а снимки добавили — отказ без повтора', () {
      final outcome = afterSentUpdate(
        edit(submit: true, photos: const ['new.jpg']),
        edit(submit: true),
      )!;
      final kept = outcome.keep!;
      expect(outcome.delete, isFalse);
      expect(kept.isRejected, isTrue);
      expect(kept.lastError, RepairCardStrings.photosAfterSubmit);
      expect(kept.serverStatus, RepairStatuses.underReview);
      expect(kept.kind, RepairConflictKind.photosRejected);
      // Окончательно: «Повторить» не предлагается.
      expect(kept.kind.isFinal, isTrue);
      expect(kept.photoPaths, ['new.jpg']);
    });
  });

  group('после загрузки снимков', () {
    test('ушедшее вычеркнуто, добавленное за время загрузки осталось', () {
      final sent = edit(photos: const ['a.jpg', 'b.jpg'], deleted: const ['x']);
      final stored = edit(
        photos: const ['a.jpg', 'b.jpg', 'c.jpg'],
        deleted: const ['x', 'y'],
      );
      final result = afterPhotoUpload(
        stored: stored,
        sent: sent,
        photosLeft: const ['b.jpg'],
        deletesLeft: const [],
      );
      expect(result.photoPaths, ['b.jpg', 'c.jpg']);
      expect(result.deletedPhotoUuids, ['y']);
    });

    test('правку поменяли за время загрузки — остаётся новая форма', () {
      final result = afterPhotoUpload(
        stored: edit(comment: 'Дописал', photos: const ['a.jpg']),
        sent: edit(photos: const ['a.jpg']),
        photosLeft: const [],
        deletesLeft: const [],
      );
      expect(result.comment, 'Дописал');
      expect(result.photoPaths, isEmpty);
    });

    test('ход загрузки ключ отправки не трогает', () {
      final result = afterPhotoUpload(
        stored: edit(photos: const ['a.jpg']),
        sent: edit(photos: const ['a.jpg']),
        photosLeft: const [],
        deletesLeft: const [],
      );
      expect(result.mutationKey, 'k-1');
      expect(result.baseEtag, 'W/"e1"');
    });
  });

  test('удаление отклонённой правки называет оборудование и последствия', () {
    final body = RepairCardStrings.deleteUnsentBody('Насос');
    expect(body, contains('«Насос»'));
    expect(body, contains('снимки'));
    expect(body, contains('ремонт на сервере не изменится'));
  });
}
