import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/spare_part.dart';

/// Оценка остатка позиции ЗИП — одна на строку справочника и карточку.
///
/// До неё правило было записано в двух местах и по-разному: строка красила
/// красным только нулевой остаток и оранжевым всё, что не выше минимума
/// (`quantity <= minimum`); карточка красила красным всё ниже минимума
/// (`quantity < minimum`) и оранжевым всё ниже нормы. Позиция с остатком 5,
/// минимумом 10 и нормой 20 была в списке оранжевой, а в карточке красной.
SparePart part({
  required double quantity,
  double? minimum,
  double? norm,
}) =>
    SparePart(
      uuid: 'sp-1',
      name: 'Болт 6008-77',
      quantity: quantity,
      minimumStock: minimum,
      stockNorm: norm,
    );

void main() {
  group('SparePart.stockLevel', () {
    test('ниже минимума — худшая из ненулевых оценок', () {
      expect(
        part(quantity: 5, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.belowMinimum,
      );
    });

    test('ровно минимум — это ещё не «ниже минимума»', () {
      // Граница строгая, как в веб-админке и как просил заказчик: «меньше
      // минимума — красный». Прежняя строка справочника считала иначе
      // (`<=`) и красила ровный минимум оранжевым.
      expect(
        part(quantity: 10, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.belowNorm,
      );
    });

    test('между минимумом и нормой — ниже нормы', () {
      expect(
        part(quantity: 15, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.belowNorm,
      );
    });

    test('норма выполнена — остаток благополучен', () {
      expect(
        part(quantity: 20, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.sufficient,
      );
      expect(
        part(quantity: 40, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.sufficient,
      );
    });

    test('ноль — всегда «нет на складе», даже без порогов', () {
      // Отдельная ветка не ради красоты: по формуле ноль без заданного
      // минимума оказался бы «достаточным», и «списывать нечего» выглядело
      // бы благополучно.
      expect(part(quantity: 0).stockLevel, SparePartStockLevel.out);
      expect(
        part(quantity: 0, minimum: 10, norm: 20).stockLevel,
        SparePartStockLevel.out,
      );
      // Отрицательный остаток сервер прислать не должен, но если пришлёт —
      // это тем более «нет на складе», а не «норма выполнена».
      expect(part(quantity: -3).stockLevel, SparePartStockLevel.out);
    });

    test('без порогов ненулевой остаток благополучен', () {
      // Сравнивать не с чем — красить строку не в чем.
      expect(part(quantity: 1).stockLevel, SparePartStockLevel.sufficient);
    });

    test('задан только минимум', () {
      expect(
        part(quantity: 5, minimum: 10).stockLevel,
        SparePartStockLevel.belowMinimum,
      );
      expect(
        part(quantity: 50, minimum: 10).stockLevel,
        SparePartStockLevel.sufficient,
      );
    });

    test('задана только норма', () {
      expect(
        part(quantity: 5, norm: 20).stockLevel,
        SparePartStockLevel.belowNorm,
      );
      expect(
        part(quantity: 25, norm: 20).stockLevel,
        SparePartStockLevel.sufficient,
      );
    });
  });
}
