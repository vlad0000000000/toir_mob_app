import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/model/scan.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

/// Прежняя формулировка «оборудование не найдено» — так её сохранила в
/// очереди версия `8e742ed`. Копия намеренная: тест должен падать, если
/// словарь перестанет её узнавать.
const _legacyEquipmentNotFound =
    'Сервер не нашёл это оборудование: его удалили или оно в другом '
    'подразделении, куда у вас нет доступа. Обратитесь к администратору.';

Scan _rejected(String equipmentUuid, String reason) => Scan(
      resultStatus: 'closed',
      equipmentUuid: equipmentUuid,
      files: const [],
      createdAt: '2026-10-24T10:00:00Z',
      eventId: 'evt-$equipmentUuid',
      lastError: reason,
    );

/// Смена доступа (`retryNoRightsRejections`) возвращает в отправку осмотры,
/// отклонённые по доступу, — в том числе с причиной, сохранённой прежними
/// словами. Иначе после выкладки бэкенда `06b145f` такой осмотр оставался бы
/// отклонённым до ручного повтора.
void main() {
  late Directory dir;

  setUpAll(() {
    Hive.registerAdapter(ScanAdapter(), override: true);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('retry_access');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
      '«оборудование не найдено» любыми словами и «нет прав» — в отправку, '
      'прочие отказы остаются', () async {
    final scans = {
      'legacy-ru': _rejected('eq-1', _legacyEquipmentNotFound),
      'current-ru': _rejected('eq-2', ScanQueueStrings.errorEquipmentNotFound),
      'server-en': _rejected('eq-3', 'Equipment not found [HTTP 404]'),
      'no-rights': _rejected('eq-4', ScanQueueStrings.errorNoRights),
      'stock': _rejected('eq-5', ScanQueueStrings.errorInsufficientStock),
    };
    final box = await Hive.openBox<Scan>('scans');
    for (final scan in scans.values) {
      await box.put(scan.key(), scan);
    }
    final provider = await testDataProvider();
    expect(provider.rejectedScansCount.value, 5);

    final cleared = await provider.retryNoRightsRejections();

    expect(cleared, 4);
    Scan stored(String name) => provider.scanBox.get(scans[name]!.key())!;
    for (final name in ['legacy-ru', 'current-ru', 'server-en', 'no-rights']) {
      expect(stored(name).isRejected, isFalse, reason: name);
    }
    expect(stored('stock').isRejected, isTrue);
    expect(provider.rejectedScansCount.value, 1);
  });
}
