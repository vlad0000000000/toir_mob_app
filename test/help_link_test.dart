import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/design/app_constants.dart';
import 'package:qr_scan_industry/src/widgets/help_link.dart';

/// Ссылка «Помощь» в шапке главной: под неё отведено 120 пикселей
/// (`leadingWidth` в `app_bar.dart`), а подпись растёт с системным шрифтом.
/// При 150% она вылезала за край примерно на 5,5 пикселя.
void main() {
  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('шапка, шрифт ${(scale * 100).toInt()}% — без переполнения',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Та же раскладка, что у шапки главной.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: const HelpLink(
              padding: EdgeInsets.symmetric(
                horizontal: AppConstants.spacingSM,
                vertical: AppConstants.spacingSM + 4,
              ),
            ),
            leadingWidth: 120,
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Помощь'), findsOneWidget);
    });
  }

  /// Экран входа: ссылка в `Positioned` без правого края — ширина не
  /// ограничена; подпись должна рисоваться целиком и ничего не ронять.
  testWidgets('экран входа, ширина не ограничена — рисуется целиком',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(top: 8, left: 16, child: HelpLink()),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Помощь'), findsOneWidget);
  });
}
