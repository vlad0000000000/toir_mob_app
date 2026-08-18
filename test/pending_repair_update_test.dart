import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/repair_conflict.dart';

/// Переходы состояния неотправленной правки ремонта.
///
/// Ключ бокса — `repairUuid`, то есть запись по ремонту ровно одна, и любая
/// перезапись «с нуля» стирала бы то, что уже накопилось. Раньше `copyWith`
/// вдобавок сбрасывал пометку об отказе, если её не передали, — и работа с
/// фотографиями снимала неразрешённый конфликт.
void main() {
  PendingRepairUpdate rejected() => PendingRepairUpdate(
        repairUuid: 'r-1',
        repairId: 128,
        equipmentName: 'Насос',
        baseStatus: 'open',
        createdAt: DateTime.utc(2026, 8, 18, 10),
        comment: 'заменил подшипник',
        submitForReview: true,
        lastError: 'Ремонт уже закрыт',
        serverStatus: 'closed',
        conflictKind: RepairConflictKind.repairClosed.code,
        photoPaths: const ['a.jpg'],
        deletedPhotoUuids: const ['p-1'],
      );

  group('copyWith', () {
    test('не снимает пометку об отказе и не теряет конфликт', () {
      final next = rejected().copyWith(photoPaths: const ['a.jpg', 'b.jpg']);

      expect(next.isRejected, isTrue);
      expect(next.lastError, 'Ремонт уже закрыт');
      expect(next.serverStatus, 'closed');
      expect(next.kind, RepairConflictKind.repairClosed);
      expect(next.photoPaths, ['a.jpg', 'b.jpg']);
      expect(next.deletedPhotoUuids, ['p-1']);
    });

    test('не трогает то, что не передали', () {
      final next = rejected().copyWith(comment: 'дописал');

      expect(next.comment, 'дописал');
      expect(next.submitForReview, isTrue);
      expect(next.baseStatus, 'open');
    });
  });

  group('markRejected', () {
    test('ставит причину и вид конфликта', () {
      final next = rejected().clearRejection().markRejected(
            reason: 'Нет доступа к этому ремонту',
            serverStatus: 'open',
            conflictKind: RepairConflictKind.repairReassigned.code,
          );

      expect(next.isRejected, isTrue);
      expect(next.kind, RepairConflictKind.repairReassigned);
      expect(next.photoPaths, ['a.jpg']);
    });
  });

  group('clearRejection', () {
    test('снимает отказ, оставляя фотографическую работу', () {
      final next = rejected().clearRejection();

      expect(next.isRejected, isFalse);
      expect(next.serverStatus, isNull);
      expect(next.kind, RepairConflictKind.other);
      expect(next.photoPaths, ['a.jpg']);
      expect(next.deletedPhotoUuids, ['p-1']);
      expect(next.hasPhotoWork, isTrue);
    });
  });

  group('isStatusConflict', () {
    test('расхождение статусов и есть конфликт', () {
      expect(rejected().isStatusConflict, isTrue);
      // baseStatus задаётся первой правкой; подмена его свежим серверным
      // статусом стирала бы сам признак.
      expect(rejected().clearRejection().isStatusConflict, isFalse);
    });
  });
}
