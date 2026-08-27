import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/widgets/spare_part_consumption.dart';

/// Поле количества в блоке фактического расхода.
///
/// Раньше разделитель писался в буфер без проверки, и в поле набиралось
/// «1.2.3». `double.tryParse` на таком возвращает `null`, `onChanged` не
/// вызывался, и при потере фокуса введённое молча пропадало. Число знаков
/// после разделителя тоже не ограничивалось — 1,23456 уходило на сервер, где
/// `Numeric(14, 4)` тихо округлял.
String format(String input) {
  const formatter = QuantityInputFormatter();
  return formatter
      .formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(
          text: input,
          selection: TextSelection.collapsed(offset: input.length),
        ),
      )
      .text;
}

void main() {
  group('QuantityInputFormatter', () {
    test('обычное число проходит как есть', () {
      expect(format('12'), '12');
      expect(format('1,5'), '1,5');
      expect(format('0.25'), '0.25');
    });

    test('второй разделитель отбрасывается', () {
      expect(format('1.2.3'), '1.23');
      expect(format('1,,5'), '1,5');
      // Точка и запятая вперемешку — тоже один разделитель.
      expect(format('1,2.3'), '1,23');
    });

    test('не больше четырёх знаков после разделителя', () {
      expect(format('1,23456'), '1,2345');
      expect(format('0.00001'), '0.0000');
    });

    test('буквы и знаки не проходят', () {
      expect(format('1a2b'), '12');
      expect(format('-5'), '5');
      expect(format('1 000'), '1000');
    });

    test('не больше девяти значащих цифр', () {
      expect(format('12345678901'), '123456789');
      // Ограничение общее: дробная часть тратит тот же запас.
      expect(format('12345,6789'), '12345,6789');
    });

    test('разделитель без целой части сохраняется', () {
      // `double.tryParse('.5')` возвращает 0.5, так что это валидный ввод.
      expect(format('.5'), '.5');
    });

    test('пустая строка остаётся пустой', () {
      expect(format(''), '');
    });
  });
}
