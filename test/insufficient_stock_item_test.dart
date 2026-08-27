import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';

/// Разбор ответа 409 «Недостаточно ЗИП на складе».
///
/// Название позиции сервер присылает вместе с отказом, и оно самое
/// авторитетное: взято из той же записи склада, по которой он и посчитал
/// нехватку. Раньше разбор его терял, и экран конфликта искал подпись в
/// четырёх запасных источниках — вплоть до голого uuid.
void main() {
  group('InsufficientStockItem.fromJson', () {
    test('берёт название из ответа сервера', () {
      final item = InsufficientStockItem.fromJson(const {
        'spare_part_uuid': 'uuid-1',
        'spare_part_name': 'Болт 6009-40',
        'required': 8,
        'available': 0,
      });

      expect(item.sparePartName, 'Болт 6009-40');
      expect(item.required, 8);
      expect(item.available, 0);
    });

    test('без названия остаётся пустая строка, а не падение', () {
      // Так выглядят отказы старого формата и случай, когда позицию удалили
      // между проверкой и формированием ответа: сервер шлёт `null`.
      final item = InsufficientStockItem.fromJson(const {
        'spare_part_uuid': 'uuid-1',
        'spare_part_name': null,
        'required': '3.5',
        'available': '1',
      });

      expect(item.sparePartName, isEmpty);
      // Числа сервер отдаёт то числом, то строкой — принимаем оба вида.
      expect(item.required, 3.5);
      expect(item.available, 1);
    });
  });

  group('сохранение отказа в осмотре', () {
    test('название переживает запись и чтение', () {
      // Отказ кладётся в `Scan.lastShortages` строкой JSON и разбирается тем
      // же `fromJson`. Не попади название в `toJson` — правка не пережила бы
      // первую же запись в Hive.
      final original = InsufficientStockItem.fromJson(const {
        'spare_part_uuid': 'uuid-1',
        'spare_part_name': 'Ремень ГРМ',
        'required': 2,
        'available': 0,
      });

      final stored = jsonEncode([original.toJson()]);
      final restored = (jsonDecode(stored) as List)
          .map((e) => InsufficientStockItem.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(restored.single.sparePartName, 'Ремень ГРМ');
      expect(restored.single.sparePartUuid, 'uuid-1');
      expect(restored.single.required, 2);
    });

    test('пустое название в JSON не пишется', () {
      const item = InsufficientStockItem(
        sparePartUuid: 'uuid-1',
        required: 1,
        available: 0,
      );

      expect(item.toJson().containsKey('spare_part_name'), isFalse);
      // И читается обратно так же — пустой строкой.
      expect(
        InsufficientStockItem.fromJson(item.toJson()).sparePartName,
        isEmpty,
      );
    });
  });
}
