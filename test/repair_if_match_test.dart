import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/model/repair_conflict.dart';
import 'package:qr_scan_industry/src/repairs/repair_edit_base.dart';

/// If-Match для правки ремонта (бэкенд `d22727e`, решение 22.11): ETag
/// берётся при открытии карточки со связью, 412 кладёт правку в «Не
/// отправлено» с тем, что на сервере сейчас. Ошибка здесь — либо тихо
/// затёртая чужая правка, либо вечный конфликт на ровном месте.
void main() {
  const baseState = '{"uuid":"r-1","updated_at":"2026-11-22T10:00:00Z",'
      '"status":"open","comment":"Было","actual_consumptions":'
      '[{"spare_part_uuid":"sp-1","quantity":2.0}]}';

  PendingRepairUpdate update({String? etag = 'W/"e1"', String? state}) =>
      PendingRepairUpdate(
        repairUuid: 'r-1',
        repairId: 7,
        equipmentName: 'Насос',
        baseStatus: 'open',
        createdAt: DateTime.utc(2026, 11, 22),
        comment: 'Заменил подшипник',
        consumptions: [
          RepairConsumption(
            sparePartUuid: 'sp-1',
            sparePartName: 'Подшипник',
            quantity: 2,
          ),
        ],
        mutationKey: 'k-1',
        requestBody: '{"comment":"Заменил подшипник"}',
        baseEtag: etag,
        baseState: state ?? baseState,
      );

  group('разбор 412', () {
    const body = '{"detail":{"code":"stale_revision","message":"Данные '
        'изменились. Обновите их перед сохранением.","current":{"status":'
        '"under_review","comment":"Админ"},"current_etag":"W/\\"e2\\""}}';

    test('состояние и ETag из ответа', () {
      final error = StaleRevisionException.fromResponse(412, body)!;
      expect(error.statusCode, 412);
      expect(error.errorCode, StaleRevisionException.code);
      expect(error.current['status'], 'under_review');
      expect(error.currentEtag, 'W/"e2"');
      expect(error.toString(), contains('Данные изменились'));
    });

    test('другой код, другой статус или без состояния — не 412 правки', () {
      expect(StaleRevisionException.fromResponse(409, body), isNull);
      expect(
        StaleRevisionException.fromResponse(
            412, '{"detail":"Ревизия ППР изменилась"}'),
        isNull,
      );
      expect(
        StaleRevisionException.fromResponse(
          412,
          '{"detail":{"code":"stale_revision","current_etag":"x"}}',
        ),
        isNull,
      );
      expect(StaleRevisionException.fromResponse(412, 'не json'), isNull);
    });
  });

  group('сдвинулось только время', () {
    Map<String, dynamic> current() =>
        Map<String, dynamic>.from(jsonDecode(baseState) as Map);

    test('другой updated_at и порядок полей — то же состояние', () {
      final moved = current()..['updated_at'] = '2026-11-22T10:05:00Z';
      final reordered = {
        for (final key in moved.keys.toList().reversed) key: moved[key],
      };
      expect(isSameRepairEditState(baseState, reordered), isTrue);
    });

    test('чужая правка — уже не то же', () {
      expect(
        isSameRepairEditState(baseState, current()..['comment'] = 'Админ'),
        isFalse,
      );
      expect(
        isSameRepairEditState(baseState, current()..['status'] = 'closed'),
        isFalse,
      );
      final consumption = current()
        ..['actual_consumptions'] = [
          {'spare_part_uuid': 'sp-1', 'quantity': 3.0},
        ];
      expect(isSameRepairEditState(baseState, consumption), isFalse);
    });

    test('основы нет или битая — считаем, что изменили', () {
      expect(isSameRepairEditState(null, current()), isFalse);
      expect(isSameRepairEditState('{', current()), isFalse);
    });
  });

  group('что на сервере сейчас', () {
    test('статус, комментарий и число позиций', () {
      final snapshot = repairServerSnapshot(baseState)!;
      expect(snapshot.status, 'open');
      expect(snapshot.comment, 'Было');
      expect(snapshot.consumptionCount, 1);
    });

    test('расход скрыт правами — без числа, мусор — ничего', () {
      final hidden =
          repairServerSnapshot({'status': 'open', 'actual_consumptions': null});
      expect(hidden!.consumptionCount, isNull);
      expect(hidden.comment, isEmpty);
      expect(repairServerSnapshot('{'), isNull);
      expect(repairServerSnapshot(42), isNull);
    });
  });

  group('правка в очереди', () {
    test('отказ 412 хранит, что на сервере, и не теряет основу', () {
      final rejected = update().markRejected(
        reason: 'Ремонт изменили',
        serverStatus: 'under_review',
        conflictKind: RepairConflictKind.changedOnServer.code,
        serverEtag: 'W/"e2"',
        serverState: '{"status":"under_review"}',
      );
      expect(rejected.kind, RepairConflictKind.changedOnServer);
      // Сам не уйдёт: «Повторить» не предлагается, решает обходчик.
      expect(rejected.kind.isFinal, isTrue);
      expect(rejected.baseEtag, 'W/"e1"');
      expect(rejected.serverEtag, 'W/"e2"');
      expect(
          rejected.copyWith(photoPaths: const ['a.jpg']).serverEtag, 'W/"e2"');
    });

    test('«Отправить мою правку» — новая основа, новый ключ, без отказа', () {
      final rejected = update().markRejected(
        reason: 'Ремонт изменили',
        conflictKind: RepairConflictKind.changedOnServer.code,
        serverEtag: 'W/"e2"',
        serverState: '{"status":"open"}',
      );
      final resent =
          rejected.rebased(etag: 'W/"e2"', state: '{"status":"open"}');
      expect(resent.isRejected, isFalse);
      expect(resent.baseEtag, 'W/"e2"');
      expect(resent.baseState, '{"status":"open"}');
      expect(resent.mutationKey, isNull);
      expect(resent.requestBody, isNull);
      expect(resent.serverEtag, isNull);
      expect(resent.comment, 'Заменил подшипник');
    });

    test('снятие отказа убирает чужое состояние, основу оставляет', () {
      final cleared = update()
          .markRejected(
            reason: 'x',
            serverEtag: 'W/"e2"',
            serverState: '{}',
          )
          .clearRejection();
      expect(cleared.serverEtag, isNull);
      expect(cleared.serverState, isNull);
      expect(cleared.baseEtag, 'W/"e1"');
    });

    test('поля ушли, запись осталась — без основы, ключ и снимки на месте', () {
      final kept =
          update().copyWith(photoPaths: const ['new.jpg']).withoutBase();
      expect(kept.baseEtag, isNull);
      expect(kept.baseState, isNull);
      // Та же форма — тот же ключ: сервер узнает повтор уже ушедших полей.
      expect(kept.mutationKey, 'k-1');
      expect(kept.requestBody, '{"comment":"Заменил подшипник"}');
      expect(kept.photoPaths, ['new.jpg']);
      expect(kept.comment, 'Заменил подшипник');
    });

    test('новая основа после нашей отправки — ключ и пометка на месте', () {
      final rebased = update(etag: null).withBase(etag: 'W/"e2"', state: '{}');
      expect(rebased.baseEtag, 'W/"e2"');
      expect(rebased.baseState, '{}');
      expect(rebased.mutationKey, 'k-1');
      expect(rebased.requestBody, isNotNull);
    });

    test('фиксация ключа основу не трогает', () {
      final frozen = update().frozen(key: 'k-2', body: '{}');
      expect(frozen.baseEtag, 'W/"e1"');
      expect(frozen.baseState, baseState);
    });
  });

  group('ETag того же снимка (ревью 25.11)', () {
    Repair repair({
      String status = 'open',
      String? comment = 'Было',
      double qty = 2,
    }) =>
        Repair(
          id: 7,
          uuid: 'r-1',
          status: status,
          equipmentUuid: 'e-1',
          equipmentName: 'Насос',
          createdAt: DateTime.utc(2026, 11, 25),
          startedAt: DateTime.utc(2026, 11, 25),
          comment: comment,
          actualConsumptions: [
            RepairConsumption(
              sparePartUuid: 'sp-1',
              sparePartName: 'П',
              quantity: qty,
            ),
          ],
        );
    const state = '{"status":"open","comment":"Было",'
        '"actual_consumptions":[{"spare_part_uuid":"sp-1","quantity":"2.000"}]}';

    test('тот же ремонт — совпадает, расход сверяется числом', () {
      expect(editStateMatchesRepair(state, repair()), isTrue);
    });

    test('админ поменял расход, комментарий или статус — не совпадает', () {
      expect(editStateMatchesRepair(state, repair(qty: 3)), isFalse);
      expect(editStateMatchesRepair(state, repair(comment: 'Иначе')), isFalse);
      expect(editStateMatchesRepair(state, repair(status: 'closed')), isFalse);
      expect(editStateMatchesRepair('', repair()), isFalse);
    });

    test('расход скрыт правами — сверяются статус и комментарий', () {
      expect(
        editStateMatchesRepair(
          '{"status":"open","comment":"Было","actual_consumptions":null}',
          repair(qty: 9),
        ),
        isTrue,
      );
    });

    test('после нашей отправки — совпадает с отправленным', () {
      final consumptions = [
        RepairConsumption(
            sparePartUuid: 'sp-1', sparePartName: 'П', quantity: 2),
      ];
      expect(
        editStateMatchesSentEdit(
          state,
          sentComment: 'Было',
          sentConsumptions: consumptions,
          submitted: false,
        ),
        isTrue,
      );
      // Отправляли на проверку, а ремонт всё ещё «Открыт» — не наша версия.
      expect(
        editStateMatchesSentEdit(
          state,
          sentComment: 'Было',
          sentConsumptions: consumptions,
          submitted: true,
        ),
        isFalse,
      );
    });

    test('без If-Match — только если сервер edit-state не знает', () {
      expect(isEditStateUnsupported(ServerFailureException(404, 'x')), isTrue);
      expect(isEditStateUnsupported(ServerFailureException(405, 'x')), isTrue);
      // Временные сбои и обрыв связи — основа «неизвестна», а не пропадает.
      expect(isEditStateUnsupported(ServerFailureException(503, 'x')), isFalse);
      expect(isEditStateUnsupported(ServerFailureException(429, 'x')), isFalse);
      expect(
        isEditStateUnsupported(const SocketException('нет сети')),
        isFalse,
      );
    });

    group('откуда основа правки карточки', () {
      PendingRepairUpdate queued({
        String comment = 'Было',
        double qty = 2,
        bool submit = false,
        String? baseEtag,
      }) =>
          PendingRepairUpdate(
            repairUuid: 'r-1',
            repairId: 7,
            equipmentName: 'Насос',
            baseStatus: 'open',
            createdAt: DateTime.utc(2026, 11, 25),
            comment: comment,
            consumptions: [
              RepairConsumption(
                sparePartUuid: 'sp-1',
                sparePartName: 'П',
                quantity: qty,
              ),
            ],
            submitForReview: submit,
            photoPaths: const ['a.jpg'],
            baseEtag: baseEtag,
          );

      test('очередь пуста — ETag карточки, сохранение ждёт его', () {
        expect(
          editBaseSource(queued: null, formSource: repair()),
          EditBaseSource.card,
        );
      });

      test('в очереди только снимки (поля как на сервере) — тоже карточки', () {
        expect(
          editBaseSource(queued: queued(), formSource: repair()),
          EditBaseSource.card,
        );
      });

      test('у правки в очереди своя основа — её', () {
        expect(
          editBaseSource(
            queued: queued(comment: 'Новое', baseEtag: 'W/"e1"'),
            formSource: repair(),
          ),
          EditBaseSource.queued,
        );
      });

      test('после 412 — состояние, которое обходчик видел', () {
        final rejected = queued(baseEtag: 'W/"e1"').markRejected(
          reason: 'x',
          conflictKind: RepairConflictKind.changedOnServer.code,
          serverEtag: 'W/"e2"',
          serverState: '{}',
        );
        expect(
          editBaseSource(queued: rejected, formSource: repair()),
          EditBaseSource.serverConflict,
        );
      });

      test('правка без связи и без основы — без If-Match', () {
        expect(
          editBaseSource(
            queued: queued(comment: 'Новое'),
            formSource: repair(),
          ),
          EditBaseSource.none,
        );
        expect(
          editBaseSource(queued: queued(submit: true), formSource: repair()),
          EditBaseSource.none,
        );
      });
    });

    test('версии ремонта сравниваются по полям правки', () {
      expect(sameEditableFields(repair(), repair()), isTrue);
      expect(sameEditableFields(repair(), repair(qty: 3)), isFalse);
      expect(sameEditableFields(repair(), repair(comment: 'Иначе')), isFalse);
      expect(sameEditableFields(repair(), repair(status: 'closed')), isFalse);
      // Нулевые позиции на сервер не уходят — не различие.
      expect(sameEditableFields(repair(qty: 0), repair(qty: 0)), isTrue);
    });

    test('неизвестная основа не совпадёт ни с каким состоянием', () {
      expect(isSameRepairEditState('', const {'status': 'open'}), isFalse);
      expect(unknownBaseEtag, startsWith('"'));
    });
  });

  group('хранение', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('repair_if_match');
      Hive.init(dir.path);
      Hive.registerAdapter(RepairConsumptionAdapter(), override: true);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('основа и состояние сервера переживают запись и чтение', () async {
      Hive.registerAdapter(PendingRepairUpdateAdapter(), override: true);
      final box = await Hive.openBox<PendingRepairUpdate>('if_match');
      await box.put(
        'r-1',
        update().markRejected(
          reason: 'x',
          serverEtag: 'W/"e2"',
          serverState: '{"status":"closed"}',
        ),
      );
      await box.close();
      final stored =
          (await Hive.openBox<PendingRepairUpdate>('if_match')).get('r-1')!;
      expect(stored.baseEtag, 'W/"e1"');
      expect(stored.baseState, baseState);
      expect(stored.serverEtag, 'W/"e2"');
      expect(stored.serverState, '{"status":"closed"}');
      expect(stored.mutationKey, 'k-1');
      await Hive.box<PendingRepairUpdate>('if_match').close();
    });

    test('правка прошлой версии читается без основы', () async {
      Hive.registerAdapter(_PreviousAdapter(), override: true);
      final box = await Hive.openBox<PendingRepairUpdate>('if_match_old');
      await box.put('r-1', update());
      await box.close();
      Hive.registerAdapter(PendingRepairUpdateAdapter(), override: true);
      final stored =
          (await Hive.openBox<PendingRepairUpdate>('if_match_old')).get('r-1')!;
      expect(stored.requestBody, '{"comment":"Заменил подшипник"}');
      expect(stored.baseEtag, isNull);
      expect(stored.serverState, isNull);
    });
  });
}

/// Адаптер до `d22727e`: те же поля без основы и состояния сервера.
class _PreviousAdapter extends PendingRepairUpdateAdapter {
  @override
  void write(BinaryWriter writer, PendingRepairUpdate obj) {
    writer.write(obj.repairUuid);
    writer.write(obj.repairId);
    writer.write(obj.equipmentName);
    writer.write(obj.comment);
    writer.write(obj.consumptions);
    writer.write(obj.submitForReview);
    writer.write(obj.baseStatus);
    writer.write(obj.createdAt);
    writer.write(obj.lastError);
    writer.write(obj.serverStatus);
    writer.write(obj.conflictKind);
    writer.write(obj.photoPaths);
    writer.write(obj.deletedPhotoUuids);
    writer.write(obj.ownerUuid);
    writer.write(obj.ownerServer);
    writer.write(obj.mutationKey);
    writer.write(obj.requestBody);
  }
}
