import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/data/task_generation.dart';
import 'package:qr_scan_industry/src/model/company.dart';
import 'package:qr_scan_industry/src/model/inventory_record.dart';
import 'package:qr_scan_industry/src/model/scan.dart';
import 'package:qr_scan_industry/src/widgets/task_pause_banner.dart';
import 'package:qr_scan_industry/strings.dart';

import 'support/test_data_provider.dart';

/// Пауза новых задач (бэкенд `5e60312`): задачи и ТО создаются только у
/// оборудования «В работе». Обходчик меняет состояние сам и должен об этом
/// знать, а сервер прошлой версии паузы не делает — обещать её там нельзя.
void main() {
  group('isTaskGenerationPaused', () {
    test('«В работе» — паузы нет', () {
      expect(isTaskGenerationPaused('in_operation'), isFalse);
    });

    test('любое другое состояние — пауза', () {
      for (final state in [
        'in_repair',
        'in_reserve',
        'on_modernization',
        'on_diagnostics',
        'waiting_for_commissioning',
        'malfunctioning',
        'on_calibration',
      ]) {
        expect(isTaskGenerationPaused(state), isTrue, reason: state);
      }
    });

    test('без состояния — пауза, как на сервере', () {
      expect(isTaskGenerationPaused(null), isTrue);
      expect(isTaskGenerationPaused(''), isTrue);
    });
  });

  group('пояс компании в /user/me', () {
    Map<String, dynamic> me(Map<String, dynamic> extra) => {
          'company': {
            'allow_requests_without_qr': true,
            'allow_multiple_tasks_per_qr_scan': false,
            ...extra,
          },
        };

    test('разбирается', () {
      expect(CompanyFlags.fromMe(me({'timezone': 'Asia/Omsk'}))!.timezone,
          'Asia/Omsk');
    });

    test('сервер прошлой версии — пояса нет, флаги на месте', () {
      final flags = CompanyFlags.fromMe(me({}))!;

      expect(flags.timezone, isNull);
      expect(flags.allowRequestsWithoutQr, isTrue);
    });
  });

  group('на устройстве', () {
    late Directory dir;

    InventoryRecord machine({String? state}) => InventoryRecord(
          id: 1,
          uuid: 'eq-1',
          name: 'Станок',
          typeModel: null,
          serialNumber: null,
          state: state,
        );

    setUpAll(() {
      Hive.registerAdapter(ScanAdapter(), override: true);
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('task_generation');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Future<DataProvider> provider({String? timezone}) async {
      final result = await testDataProvider();
      if (timezone != null) {
        await result.stringBox.put('company_timezone', timezone);
      }
      return result;
    }

    test('сервер прошлой версии — плашки нет, что бы ни было с состоянием',
        () async {
      final data = await provider();

      expect(data.taskPauseSupported, isFalse);
      expect(data.isTaskGenerationPausedFor(machine(state: 'in_reserve')),
          isFalse);
    });

    test('новый сервер: не «В работе» — пауза, «В работе» — нет', () async {
      final data = await provider(timezone: 'Europe/Moscow');

      expect(data.taskPauseSupported, isTrue);
      expect(
          data.isTaskGenerationPausedFor(machine(state: 'in_reserve')), isTrue);
      expect(data.isTaskGenerationPausedFor(machine()), isTrue);
      expect(data.isTaskGenerationPausedFor(machine(state: 'in_operation')),
          isFalse);
    });

    test('смена аккаунта или сервера забывает пояс', () async {
      final data = await provider(timezone: 'Europe/Moscow');

      await data.clearCachedData();

      expect(data.companyTimezone, isNull);
      expect(data.taskPauseSupported, isFalse);
    });
  });

  group('плашка', () {
    for (final size in const [Size(320, 568), Size(480, 1000)]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} — без '
          'переполнения', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SafeArea(child: TaskPauseBanner())),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(TaskPauseStrings.title), findsOneWidget);
        expect(find.text(TaskPauseStrings.body), findsOneWidget);
      });
    }
  });
}
