import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/model/pending_repair.dart';
import 'package:qr_scan_industry/src/model/repair.dart';

/// Запись и чтение черновика ремонта через настоящий Hive.
///
/// Адаптеры в проекте написаны руками: `read()` обязан повторять `write()`
/// поле в поле, и любая перестановка тихо портит уже сохранённые черновики —
/// не падением, а подменой значений (комментарий окажется в `lastError`,
/// счётчик попыток — в дате). Тест закрепляет порядок: он гоняет объект через
/// боксовый файл, а не сравнивает поля в памяти.
///
/// Проверяются и поля, дописанные в конец после первого выпуска
/// (`conflictRepairUuid` … `normItems`): они читаются через `_readTrailing`, и
/// первое же чтение за концом записи гасит все следующие — то есть их порядок
/// так же обязателен, как и у основных.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pending_repair_hive');
    Hive.init(dir.path);
    Hive.registerAdapter(PendingRepairAdapter());
    Hive.registerAdapter(RepairConsumptionAdapter());
    Hive.registerAdapter(RepairNormItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('черновик переживает запись и чтение без перестановки полей', () async {
    final draft = PendingRepair(
      localId: 'local-1',
      equipmentUuid: 'eq-1',
      equipmentName: 'Насос НМ-125',
      consumptionNormUuid: 'norm-1',
      consumptionNormName: 'ТО-1 насоса',
      startedAt: DateTime.utc(2026, 8, 18, 10, 30),
      comment: 'заменил сальник',
      createdAt: DateTime.utc(2026, 8, 18, 11),
      attempts: 3,
      lastError: 'Сервер не принял ремонт',
      conflictRepairUuid: 'repair-9',
      consumptions: [
        RepairConsumption(
          sparePartUuid: 'sp-1',
          sparePartName: 'Сальник 40×60',
          unitName: 'шт',
          quantity: 2,
          normQuantity: 1.5,
        ),
      ],
      serverUuid: 'srv-1',
      photoPaths: const ['a.jpg', 'b.jpg'],
      submitForReview: true,
      normItems: [
        RepairNormItem(
          sparePartUuid: 'sp-1',
          sparePartName: 'Сальник 40×60',
          quantity: 1.5,
        ),
      ],
    );

    final box = await Hive.openBox<PendingRepair>('pending_repairs_test');
    await box.put(draft.localId, draft);
    // Закрываем и открываем заново: иначе вернулся бы объект из памяти, а не
    // разобранный адаптером.
    await box.close();
    final reopened = await Hive.openBox<PendingRepair>('pending_repairs_test');
    final stored = reopened.get('local-1')!;

    expect(stored.localId, 'local-1');
    expect(stored.equipmentUuid, 'eq-1');
    expect(stored.equipmentName, 'Насос НМ-125');
    expect(stored.consumptionNormUuid, 'norm-1');
    expect(stored.consumptionNormName, 'ТО-1 насоса');
    expect(stored.startedAt, DateTime.utc(2026, 8, 18, 10, 30));
    expect(stored.comment, 'заменил сальник');
    expect(stored.createdAt, DateTime.utc(2026, 8, 18, 11));
    expect(stored.attempts, 3);
    expect(stored.lastError, 'Сервер не принял ремонт');
    expect(stored.conflictRepairUuid, 'repair-9');
    expect(stored.serverUuid, 'srv-1');
    expect(stored.photoPaths, ['a.jpg', 'b.jpg']);
    expect(stored.submitForReview, isTrue);

    expect(stored.consumptions, hasLength(1));
    expect(stored.consumptions.single.sparePartUuid, 'sp-1');
    expect(stored.consumptions.single.quantity, 2);
    expect(stored.consumptions.single.normQuantity, 1.5);
    expect(stored.consumptions.single.unitName, 'шт');

    expect(stored.normItems, hasLength(1));
    expect(stored.normItems.single.sparePartUuid, 'sp-1');
    expect(stored.normItems.single.quantity, 1.5);

    await reopened.close();
  });

  test('пустые необязательные поля читаются как пустые, а не как чужие',
      () async {
    // Черновик без нормы, без снимков и без отказа — самый частый случай.
    // Если бы порядок чтения разъехался, `null`-поля не остались бы `null`:
    // в них попали бы значения соседей.
    final draft = PendingRepair(
      localId: 'local-2',
      equipmentUuid: 'eq-2',
      equipmentName: 'Задвижка',
      startedAt: DateTime.utc(2026, 8, 19, 9),
      createdAt: DateTime.utc(2026, 8, 19, 9),
      comment: '',
    );

    final box = await Hive.openBox<PendingRepair>('pending_repairs_empty');
    await box.put(draft.localId, draft);
    await box.close();
    final reopened = await Hive.openBox<PendingRepair>('pending_repairs_empty');
    final stored = reopened.get('local-2')!;

    expect(stored.consumptionNormUuid, isNull);
    expect(stored.consumptionNormName, isNull);
    expect(stored.lastError, isNull);
    expect(stored.conflictRepairUuid, isNull);
    expect(stored.serverUuid, isNull);
    expect(stored.attempts, 0);
    expect(stored.submitForReview, isFalse);
    expect(stored.consumptions, isEmpty);
    expect(stored.photoPaths, isEmpty);
    expect(stored.normItems, isEmpty);
    expect(stored.comment, '');
    expect(stored.startedAt, DateTime.utc(2026, 8, 19, 9));

    await reopened.close();
  });
}
