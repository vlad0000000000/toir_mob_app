import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/sync_report.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/repairs/repair_delivery.dart';
import 'package:qr_scan_industry/strings.dart';

/// Прод, 19.11: «Не все ремонты отправлены», а в «Ремонтах» — «Ремонтов нет».
/// Отправка на проверку дошла, ответ потерялся, повтор получил «ремонт не
/// открыт» — запись помечалась отклонённой и пряталась навсегда.
void main() {
  RepairConsumption item(String uuid, double quantity) => RepairConsumption(
        sparePartUuid: uuid,
        sparePartName: 'ЗИП $uuid',
        quantity: quantity,
      );

  Repair server({
    String status = 'under_review',
    String? comment = 'Заменил подшипник',
    List<RepairConsumption>? consumptions,
  }) =>
      Repair(
        id: 7,
        uuid: 'r-1',
        status: status,
        equipmentUuid: 'eq-1',
        equipmentName: 'Насос',
        createdAt: DateTime.utc(2026, 11, 19),
        startedAt: DateTime.utc(2026, 11, 19),
        comment: comment,
        actualConsumptions: consumptions ?? [item('sp-1', 2)],
      );

  bool delivered({
    bool submit = true,
    Repair? repair,
    String? comment = 'Заменил подшипник',
    List<RepairConsumption>? consumptions,
  }) =>
      isSubmissionDelivered(
        submitForReview: submit,
        server: repair ?? server(),
        comment: comment,
        consumptions: consumptions ?? [item('sp-1', 2)],
      );

  group('отправка на проверку уже дошла', () {
    test('«На рассмотрении» ровно с правкой обходчика — дошла', () {
      expect(delivered(), isTrue);
    });

    test('без «Отправить на проверку» — не считается', () {
      expect(delivered(submit: false), isFalse);
    });

    test('ремонт не «На рассмотрении» или не перечитан — не считается', () {
      expect(delivered(repair: server(status: 'closed')), isFalse);
      expect(delivered(repair: server(status: 'open')), isFalse);
      expect(
        isSubmissionDelivered(
          submitForReview: true,
          server: null,
          comment: null,
          consumptions: null,
        ),
        isFalse,
      );
    });

    test('на рассмотрение перевёл кто-то другой — данные не совпали', () {
      expect(delivered(comment: 'Другой текст'), isFalse);
      expect(delivered(consumptions: [item('sp-1', 3)]), isFalse);
      expect(delivered(consumptions: [item('sp-2', 2)]), isFalse);
      expect(delivered(consumptions: const []), isFalse);
    });

    test('комментарий или расход не уходили — их не сверяем', () {
      expect(delivered(comment: null), isTrue);
      expect(
        isSubmissionDelivered(
          submitForReview: true,
          server: server(consumptions: [item('sp-9', 1)]),
          comment: 'Заменил подшипник',
          consumptions: null,
        ),
        isTrue,
      );
    });

    test('нулевые позиции на сервер не уходят — не мешают', () {
      expect(
        delivered(consumptions: [item('sp-1', 2), item('sp-3', 0)]),
        isTrue,
      );
    });

    test('пробелы по краям комментария не отличие', () {
      expect(delivered(comment: '  Заменил подшипник \n'), isTrue);
    });
  });

  test('правка без ремонта открывается по своим данным', () {
    final update = PendingRepairUpdate(
      repairUuid: 'r-1',
      repairId: 7,
      equipmentName: 'Насос',
      baseStatus: 'open',
      createdAt: DateTime.utc(2026, 11, 19),
      comment: 'Заменил подшипник',
      consumptions: [item('sp-1', 2)],
      serverStatus: 'closed',
    );
    final repair = update.toRepair();
    expect(repair.uuid, 'r-1');
    expect(repair.id, 7);
    expect(repair.equipmentName, 'Насос');
    expect(repair.status, 'closed');
    expect(repair.comment, 'Заменил подшипник');
    expect(repair.actualConsumptions.single.quantity, 2);
    expect(repair.detailsLoaded, isTrue);
  });

  group('окно синхронизации', () {
    test('отклонённые ремонты — отказ, ведёт в «Ремонты»', () {
      final trouble = const SyncReport(repairsRejected: true).troubles.single;
      expect(trouble.title, DialogStrings.syncRepairsRejectedTitle);
      expect(trouble.rejected, isTrue);
      expect(trouble.opensRepairs, isTrue);
    });

    test('ждущие отправки — не отказ, тоже ведёт в «Ремонты»', () {
      final trouble = const SyncReport(repairsLeft: true).troubles.single;
      expect(trouble.title, DialogStrings.syncRepairsFailedTitle);
      expect(trouble.rejected, isFalse);
      expect(trouble.opensRepairs, isTrue);
    });

    test('осмотры в «Ремонты» не ведут', () {
      final trouble = const SyncReport(scansLeft: true).troubles.single;
      expect(trouble.opensRepairs, isFalse);
    });
  });
}
