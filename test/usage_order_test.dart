import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/usage_order.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';

/// Наработка в составе осмотра: формат поля `usage_updates` и порядок
/// показаний между двумя очередями.
void main() {
  group('usageUpdatesPayload', () {
    test('значение — строкой с двумя знаками', () {
      final payload = usageUpdatesPayload([
        UsageUpdate(usageParameterUuid: 'p-1', usageParameterValue: 1250),
        UsageUpdate(usageParameterUuid: 'p-2', usageParameterValue: 0.1 + 0.2),
      ])!;

      expect(jsonDecode(payload), [
        {'usage_parameter_uuid': 'p-1', 'current_value': '1250.00'},
        {'usage_parameter_uuid': 'p-2', 'current_value': '0.30'},
      ]);
    });

    test('один параметр — одна строка, берётся последнее значение', () {
      final payload = usageUpdatesPayload([
        UsageUpdate(usageParameterUuid: 'p-1', usageParameterValue: 10),
        UsageUpdate(usageParameterUuid: 'p-1', usageParameterValue: 12),
      ])!;

      expect(jsonDecode(payload), [
        {'usage_parameter_uuid': 'p-1', 'current_value': '12.00'},
      ]);
    });

    test('без значения или параметра — отправлять нечего', () {
      expect(
        usageUpdatesPayload([
          UsageUpdate(usageParameterUuid: 'p-1'),
          UsageUpdate(usageParameterValue: 5),
        ]),
        isNull,
      );
      expect(usageUpdatesPayload(const []), isNull);
    });

    test('округление до сотых', () {
      expect(roundUsageValue(1250.456), 1250.46);
      expect(roundUsageValue(7), 7);
    });
  });

  group('hasEarlierUsage', () {
    UsageOrderEntry entry(String equipment, String? createdAt) =>
        (equipmentUuid: equipment, createdAt: createdAt);

    const t1 = '2026-10-19T08:00:00.000Z';
    const t2 = '2026-10-19T09:00:00.000Z';

    test('более раннее показание по тому же оборудованию держит запись', () {
      expect(hasEarlierUsage(entry('eq-1', t2), [entry('eq-1', t1)]), isTrue);
    });

    test('более позднее — не держит: старое уходит первым', () {
      expect(hasEarlierUsage(entry('eq-1', t1), [entry('eq-1', t2)]), isFalse);
    });

    test('другое оборудование не держит', () {
      expect(hasEarlierUsage(entry('eq-1', t2), [entry('eq-2', t1)]), isFalse);
    });

    test('одна карточка — одно время, друг друга не держат', () {
      expect(hasEarlierUsage(entry('eq-1', t1), [entry('eq-1', t1)]), isFalse);
    });

    test('запись прошлой версии без времени считается самой ранней', () {
      expect(hasEarlierUsage(entry('eq-1', t1), [entry('eq-1', null)]), isTrue);
      // Две старые друг друга не держат — как и до появления правила.
      expect(
          hasEarlierUsage(entry('eq-1', null), [entry('eq-1', null)]), isFalse);
    });

    test('без оборудования ждать нечего', () {
      expect(
        hasEarlierUsage(
            (equipmentUuid: null, createdAt: t2), [entry('eq-1', t1)]),
        isFalse,
      );
    });
  });
}
