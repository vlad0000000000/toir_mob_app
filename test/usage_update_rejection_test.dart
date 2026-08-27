import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';

/// Пометка об отказе у наработки.
///
/// До неё у этой очереди не было понятия отказа вовсе: любая ошибка возвращала
/// запись в бокс, и невыполнимый запрос крутился в ней вечно. Хуже того,
/// закрытие задачи ТО намеренно ждёт наработку по тому же оборудованию — и
/// зависало вместе с ней навсегда, вместе со списанием ЗИП.
///
/// Два инварианта, которые тут и закрепляются: поле переживает запись в Hive
/// (адаптер рукописный, новое поле дописано в конец) и **не меняет ключ**
/// записи. Ключ — идентификатор в боксе: сдвинься он, и уже поставленную в
/// очередь наработку не нашли бы ни для удаления, ни для повтора.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('usage_update_hive');
    Hive.init(dir.path);
    Hive.registerAdapter(UsageUpdateAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  UsageUpdate sample() => UsageUpdate(
        usageParameterUuid: 'param-1',
        usageParameterValue: 1250.5,
        equipmentUuid: 'eq-1',
      );

  test('ключ не зависит от пометки об отказе', () {
    final clean = sample();
    final rejected = sample()..lastError = 'Значение меньше предыдущего';

    expect(rejected.key(), clean.key());
    // И в теле ключа пометки нет — она не часть формата.
    expect(clean.toJson().containsKey('last_error'), isFalse);
    expect(rejected.toJson().containsKey('last_error'), isFalse);
  });

  test('пометка переживает запись и чтение', () async {
    final usage = sample()..lastError = 'Параметр наработки не найден';

    final box = await Hive.openBox<UsageUpdate>('usage_rejected');
    await box.put(usage.key(), usage);
    // Закрываем и открываем заново: иначе вернулся бы объект из памяти, а не
    // разобранный адаптером.
    await box.close();
    final reopened = await Hive.openBox<UsageUpdate>('usage_rejected');
    final stored = reopened.get(usage.key())!;

    expect(stored.usageParameterUuid, 'param-1');
    expect(stored.usageParameterValue, 1250.5);
    expect(stored.equipmentUuid, 'eq-1');
    expect(stored.lastError, 'Параметр наработки не найден');
    expect(stored.isRejected, isTrue);
    // Ключ восстановленной записи обязан совпасть с исходным — иначе очередь
    // не нашла бы её в боксе.
    expect(stored.key(), usage.key());

    await reopened.close();
  });

  test('запись без пометки читается как неотклонённая', () async {
    final usage = sample();

    final box = await Hive.openBox<UsageUpdate>('usage_clean');
    await box.put(usage.key(), usage);
    await box.close();
    final reopened = await Hive.openBox<UsageUpdate>('usage_clean');
    final stored = reopened.get(usage.key())!;

    expect(stored.lastError, isNull);
    expect(stored.isRejected, isFalse);
    // Пустая строка тоже не считается отказом: очередь ориентируется на
    // `isRejected`, и «отклонена без причины» было бы тупиком.
    stored.lastError = '';
    expect(stored.isRejected, isFalse);

    await reopened.close();
  });
}
