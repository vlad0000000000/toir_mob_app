import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/periodic_task_models.dart';
import 'package:qr_scan_industry/src/model/task_access.dart';
import 'package:qr_scan_industry/src/tasks/periodic_task_card.dart';
import 'package:qr_scan_industry/strings.dart';

PeriodicTask _task() => PeriodicTask.fromJson({
      'id': 1,
      'uuid': 'pt-1',
      'equipment': {'id': 1, 'uuid': 'eq-1', 'name': 'Компрессор'},
      'title': 'Проблема',
      'periodicity_rule': 'once',
      'periodicity_rule_display': 'Однократно',
      'custom_roles': <dynamic>[],
      'is_active': true,
    });

Future<void> _openCard(WidgetTester tester, TaskAccess? rework) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                showPeriodicTaskCard(context, _task(), rework: rework),
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
  testWidgets('карточка возвращённой задачи — причина и кто вернул',
      (tester) async {
    await _openCard(
      tester,
      const TaskAccess(
        returned: true,
        returnComment: 'Не приложено фото',
        returnedBy: 'Иванов И. И.',
      ),
    );

    expect(find.text(ReworkStrings.sectionTitle), findsOneWidget);
    expect(find.text('Не приложено фото'), findsOneWidget);
    expect(find.text(ReworkStrings.returnedBy('Иванов И. И.')), findsOneWidget);
  });

  testWidgets('без причины — так и сказано', (tester) async {
    await _openCard(tester, const TaskAccess(returned: true));

    expect(find.text(ReworkStrings.reasonEmpty), findsOneWidget);
  });

  testWidgets('обычная задача — блока доработки нет', (tester) async {
    await _openCard(tester, null);

    expect(find.text(ReworkStrings.sectionTitle), findsNothing);
  });

  /// Заголовок блока при крупном шрифте на узком экране переносится, а не
  /// вылезает за край: раньше текст стоял в `Row` без ограничения ширины.
  testWidgets('320×568 при шрифте 150% — без переполнения', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _openCard(
      tester,
      const TaskAccess(returned: true, returnComment: 'Причина'),
    );

    expect(tester.takeException(), isNull);
  });
}
