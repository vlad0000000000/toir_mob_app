import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/data/problem_report_photos.dart';
import 'package:qr_scan_industry/src/model/periodic_task_request.dart';
import 'package:qr_scan_industry/src/qr/rejected_problem_reports_sheet.dart';
import 'package:qr_scan_industry/src/widgets/app_bottom_sheet.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

PeriodicTaskRequest _request(String description) => PeriodicTaskRequest(
      equipmentUuid: 'eq-1',
      title: 'Проблема',
      description: description,
      periodicityRule: 'once',
      nextDueAt: '2026-10-23T10:00:00.000Z',
      params: const {'target_type': 'ad_hoc', 'priority': 'high'},
      photos: const [],
      eventId: 'ev-$description',
    );

/// Кладёт заявки в бокс до создания провайдера — как после перезапуска.
Future<void> _seed(List<PeriodicTaskRequest> requests) async {
  final box = await Hive.openBox<PeriodicTaskRequest>('periodic_tasks');
  for (final request in requests) {
    await box.put(request.key(), request);
  }
}

void main() {
  late Directory dir;

  setUpAll(() {
    Hive.registerAdapter(PeriodicTaskRequestAdapter(), override: true);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rejected_reports');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('при запуске счётчик видит отклонённые, но не обычные заявки', () async {
    await _seed([
      _request('течь').withRejection('нет оборудования'),
      _request('шум'),
    ]);
    final provider = await testDataProvider();

    expect(provider.rejectedProblemReportsCount.value, 1);
    expect(provider.rejectedProblemReports.single.description, 'течь');
  });

  test('повтор снимает пометку и счётчик, запись остаётся в очереди', () async {
    final rejected = _request('течь').withRejection('нет оборудования');
    await _seed([rejected]);
    final provider = await testDataProvider();

    await provider.retryRejectedProblemReport(rejected.key());

    expect(provider.rejectedProblemReportsCount.value, 0);
    expect(provider.periodicTaskBox.get(rejected.key())!.isRejected, isFalse);
  });

  test('ручная синхронизация и смена доступа снимают все пометки', () async {
    await _seed([
      _request('течь').withRejection('нет оборудования'),
      _request('шум').withRejection('нет оборудования'),
    ]);
    final provider = await testDataProvider();

    expect(await provider.retryRejectedProblemReports(), 2);
    expect(provider.rejectedProblemReportsCount.value, 0);
  });

  test('удаление убирает заявку и пометку', () async {
    final rejected = _request('течь').withRejection('нет оборудования');
    await _seed([rejected]);
    final provider = await testDataProvider();

    await provider.deleteRejectedProblemReport(rejected.key());

    expect(provider.periodicTaskBox.isEmpty, isTrue);
    expect(provider.rejectedProblemReportsCount.value, 0);
  });

  /// Открывает лист так же, как главная, — через [showAppModalSheet]:
  /// без своей обёртки, иначе тест не увидел бы переполнения.
  Future<DataProvider> openSheet(
    WidgetTester tester,
    List<PeriodicTaskRequest> requests,
  ) async {
    final provider = await tester.runAsync(() async {
      await _seed(requests);
      return testDataProvider();
    });
    GlobalState.dataProvider = provider!;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAppModalSheet<void>(
                context,
                isDismissible: true,
                enableDrag: true,
                child: const RejectedProblemReportsSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return provider;
  }

  testWidgets('лист показывает причину, а «Повторить» закрывает его',
      (tester) async {
    final provider = await openSheet(tester, [
      _request('Течь масла')
          .withRejection(ProblemReportStrings.rejectedNotFound),
    ]);

    expect(find.text('Течь масла'), findsOneWidget);
    expect(find.text(ProblemReportStrings.rejectedNotFound), findsOneWidget);

    // Запись в Hive — настоящий ввод-вывод: даём ему пройти вне фейкового
    // времени теста.
    await tester.runAsync(() async {
      await tester.tap(find.text(ProblemReportStrings.retry));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byType(RejectedProblemReportsSheet), findsNothing);
    expect(provider.rejectedProblemReportsCount.value, 0);
  });

  testWidgets('прежний текст причины — нынешними словами, без повтора пункта',
      (tester) async {
    // Заявка, отклонённая прошлой версией, несёт прежние слова; рядом —
    // такая же, отклонённая уже нынешней. Причина одна — и показывается она
    // одна, нынешним текстом.
    const legacy =
        'Сервер не нашёл оборудование — возможно, оно в другом подразделении. '
        'Осмотр отправлен, но задача по проблеме не создана. Повторите '
        '«Синхронизировать данные» позже или сообщите администратору.';
    final old = _request('старая').withRejection(legacy);
    final fresh =
        _request('новая').withRejection(ProblemReportStrings.rejectedNotFound);
    final provider = await openSheet(tester, [old, fresh]);

    expect(find.text(legacy), findsNothing);
    expect(find.text(ProblemReportStrings.rejectedNotFound), findsNWidgets(2));
    expect(
      {
        for (final task in provider.rejectedProblemReports)
          problemReportStoredReason(task.rejectedReason),
      },
      {ProblemReportStrings.rejectedNotFound},
    );
  });

  /// Лист прокручивается: `Modal` даёт ему высоту 90% экрана без прокрутки,
  /// и раньше нижние записи и кнопки уходили за край.
  for (final (size, count) in const [
    (Size(320, 568), 1),
    (Size(480, 1000), 4),
  ]) {
    testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}, заявок: $count — '
        'без переполнения, «Закрыть» достижима', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await openSheet(tester, [
        for (var i = 0; i < count; i++)
          _request('Заявка $i')
              .withRejection(ProblemReportStrings.rejectedNotFound),
      ]);

      expect(tester.takeException(), isNull);
      final close = find.widgetWithText(TextButton, ProblemReportStrings.close);
      await tester.scrollUntilVisible(close, 200,
          scrollable: find.descendant(
              of: find.byType(RejectedProblemReportsSheet),
              matching: find.byType(Scrollable)));
      expect(tester.getBottomLeft(close).dy, lessThanOrEqualTo(size.height));
    });
  }
}
