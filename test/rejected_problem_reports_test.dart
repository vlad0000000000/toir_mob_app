import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/company.dart';
import 'package:qr_scan_industry/src/model/consumption_norm.dart';
import 'package:qr_scan_industry/src/model/equipment_state.dart';
import 'package:qr_scan_industry/src/model/inventory_record.dart';
import 'package:qr_scan_industry/src/model/pending_repair.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/periodic_task_request.dart';
import 'package:qr_scan_industry/src/model/periodicity_rule.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/model/scan.dart';
import 'package:qr_scan_industry/src/model/session.dart';
import 'package:qr_scan_industry/src/model/spare_part.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/model/typical_problem.dart';
import 'package:qr_scan_industry/src/model/usage_unit.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';
import 'package:qr_scan_industry/src/model/user.dart';
import 'package:qr_scan_industry/src/qr/rejected_problem_reports_sheet.dart';
import 'package:qr_scan_industry/src/widgets/app_bottom_sheet.dart';
import 'package:qr_scan_industry/strings.dart';

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

/// `DataProvider` на пустых боксах во временном каталоге: адаптер нужен
/// только заявкам — остальные боксы пусты и ничего не читают.
Future<DataProvider> _provider() async {
  Future<Box<T>> open<T>(String name) => Hive.openBox<T>(name);
  return DataProvider(
    api: API(),
    userBox: await open<User>('users'),
    inventoryBox: await open<InventoryRecord>('inventory'),
    scanBox: await open<Scan>('scans'),
    scanUsageBox: await open<UsageUpdate>('usage_scans'),
    scanPendingBox: await open<Scan>('pending_scans'),
    scanUsagePendingBox: await open<UsageUpdate>('pending_usage_scans'),
    sessionBox: await open<Session>('sessions'),
    usageUnitBox: await open<UsageUnit>('usage_units'),
    typicalProblemBox: await open<TypicalProblem>('typical_problems'),
    stringBox: await open<String>('strings'),
    periodicityRuleBox: await open<PeriodicityRule>('periodicity_rules'),
    taskBox: await open<Task>('tasks'),
    companyBox: await open<Company>('company'),
    equipmentStateBox: await open<EquipmentState>('equipment_states'),
    sparePartBox: await open<SparePart>('spare_parts'),
    repairBox: await open<Repair>('repairs'),
    pendingRepairBox: await open<PendingRepair>('pending_repairs'),
    pendingRepairUpdateBox:
        await open<PendingRepairUpdate>('pending_repair_updates'),
    consumptionNormBox: await open<ConsumptionNorm>('consumption_norms'),
    periodicTaskBox: await open<PeriodicTaskRequest>('periodic_tasks'),
    periodicTaskPendingBox:
        await open<PeriodicTaskRequest>('pending_periodic_tasks'),
  );
}

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
    final provider = await _provider();

    expect(provider.rejectedProblemReportsCount.value, 1);
    expect(provider.rejectedProblemReports.single.description, 'течь');
  });

  test('повтор снимает пометку и счётчик, запись остаётся в очереди', () async {
    final rejected = _request('течь').withRejection('нет оборудования');
    await _seed([rejected]);
    final provider = await _provider();

    await provider.retryRejectedProblemReport(rejected.key());

    expect(provider.rejectedProblemReportsCount.value, 0);
    expect(provider.periodicTaskBox.get(rejected.key())!.isRejected, isFalse);
  });

  test('ручная синхронизация и смена доступа снимают все пометки', () async {
    await _seed([
      _request('течь').withRejection('нет оборудования'),
      _request('шум').withRejection('нет оборудования'),
    ]);
    final provider = await _provider();

    expect(await provider.retryRejectedProblemReports(), 2);
    expect(provider.rejectedProblemReportsCount.value, 0);
  });

  test('удаление убирает заявку и пометку', () async {
    final rejected = _request('течь').withRejection('нет оборудования');
    await _seed([rejected]);
    final provider = await _provider();

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
      return _provider();
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
