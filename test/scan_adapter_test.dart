import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/model/scan.dart';

/// Адаптер осмотра до появления [Scan.eventId] и [Scan.usageKeys] — ровно
/// тот формат, что лежит в очередях на устройствах с прошлой версией.
class _LegacyScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2;

  @override
  Scan read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, Scan obj) {
    writer.write(obj.files);
    writer.write(obj.periodicTaskUuid);
    writer.write(obj.equipmentUuid);
    writer.write(obj.resultStatus);
    writer.write(obj.comment);
    writer.write(obj.faultUuid);
    writer.write(obj.taskUuid);
    writer.write(obj.priority);
    writer.write(obj.createdAt);
    writer.write(obj.closedAt);
    writer.write(obj.isOtherFault);
    writer.write(obj.actualConsumptions);
    writer.write(obj.lastError);
    writer.write(obj.lastShortages);
    writer.write(obj.consumptionNames);
  }
}

/// Рукописный адаптер осмотра: новые поля дописаны в конец, и в очереди на
/// устройствах лежат записи и с ними, и без них. Ошибка здесь — потерянные
/// неотправленные осмотры, поэтому проверяем обе стороны.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scan_hive');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    Hive.resetAdapters();
    await dir.delete(recursive: true);
  });

  Scan sample(
          {String? eventId, List<String>? usageKeys, String? usageUpdates}) =>
      Scan(
        resultStatus: 'closed',
        equipmentUuid: 'eq-1',
        comment: 'Наработка: 1250 м/ч',
        taskUuid: '',
        faultUuid: '',
        periodicTaskUuid: '',
        files: const [],
        createdAt: '2026-10-17T10:00:00Z',
        closedAt: '2026-10-17T10:05:00Z',
        eventId: eventId,
        usageKeys: usageKeys,
        usageUpdates: usageUpdates,
      );

  test('ключ события и привязка к наработке переживают запись и чтение',
      () async {
    Hive.registerAdapter(ScanAdapter());
    final scan = sample(eventId: 'evt-1', usageKeys: ['u-1', 'u-2']);

    final box = await Hive.openBox<Scan>('scans');
    await box.put(scan.key(), scan);
    await box.close();
    final stored = (await Hive.openBox<Scan>('scans')).get(scan.key())!;

    expect(stored.eventId, 'evt-1');
    expect(stored.usageKeys, ['u-1', 'u-2']);
    expect(stored.comment, 'Наработка: 1250 м/ч');
  });

  test('запись прошлой версии читается без новых полей', () async {
    Hive.registerAdapter(_LegacyScanAdapter());
    final old = sample();
    final box = await Hive.openBox<Scan>('scans');
    await box.put(old.key(), old);
    await box.close();

    Hive.resetAdapters();
    Hive.registerAdapter(ScanAdapter());
    final stored = (await Hive.openBox<Scan>('scans')).get(old.key())!;

    expect(stored.eventId, isNull);
    expect(stored.usageKeys, isNull);
    expect(stored.equipmentUuid, 'eq-1');
    expect(stored.closedAt, '2026-10-17T10:05:00Z');
  });

  test('новые поля не меняют ключ и не уходят на сервер', () {
    final plain = sample();
    final linked = sample(eventId: 'evt-1', usageKeys: ['u-1']);

    expect(linked.key(), plain.key());
    expect(linked.toJson().containsKey('event_id'), isFalse);
    expect(linked.toJson().containsKey('usage_keys'), isFalse);
  });

  test('копия с расходом сохраняет ключ события и привязку', () {
    final scan = sample(eventId: 'evt-1', usageKeys: ['u-1']);
    final copy = scan.copyWithConsumption(
      actualConsumptions: null,
      consumptionNames: null,
    );

    expect(copy.eventId, 'evt-1');
    expect(copy.usageKeys, ['u-1']);
  });

  test('наработка в составе осмотра переживает запись и уходит полем формы',
      () async {
    Hive.registerAdapter(ScanAdapter());
    const usage = '[{"usage_parameter_uuid":"p-1","current_value":"1250.00"}]';
    final scan = sample(eventId: 'evt-1', usageUpdates: usage);

    final box = await Hive.openBox<Scan>('scans');
    await box.put(scan.key(), scan);
    await box.close();
    final stored = (await Hive.openBox<Scan>('scans')).get(scan.key())!;

    expect(stored.usageUpdates, usage);
    expect(stored.toJson()['usage_updates'], usage);
    // В ключ не входит: та же запись без наработки — тот же ключ.
    expect(stored.key(), sample().key());
    expect(
      stored
          .copyWithConsumption(actualConsumptions: null, consumptionNames: null)
          .usageUpdates,
      usage,
    );
  });

  test('ключи событий уникальны', () {
    final ids = {for (var i = 0; i < 100; i++) Scan.newEventId()};
    expect(ids.length, 100);
    expect(ids.first.length, 32);
  });
}
