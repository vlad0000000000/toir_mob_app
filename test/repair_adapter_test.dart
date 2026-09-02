import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/model/repair.dart';

/// Запись и чтение ремонта через настоящий Hive.
///
/// Поводом стало новое поле `detailsLoaded` — отметка «карточка прочитана
/// целиком, а не взята из списка». Адаптеры в проекте написаны руками, поле
/// дописано в конец `write()` и читается через `try/catch`; ошибка здесь не
/// падает, а тихо подменяет значения соседних полей.
///
/// Чего этот тест не проверяет: чтение записи, сохранённой **прежней**
/// версией, — у неё поля в потоке нет. Двух адаптеров с одним `typeId` в одном
/// изоляте не зарегистрировать, поэтому старый формат не подделать. Запасной
/// путь (`_readDetailsLoaded`) восстанавливает отметку по содержимому записи.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('repair_hive');
    Hive.init(dir.path);
    Hive.registerAdapter(RepairAdapter());
    Hive.registerAdapter(RepairConsumptionAdapter());
    Hive.registerAdapter(RepairPhotoAdapter());
    Hive.registerAdapter(RepairNormItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Repair sample({required bool detailsLoaded}) => Repair(
        id: 867,
        uuid: 'repair-1',
        status: RepairStatuses.underReview,
        equipmentUuid: 'eq-1',
        equipmentName: 'Насос НМ-125',
        equipmentTypeModel: 'НМ-125/550',
        consumptionNormUuid: 'norm-1',
        consumptionNormName: 'ТО-1 насоса',
        createdAt: DateTime.utc(2026, 8, 18, 10),
        startedAt: DateTime.utc(2026, 8, 18, 10, 30),
        underReviewAt: DateTime.utc(2026, 8, 19, 9),
        duration: '2 дн 16 ч 4 мин',
        comment: 'заменил сальник',
        responsibleUserUuid: 'user-1',
        responsibleUserFullname: 'Козлов М. М.',
        actualConsumptions: [
          RepairConsumption(
            sparePartUuid: 'sp-1',
            sparePartName: 'Сальник 40×60',
            unitName: 'шт',
            quantity: 3,
            normQuantity: 2,
          ),
        ],
        photos: [RepairPhoto(uuid: 'ph-1', url: 'http://x/1.jpg', order: 0)],
        normItems: [
          RepairNormItem(
            sparePartUuid: 'sp-1',
            sparePartName: 'Сальник 40×60',
            quantity: 2,
          ),
        ],
        detailsLoaded: detailsLoaded,
      );

  Future<Repair> roundTrip(String boxName, Repair repair) async {
    final box = await Hive.openBox<Repair>(boxName);
    await box.put(repair.uuid, repair);
    // Закрываем и открываем заново: иначе вернулся бы объект из памяти, а не
    // разобранный адаптером.
    await box.close();
    final reopened = await Hive.openBox<Repair>(boxName);
    final stored = reopened.get(repair.uuid)!;
    await reopened.close();
    return stored;
  }

  test('ремонт переживает запись и чтение без перестановки полей', () async {
    final stored = await roundTrip('repairs_full', sample(detailsLoaded: true));

    expect(stored.id, 867);
    expect(stored.uuid, 'repair-1');
    expect(stored.status, RepairStatuses.underReview);
    expect(stored.equipmentName, 'Насос НМ-125');
    expect(stored.equipmentTypeModel, 'НМ-125/550');
    expect(stored.consumptionNormName, 'ТО-1 насоса');
    expect(stored.createdAt, DateTime.utc(2026, 8, 18, 10));
    expect(stored.startedAt, DateTime.utc(2026, 8, 18, 10, 30));
    expect(stored.underReviewAt, DateTime.utc(2026, 8, 19, 9));
    expect(stored.completedAt, isNull);
    expect(stored.duration, '2 дн 16 ч 4 мин');
    expect(stored.comment, 'заменил сальник');
    expect(stored.responsibleUserFullname, 'Козлов М. М.');

    expect(stored.actualConsumptions.single.sparePartName, 'Сальник 40×60');
    expect(stored.actualConsumptions.single.quantity, 3);
    expect(stored.actualConsumptions.single.normQuantity, 2);
    expect(stored.photos.single.url, 'http://x/1.jpg');
    expect(stored.normItems.single.quantity, 2);

    expect(stored.detailsLoaded, isTrue);
  });

  test('отметка «подробности не загружены» тоже переживает', () async {
    // Не мелочь: именно по ней карточка решает, говорить «расхода нет» или
    // «расход не загружен». Перепутать эти два состояния — и обходчик решит,
    // что расход потерян.
    final stored = await roundTrip(
      'repairs_partial',
      sample(detailsLoaded: false),
    );

    expect(stored.detailsLoaded, isFalse);
    // Остальное на месте — отметка не должна утащить за собой соседние поля.
    expect(stored.comment, 'заменил сальник');
    expect(stored.actualConsumptions, hasLength(1));
  });
}
