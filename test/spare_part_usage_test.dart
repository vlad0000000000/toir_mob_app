import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/spare_part_usage.dart';

/// Разбор блока `spare_part_usage` из осмотра.
///
/// С коммита бэкенда `1d99a25` блок приходит у **любой** периодической задачи,
/// а не только у настроенной: фактический расход можно указать и без нормы.
/// Отсюда разница между «расход настроен» и «есть план» — от неё зависит,
/// переспрашивать ли перед отправкой осмотра без единой позиции.
void main() {
  group('SparePartUsage', () {
    test('ненастроенная задача: режим пуст, плана нет', () {
      final usage = SparePartUsage.fromJson({
        'mode': null,
        'planned_consumptions': [],
        'actual_consumptions': [],
      });

      expect(usage.mode, isNull);
      expect(usage.isConfigured, isFalse);
      expect(usage.hasPlan, isFalse);
    });

    test('норма: режим и план на месте', () {
      final usage = SparePartUsage.fromJson({
        'mode': 'norm',
        'planned_consumptions': [
          {
            'spare_part': {'uuid': 'a', 'name': 'Подшипник 6205 2RS'},
            'quantity': '2',
          },
        ],
        'actual_consumptions': [],
      });

      expect(usage.isConfigured, isTrue);
      expect(usage.hasPlan, isTrue);
      expect(usage.planned.single.sparePartName, 'Подшипник 6205 2RS');
      expect(usage.planned.single.quantity, 2);
    });

    test('режим задан, а состав пуст — это всё ещё настроенная задача', () {
      // Ровно тот случай, ради которого `isConfigured` отделён от `hasPlan`:
      // администратор выбрал ручной режим, но позиций не добавил.
      final usage = SparePartUsage.fromJson({'mode': 'manual'});

      expect(usage.isConfigured, isTrue);
      expect(usage.hasPlan, isFalse);
    });

    test('факт несёт плановое количество для сравнения', () {
      final usage = SparePartUsage.fromJson({
        'mode': 'norm',
        'actual_consumptions': [
          {
            'spare_part': {'uuid': 'a', 'name': 'Масло И-20А'},
            'quantity': '7',
            'norm_quantity': '5',
          },
        ],
      });

      expect(usage.actual.single.quantity, 7);
      expect(usage.actual.single.normQuantity, 5);
    });

    test('в Hive и обратно — без потери режима', () {
      // Блок лежит в задаче одной JSON-строкой, поэтому важно, чтобы
      // `toJson` и `fromJson` сходились, включая пустой режим.
      final source = SparePartUsage.fromJson({'mode': null});
      final restored = SparePartUsage.fromJson(source.toJson());

      expect(restored.mode, isNull);
      expect(restored.isConfigured, isFalse);
    });
  });
}
