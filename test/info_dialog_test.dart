import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/widgets/info_dialog.dart';
import 'package:qr_scan_industry/strings.dart';

/// Окно-сообщение на маленьком экране: длинный текст прокручивается, а
/// кнопки остаются на экране. Раньше содержимое не прокручивалось, и на
/// 320×568 нижняя кнопка уходила за край.
void main() {
  testWidgets('длинное предупреждение на 320×568 — кнопки на экране',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longName = 'Компрессорная установка винтовая ' * 6;
    final longLocation = 'Компрессорная станция корпуса № 4, второй этаж ' * 4;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => InfoDialog(
                  icon: Icons.domain_rounded,
                  accent: Colors.green,
                  accentContainer: Colors.green.shade100,
                  title: ForeignEquipmentStrings.title,
                  body: ForeignEquipmentStrings.body(longName, longLocation),
                  note: AccessStrings.hint,
                  actions: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text(ForeignEquipmentStrings.open),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text(ForeignEquipmentStrings.cancel),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Переполнения нет — иначе тест упал бы на исключении рендеринга.
    expect(tester.takeException(), isNull);
    final cancel = find.text(ForeignEquipmentStrings.cancel);
    expect(cancel, findsOneWidget);
    expect(tester.getBottomLeft(cancel).dy, lessThanOrEqualTo(568));
    expect(
      tester.getBottomLeft(find.text(ForeignEquipmentStrings.open)).dy,
      lessThanOrEqualTo(568),
    );
  });
}
