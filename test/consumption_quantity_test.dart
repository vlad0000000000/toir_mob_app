import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/utils/quantity_format.dart';
import 'package:qr_scan_industry/src/widgets/spare_part_consumption.dart';

/// Счётчик количества в блоке фактического расхода.
///
/// Количество на сервере — `Numeric(14, 4)`, то есть литры, килограммы и метры
/// законны. Шаг был жёстко ±1: «−» у позиции 0,5 блокировался, а «Заполнить из
/// нормы» с плановыми 0,25 после одного «+» давало 1,25.
void main() {
  group('consumptionStep', () {
    test('у целого количества шаг единичный', () {
      expect(consumptionStep(1), 1);
      expect(consumptionStep(12), 1);
      // Ноль тоже целый: первая же «+» должна дать 1, а не 0,1.
      expect(consumptionStep(0), 1);
    });

    test('у дробного — десятая доля', () {
      expect(consumptionStep(0.25), 0.1);
      expect(consumptionStep(1.5), 0.1);
      expect(consumptionStep(232.75), 0.1);
    });
  });

  group('roundConsumptionQuantity', () {
    test('снимает погрешность двоичной дроби', () {
      // Ровно этот случай и всплывал бы на экране: 0.3 - 0.1 в double равно
      // 0.19999999999999998, и `formatConsumptionQuantity` напечатал бы его
      // целиком.
      expect(roundConsumptionQuantity(0.3 - 0.1), 0.2);
      expect(roundConsumptionQuantity(0.1 + 0.2), 0.3);
    });

    test('оставляет четыре знака — столько же, сколько сервер', () {
      expect(roundConsumptionQuantity(1.23456), 1.2346);
      expect(roundConsumptionQuantity(0.0001), 0.0001);
    });

    test('целые не портит', () {
      expect(roundConsumptionQuantity(5), 5);
      expect(formatConsumptionQuantity(roundConsumptionQuantity(5)), '5');
    });
  });

  group('шаг и округление вместе', () {
    /// Повторяет то, что делает экран: прибавить шаг и округлить.
    double press(double quantity, {required bool plus}) =>
        roundConsumptionQuantity(
            quantity + (plus ? 1 : -1) * consumptionStep(quantity));

    test('«+» у плановых 0,25 даёт 0,35, а не 1,25', () {
      expect(press(0.25, plus: true), 0.35);
    });

    test('«−» у 0,5 работает и даёт 0,4', () {
      // До правки проверка `next < 1` блокировала это нажатие целиком.
      expect(press(0.5, plus: false), 0.4);
    });

    test('целые считаются по единице', () {
      expect(press(3, plus: true), 4);
      expect(press(3, plus: false), 2);
    });

    test('результат печатается без хвоста и через запятую', () {
      expect(formatConsumptionQuantity(press(0.3, plus: false)), '0,2');
    });
  });

  group('formatQuantity', () {
    test('целое печатается без дробной части', () {
      expect(formatQuantity(4), '4');
      expect(formatQuantity(40.0), '40');
    });

    test('дробное — через запятую, как в админке', () {
      expect(formatQuantity(0.1), '0,1');
      expect(formatQuantity(0.01), '0,01');
      expect(formatQuantity(1.5), '1,5');
    });
  });

  group('parseQuantity', () {
    test('запятая и точка равнозначны', () {
      expect(parseQuantity('0,25'), 0.25);
      expect(parseQuantity('0.25'), 0.25);
      expect(parseQuantity(' 12 '), 12);
    });

    test('не число — null', () {
      expect(parseQuantity('много'), isNull);
      expect(parseQuantity(''), isNull);
      expect(parseQuantity(null), isNull);
    });
  });
}
