import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';
import 'package:qr_scan_industry/src/qr/scan_error_messages.dart';
import 'package:qr_scan_industry/src/repairs/repair_error_messages.dart';
import 'package:qr_scan_industry/src/utils/idempotency_key.dart';
import 'package:qr_scan_industry/src/utils/offline_error.dart';
import 'package:qr_scan_industry/strings.dart';

/// Ключи повторов (бэкенд `81f644c`): правка ремонта, показание наработки,
/// смена состояния. Ошибиться дорого в обе стороны: ключ, потерянный между
/// попытками, применит правку дважды («На рассмотрение» уйдёт второй раз и
/// упрётся в конфликт), а ключ, переживший смену данных, получит 409.
void main() {
  RepairConsumption item(String uuid, double quantity) => RepairConsumption(
        sparePartUuid: uuid,
        sparePartName: 'ЗИП $uuid',
        quantity: quantity,
      );

  PendingRepairUpdate update({
    String comment = 'Заменил подшипник',
    bool submit = true,
    String? key,
    String? body,
  }) =>
      PendingRepairUpdate(
        repairUuid: 'r-1',
        repairId: 7,
        equipmentName: 'Насос',
        baseStatus: 'open',
        createdAt: DateTime.utc(2026, 11, 18),
        comment: comment,
        consumptions: [item('sp-1', 2)],
        submitForReview: submit,
        mutationKey: key,
        requestBody: body,
      );

  group('ключи', () {
    test('новый ключ — 32 hex и каждый раз другой', () {
      final keys = {for (var i = 0; i < 100; i++) newIdempotencyKey()};
      expect(keys.length, 100);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(keys.first), isTrue);
    });

    test('ключ шага черновика — тот же у того же тела, другой у другого', () {
      final a = repairFinishKey('local-1', '{"comment":"a"}');
      expect(repairFinishKey('local-1', '{"comment":"a"}'), a);
      expect(repairFinishKey('local-1', '{"comment":"b"}'), isNot(a));
      expect(repairFinishKey('local-2', '{"comment":"a"}'), isNot(a));
      expect(a.length, lessThanOrEqualTo(255));
    });
  });

  group('тело правки ремонта', () {
    test('поля обходчика, нулевые позиции не уходят', () {
      final body = jsonDecode(repairUpdateBody(
        comment: 'Готово',
        consumptions: [item('sp-1', 2), item('sp-2', 0)],
        submitForReview: true,
      ));
      expect(body, {
        'comment': 'Готово',
        'actual_consumptions': [
          {'spare_part_uuid': 'sp-1', 'quantity': 2.0},
        ],
        'status': 'under_review',
      });
    });

    test('без комментария и отправки — только расход', () {
      final body = jsonDecode(repairUpdateBody(consumptions: const []));
      expect(body, {'actual_consumptions': []});
    });

    test('то же — байт в байт', () {
      String build() => repairUpdateBody(
            comment: 'x',
            consumptions: [item('sp-1', 1.5)],
            submitForReview: true,
          );
      expect(build(), build());
    });
  });

  group('правка ремонта в очереди', () {
    test('фиксация ключа и тела', () {
      final frozen = update().frozen(key: 'k-1', body: '{"comment":"x"}');
      expect(frozen.mutationKey, 'k-1');
      expect(frozen.requestBody, '{"comment":"x"}');
      expect(frozen.comment, 'Заменил подшипник');
    });

    test('ход отправки снимков и отказ ключ не трогают', () {
      final frozen = update(key: 'k-1', body: 'b');
      expect(frozen.copyWith(photoPaths: const ['p']).mutationKey, 'k-1');
      final rejected = frozen.markRejected(reason: 'Нет связи');
      expect(rejected.mutationKey, 'k-1');
      expect(rejected.requestBody, 'b');
      expect(rejected.clearRejection().mutationKey, 'k-1');
    });

    test('новые поля формы — новый запрос, ключа нет', () {
      final frozen = update(key: 'k-1', body: 'b');
      expect(frozen.copyWith(comment: 'Другое').mutationKey, isNull);
      expect(frozen.copyWith(submitForReview: false).requestBody, isNull);
      expect(frozen.copyWith(consumptions: const []).mutationKey, isNull);
    });

    test('та же форма узнаётся, другая — нет', () {
      final queued = update();
      bool same(
              {String? comment,
              List<RepairConsumption>? items,
              bool? submit}) =>
          queued.sameFormAs(
            comment: comment ?? 'Заменил подшипник',
            consumptions: items ?? [item('sp-1', 2)],
            submitForReview: submit ?? true,
          );
      expect(same(), isTrue);
      expect(same(comment: 'x'), isFalse);
      expect(same(submit: false), isFalse);
      expect(same(items: [item('sp-1', 3)]), isFalse);
      expect(same(items: [item('sp-2', 2)]), isFalse);
      expect(same(items: const []), isFalse);
    });
  });

  group('разбор отказов', () {
    test('код отказа — сверху или внутри detail', () {
      expect(serverErrorCode('{"code":"already_taken","detail":"x"}'),
          'already_taken');
      expect(
        serverErrorCode(jsonEncode({
          'detail': {
            'code': idempotencyKeyInProgressCode,
            'message': 'Запрос ещё обрабатывается.',
          },
        })),
        idempotencyKeyInProgressCode,
      );
      expect(serverErrorCode('{"detail":"Repair not found"}'), isNull);
      expect(serverErrorCode('<html>502</html>'), isNull);
    });

    test('«ещё обрабатывается» — повтор, «другое тело» — окончательно', () {
      final inProgress = ServerFailureException(409, 'Ещё обрабатывается',
          errorCode: idempotencyKeyInProgressCode);
      final conflict = ServerFailureException(409, 'Другой запрос',
          errorCode: idempotencyKeyConflictCode);
      expect(inProgress.isTransient, isTrue);
      expect(isRetryableRepairError(inProgress), isTrue);
      expect(isRetryableScanError(inProgress), isTrue);

      expect(conflict.isTransient, isFalse);
      expect(conflict.isIdempotencyConflict, isTrue);
      expect(isRetryableRepairError(conflict), isFalse);
      expect(isRetryableScanError(conflict), isFalse);
      expect(repairErrorMessage(conflict), repairKeyConflictMessage);
      expect(scanErrorMessage(conflict), ScanQueueStrings.errorKeyConflict);
    });

    test('прочие 409 без кода — прежний разбор', () {
      final plain = ServerFailureException(409, 'Оборудование уже в ремонте');
      expect(plain.isTransient, isFalse);
      expect(plain.isIdempotencyConflict, isFalse);
    });

    test('ответ мог потеряться — таймаут и обрыв, но не «нет адреса»', () {
      expect(isLostResponseError(TimeoutException('ждали')), isTrue);
      expect(
        isLostResponseError(
            Exception('Failed: Connection closed before full header')),
        isTrue,
      );
      expect(
        isLostResponseError(const SocketException('Failed host lookup')),
        isFalse,
      );
      expect(
        isLostResponseError(const SocketException('Connection refused')),
        isFalse,
      );
    });
  });

  group('хранение', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('idempotency_keys');
      Hive.init(dir.path);
      Hive.registerAdapter(RepairConsumptionAdapter(), override: true);
      Hive.registerAdapter(PendingRepairUpdateAdapter(), override: true);
      Hive.registerAdapter(UsageUpdateAdapter(), override: true);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('ключ и тело правки ремонта переживают запись и чтение', () async {
      final box = await Hive.openBox<PendingRepairUpdate>('updates_keys');
      await box.put('r-1', update(key: 'k-1', body: '{"comment":"x"}'));
      await box.close();
      final stored =
          (await Hive.openBox<PendingRepairUpdate>('updates_keys')).get('r-1')!;
      expect(stored.mutationKey, 'k-1');
      expect(stored.requestBody, '{"comment":"x"}');
      expect(stored.consumptions.single.quantity, 2);
    });

    test('ключ показания переживает запись и не меняет ключ записи', () async {
      UsageUpdate sample() => UsageUpdate(
            usageParameterUuid: 'param-1',
            usageParameterValue: 1250.5,
            equipmentUuid: 'eq-1',
          );
      final keyed = sample()..eventId = 'evt-1';
      expect(keyed.key(), sample().key());
      expect(keyed.toJson().containsKey('event_id'), isFalse);

      final box = await Hive.openBox<UsageUpdate>('usage_keys');
      await box.put(keyed.key(), keyed);
      await box.close();
      final stored =
          (await Hive.openBox<UsageUpdate>('usage_keys')).get(keyed.key())!;
      expect(stored.eventId, 'evt-1');
      expect(stored.usageParameterValue, 1250.5);
    });
  });
}
