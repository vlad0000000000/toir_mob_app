import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/widgets/info_dialog.dart';
import 'package:qr_scan_industry/strings.dart';

/// Открывает окно по кнопке и ждёт анимации.
Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) show,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  /// Окно-сообщение на маленьком экране: длинный текст прокручивается, а
  /// кнопки остаются на экране. Раньше содержимое не прокручивалось, и на
  /// 320×568 нижняя кнопка уходила за край.
  testWidgets('длинное предупреждение на 320×568 — кнопки на экране',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final longName = 'Компрессорная установка винтовая ' * 6;
    final longLocation = 'Компрессорная станция корпуса № 4, второй этаж ' * 4;

    await _open(
      tester,
      (context) => showConfirmDialog(
        context,
        icon: Icons.domain_rounded,
        tone: DialogTone.primary,
        title: ForeignEquipmentStrings.title,
        body: ForeignEquipmentStrings.body(longName, longLocation),
        note: AccessStrings.hint,
        confirmLabel: ForeignEquipmentStrings.open,
        cancelLabel: ForeignEquipmentStrings.cancel,
      ),
    );

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

  group('showConfirmDialog', () {
    Future<bool?> run(WidgetTester tester, Finder? tap) async {
      bool? result;
      await _open(tester, (context) async {
        result = await showConfirmDialog(
          context,
          icon: Icons.logout_rounded,
          tone: DialogTone.primary,
          title: DialogStrings.logoutTitle,
          confirmLabel: DialogStrings.logout,
        );
        return result;
      });
      // Без кнопки — тап в угол экрана, мимо окна.
      if (tap == null) {
        await tester.tapAt(const Offset(4, 4));
      } else {
        await tester.tap(tap);
      }
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('главная кнопка — true', (tester) async {
      expect(await run(tester, find.text(DialogStrings.logout)), isTrue);
    });

    testWidgets('«Отмена» — false', (tester) async {
      expect(await run(tester, find.text(DialogStrings.cancel)), isFalse);
    });

    testWidgets('закрытие мимо окна — false, а не null', (tester) async {
      expect(await run(tester, null), isFalse);
    });

    testWidgets('кнопки друг под другом: главная сверху, во всю ширину',
        (tester) async {
      await _open(
        tester,
        (context) => showConfirmDialog(
          context,
          icon: Icons.delete_outline_rounded,
          tone: DialogTone.error,
          title: 'Удалить?',
          confirmLabel: 'Удалить',
          destructive: true,
        ),
      );
      final primary = tester.getRect(find.ancestor(
          of: find.text('Удалить'), matching: find.byType(ElevatedButton)));
      final secondary = tester.getRect(find.ancestor(
          of: find.text(DialogStrings.cancel),
          matching: find.byType(ElevatedButton)));
      expect(primary.top, lessThan(secondary.top));
      expect(primary.width, secondary.width);
      expect(primary.left, secondary.left);
    });
  });

  /// Подпись кнопки при крупном системном шрифте на узком экране не
  /// обрезается: раньше высота была жёсткой и `maxLines: 1` оставлял от
  /// «Завершить и сохранить» только «Завершить и».
  testWidgets('длинная подпись на 320 при шрифте 130% — кнопка растёт',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const label = 'Завершить и сохранить';
    await _open(
      tester,
      (context) => showConfirmDialog(
        context,
        icon: Icons.cloud_off_rounded,
        tone: DialogTone.warning,
        title: 'Завершить ремонт №12?',
        confirmLabel: label,
        confirmIcon: Icons.save_outlined,
      ),
    );

    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(paragraph.didExceedMaxLines, isFalse);
    final button = tester.getRect(find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
    // Подпись не влезла в строку — кнопка выше прежних 56.
    expect(button.height, greaterThan(56));
  });

  testWidgets('сообщение без пояснения — только заголовок и «Понятно»',
      (tester) async {
    await _open(
      tester,
      (context) => showInfoDialog(
        context,
        icon: Icons.cloud_done_rounded,
        tone: DialogTone.success,
        title: DialogStrings.syncAllDone,
      ),
    );
    expect(find.text(DialogStrings.syncAllDone), findsOneWidget);
    await tester.tap(find.text(DialogStrings.understand));
    await tester.pumpAndSettle();
    expect(find.byType(InfoDialog), findsNothing);
  });
}
