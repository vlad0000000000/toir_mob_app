import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/problem_report_photos.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/model/periodic_task_request.dart';

/// Адаптер заявки до ключа события и uuid созданной задачи — формат, что
/// лежит в очередях на устройствах с прошлой версией.
class _LegacyRequestAdapter extends TypeAdapter<PeriodicTaskRequest> {
  @override
  final int typeId = 20;

  @override
  PeriodicTaskRequest read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, PeriodicTaskRequest obj) {
    writer.write(obj.equipmentUuid);
    writer.write(obj.node);
    writer.write(obj.title);
    writer.write(obj.description);
    writer.write(obj.periodicityRule);
    writer.write(obj.customRoleIds);
    writer.write(obj.nextDueAt);
    writer.write(obj.params);
    writer.write(obj.photos);
  }
}

PeriodicTaskRequest _request({String? eventId, String? serverUuid}) =>
    PeriodicTaskRequest(
      equipmentUuid: 'eq-1',
      title: 'Проблема',
      description: 'Течь масла',
      periodicityRule: 'once',
      nextDueAt: '2026-10-23T10:00:00.000Z',
      params: const {'target_type': 'ad_hoc', 'priority': 'high'},
      photos: const ['aGVsbG8='],
      eventId: eventId,
      serverUuid: serverUuid,
    );

void main() {
  group('ключи заявки', () {
    test('ключ создания — от события, снимков — свой', () {
      final request = _request(eventId: 'ev-1');

      expect(request.createIdempotencyKey, 'ev-1');
      expect(request.photosIdempotencyKey, 'ev-1:photos');
    });

    test('запись прошлой версии — ключ из содержимого, стабильный', () {
      final request = _request();

      expect(request.createIdempotencyKey, 'problem-report-${request.key()}');
      expect(_request().createIdempotencyKey, request.createIdempotencyKey);
    });

    test('uuid созданной задачи не меняет ни ключ бокса, ни тело', () {
      final request = _request(eventId: 'ev-1');
      final created = request.withServerUuid('task-1');

      expect(created.key(), request.key());
      expect(created.createIdempotencyKey, request.createIdempotencyKey);
      // Сервер сверяет ключ с телом: тело повтора обязано совпадать.
      expect(jsonEncode(created.toJson()), jsonEncode(request.toJson()));
      expect(created.serverUuid, 'task-1');
    });
  });

  group('адаптер', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ptask_hive');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    });

    test('ключ события и uuid переживают запись и чтение', () async {
      Hive.registerAdapter(PeriodicTaskRequestAdapter());
      final box = await Hive.openBox<PeriodicTaskRequest>('ptask');
      await box.put('k', _request(eventId: 'ev-1', serverUuid: 'task-1'));
      await box.close();

      final reopened = await Hive.openBox<PeriodicTaskRequest>('ptask');
      final request = reopened.get('k')!;

      expect(request.eventId, 'ev-1');
      expect(request.serverUuid, 'task-1');
      expect(request.photos, ['aGVsbG8=']);
    });

    test('запись прошлой версии читается — ключа и uuid нет', () async {
      Hive.registerAdapter(_LegacyRequestAdapter());
      final legacy = await Hive.openBox<PeriodicTaskRequest>('ptask');
      await legacy.put('k', _request());
      await legacy.close();
      Hive.resetAdapters();

      Hive.registerAdapter(PeriodicTaskRequestAdapter());
      final reopened = await Hive.openBox<PeriodicTaskRequest>('ptask');
      final request = reopened.get('k')!;

      expect(request.title, 'Проблема');
      expect(request.eventId, isNull);
      expect(request.serverUuid, isNull);
    });
  });

  group('снимки заявки не загрузились', () {
    test('обрыв связи, сбой сервера, протухший доступ — повторяем', () {
      expect(isRetryableProblemPhotoError(const SocketException('нет сети')),
          isTrue);
      expect(isRetryableProblemPhotoError(ServerFailureException(503, 'x')),
          isTrue);
      expect(isRetryableProblemPhotoError(AuthExpiredException()), isTrue);
    });

    test('задачу взяли, нет права, файл не принят — бросаем', () {
      expect(isRetryableProblemPhotoError(ServerFailureException(409, 'x')),
          isFalse);
      expect(
        isRetryableProblemPhotoError(
            AccessDeniedException(403, 'permission_denied', 'x')),
        isFalse,
      );
      expect(isRetryableProblemPhotoError(ServerFailureException(413, 'x')),
          isFalse);
    });

    test('задачу по ключу удалили или такая уже есть — повтор бесполезен', () {
      expect(isProblemReportSettled(ServerFailureException(410, 'x')), isTrue);
      expect(isProblemReportSettled(ServerFailureException(409, 'x')), isTrue);
    });

    test('прочие отказы создания — повторяем', () {
      expect(isProblemReportSettled(ServerFailureException(503, 'x')), isFalse);
      expect(isProblemReportSettled(ServerFailureException(403, 'x')), isFalse);
      expect(
          isProblemReportSettled(const SocketException('нет сети')), isFalse);
    });
  });
}
