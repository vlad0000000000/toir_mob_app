import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/problem_report_photos.dart';
import 'package:qr_scan_industry/src/exceptions/app_exceptions.dart';
import 'package:qr_scan_industry/src/model/periodic_task_request.dart';
import 'package:qr_scan_industry/strings.dart';

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

/// Адаптер версии с ключом события и uuid, но ещё без причины отказа.
class _KeyedRequestAdapter extends _LegacyRequestAdapter {
  @override
  void write(BinaryWriter writer, PeriodicTaskRequest obj) {
    super.write(writer, obj);
    writer.write(obj.eventId);
    writer.write(obj.serverUuid);
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

    test('отказ и его снятие не меняют ни ключ бокса, ни тело', () {
      final request = _request(eventId: 'ev-1');
      final rejected = request.withRejection('нет оборудования');

      expect(rejected.isRejected, isTrue);
      expect(rejected.key(), request.key());
      expect(jsonEncode(rejected.toJson()), jsonEncode(request.toJson()));
      expect(rejected.withRejection(null).isRejected, isFalse);
      // Пометка переживает запоминание uuid созданной задачи.
      expect(
          rejected.withServerUuid('task-1').rejectedReason, 'нет оборудования');
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

    test('причина отказа переживает запись и чтение', () async {
      Hive.registerAdapter(PeriodicTaskRequestAdapter());
      final box = await Hive.openBox<PeriodicTaskRequest>('ptask');
      await box.put('k', _request(eventId: 'ev-1').withRejection('причина'));
      await box.close();

      final reopened = await Hive.openBox<PeriodicTaskRequest>('ptask');
      final request = reopened.get('k')!;

      expect(request.rejectedReason, 'причина');
      expect(request.eventId, 'ev-1');
    });

    test('запись с ключом и uuid, но без причины, читается — не отклонена',
        () async {
      Hive.registerAdapter(_KeyedRequestAdapter());
      final legacy = await Hive.openBox<PeriodicTaskRequest>('ptask');
      await legacy.put('k', _request(eventId: 'ev-1', serverUuid: 'task-1'));
      await legacy.close();
      Hive.resetAdapters();

      Hive.registerAdapter(PeriodicTaskRequestAdapter());
      final reopened = await Hive.openBox<PeriodicTaskRequest>('ptask');
      final request = reopened.get('k')!;

      expect(request.serverUuid, 'task-1');
      expect(request.isRejected, isFalse);
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

    test('оборудование заявки сервер не видит — отклонена, но не брошена', () {
      // Чужое подразделение: сервер пускает к нему только сам осмотр, а не
      // отдельную заявку. Осмотр принят, а задачи «Проблема» нет — запись
      // ждёт ручного повтора, а не удаляется.
      final notFound = ServerFailureException(404, 'Equipment was not found');
      expect(isProblemReportSettled(notFound), isFalse);
      expect(isProblemReportRejected(notFound), isTrue);
    });

    test('временный сбой — не отказ: повторяет фон', () {
      expect(
          isProblemReportRejected(ServerFailureException(503, 'x')), isFalse);
      expect(
          isProblemReportRejected(const SocketException('нет сети')), isFalse);
      // Таймаут и «слишком часто» лечатся временем.
      expect(
          isProblemReportRejected(ServerFailureException(408, 'x')), isFalse);
      expect(
          isProblemReportRejected(ServerFailureException(429, 'x')), isFalse);
      // Протухший токен — уйдёт после входа.
      expect(isProblemReportRejected(AuthExpiredException()), isFalse);
    });

    test('нет права или данные не приняты — тоже отклонена, а не вечный повтор',
        () {
      // Раньше 403 и 422 тихо повторялись каждые 120 секунд, а ручная
      // синхронизация обещала, что заявки «уйдут сами».
      expect(
          isProblemReportRejected(
              AccessDeniedException(403, 'permission_denied', 'x')),
          isTrue);
      expect(isProblemReportRejected(ServerFailureException(422, 'x')), isTrue);
      expect(isProblemReportRejected(ServerFailureException(400, 'x')), isTrue);
    });

    test('409 и 410 разбирает isProblemReportSettled, а не отказ', () {
      expect(
          isProblemReportRejected(ServerFailureException(409, 'x')), isFalse);
      expect(
          isProblemReportRejected(ServerFailureException(410, 'x')), isFalse);
    });

    test('причина — по коду ответа', () {
      expect(problemReportRejectionReason(ServerFailureException(404, 'x')),
          ProblemReportStrings.rejectedNotFound);
      expect(
          problemReportRejectionReason(
              AccessDeniedException(403, 'permission_denied', 'x')),
          ProblemReportStrings.rejectedNoRights);
      expect(problemReportRejectionReason(ServerFailureException(422, 'x')),
          ProblemReportStrings.rejectedOther);
    });

    test('причина прошлой версии показывается нынешними словами', () {
      // Так её сохранила версия 8e742ed. Копия намеренная: тест должен
      // падать, если перевод перестанет её узнавать.
      const legacy =
          'Сервер не нашёл оборудование — возможно, оно в другом подразделении. '
          'Осмотр отправлен, но задача по проблеме не создана. Повторите '
          '«Синхронизировать данные» позже или сообщите администратору.';
      expect(problemReportStoredReason(legacy),
          ProblemReportStrings.rejectedNotFound);
      expect(problemReportStoredReason(ProblemReportStrings.rejectedNoRights),
          ProblemReportStrings.rejectedNoRights);
      expect(
          problemReportStoredReason(null), ProblemReportStrings.rejectedOther);
    });

    test('прочие отказы создания — повторяем', () {
      expect(isProblemReportSettled(ServerFailureException(503, 'x')), isFalse);
      expect(isProblemReportSettled(ServerFailureException(403, 'x')), isFalse);
      expect(
          isProblemReportSettled(const SocketException('нет сети')), isFalse);
    });
  });
}
