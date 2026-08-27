import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/spare_part.dart';

/// Разбор строки фактического расхода обратно в «uuid → сколько списать».
///
/// Нужен для локальной заплатки на остаток: сервер списывает ЗИП в момент
/// закрытия осмотра, а каталог у клиента освежается раз в минуту, и всю эту
/// минуту предупреждение о нехватке считалось по числу, которого на складе
/// уже нет.
///
/// Разбор обязан быть терпимым: он правит каталог, и кривая запись в очереди
/// не должна его испортить.
void main() {
  group('parseConsumptionWriteOff', () {
    test('разбирает то, что ушло на сервер', () {
      final result = parseConsumptionWriteOff(
        '[{"spare_part_uuid":"sp-1","quantity":2},'
        '{"spare_part_uuid":"sp-2","quantity":0.25}]',
      );

      expect(result, {'sp-1': 2.0, 'sp-2': 0.25});
    });

    test('число строкой тоже принимается', () {
      // То же послабление, что и в `parseServerDecimal`: Numeric сервер
      // отдаёт то числом, то строкой.
      final result = parseConsumptionWriteOff(
        '[{"spare_part_uuid":"sp-1","quantity":"1.5"}]',
      );

      expect(result, {'sp-1': 1.5});
    });

    test('повторы одной позиции складываются', () {
      final result = parseConsumptionWriteOff(
        '[{"spare_part_uuid":"sp-1","quantity":2},'
        '{"spare_part_uuid":"sp-1","quantity":3}]',
      );

      expect(result, {'sp-1': 5.0});
    });

    test('ноль, отрицательное и мусор в количестве отбрасываются', () {
      // Ноль и отрицательное сервер и не принял бы; списывать по ним нечего,
      // а обнулить остаток «на всякий случай» было бы хуже, чем пропустить.
      final result = parseConsumptionWriteOff(
        '[{"spare_part_uuid":"sp-1","quantity":0},'
        '{"spare_part_uuid":"sp-2","quantity":-4},'
        '{"spare_part_uuid":"sp-3","quantity":"много"},'
        '{"spare_part_uuid":"sp-4"},'
        '{"spare_part_uuid":"sp-5","quantity":1}]',
      );

      expect(result, {'sp-5': 1.0});
    });

    test('строка без uuid не попадает в результат', () {
      final result = parseConsumptionWriteOff(
        '[{"quantity":2},{"spare_part_uuid":"","quantity":2},'
        '{"spare_part_uuid":"sp-1","quantity":2}]',
      );

      expect(result, {'sp-1': 2.0});
    });

    test('пустое, битое и не то по форме — пустой результат, а не падение', () {
      // Заплатка не вправе уронить очередь отправки: она вызывается из неё
      // сразу после успешной отправки осмотра.
      expect(parseConsumptionWriteOff(null), isEmpty);
      expect(parseConsumptionWriteOff(''), isEmpty);
      expect(parseConsumptionWriteOff('не json'), isEmpty);
      expect(parseConsumptionWriteOff('{"spare_part_uuid":"sp-1"}'), isEmpty);
      expect(parseConsumptionWriteOff('[1, 2, 3]'), isEmpty);
    });
  });

  group('SparePart.copyWithQuantity', () {
    test('меняет только остаток', () {
      final part = SparePart(
        uuid: 'sp-1',
        name: 'Болт 6009-40',
        supplierCode: 'A-1',
        unitName: 'шт',
        warehouseUuid: 'wh-1',
        warehouseName: 'Основной',
        nomenclatureGroupUuid: 'ng-1',
        nomenclatureGroupName: 'Крепёж',
        quantity: 10,
        minimumStock: 3,
        stockNorm: 20,
        accountingAccount: '10.06.5',
      );

      final reduced = part.copyWithQuantity(2);

      expect(reduced.quantity, 2);
      expect(reduced.uuid, part.uuid);
      expect(reduced.name, part.name);
      expect(reduced.supplierCode, part.supplierCode);
      expect(reduced.unitName, part.unitName);
      expect(reduced.warehouseName, part.warehouseName);
      expect(reduced.nomenclatureGroupName, part.nomenclatureGroupName);
      expect(reduced.minimumStock, part.minimumStock);
      expect(reduced.stockNorm, part.stockNorm);
      expect(reduced.accountingAccount, part.accountingAccount);
      // Признак «ниже минимума» считается от остатка — он обязан пересчитаться.
      expect(part.isBelowMinimum, isFalse);
      expect(reduced.isBelowMinimum, isTrue);
    });
  });
}
