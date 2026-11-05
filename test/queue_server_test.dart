import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/model/scan.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';

import 'support/test_data_provider.dart';

/// Очереди привязаны к паре «сервер + пользователь» (ревью P1): если база
/// стенда — копия другой (dev — копия прода), uuid обходчика на обоих
/// совпадает, и без сервера осмотр, сделанный для A, после пересборки
/// приложения под B ушёл бы на B и пропал из очереди, а кэш справочников A
/// остался бы на экране.
void main() {
  const serverA = 'https://a.example';

  Scan scan({
    String? owner = 'user-1',
    String? server,
    String task = 'task-1',
  }) =>
      Scan(
        equipmentUuid: 'eq-1',
        resultStatus: 'closed',
        taskUuid: task,
        comment: 'осмотр',
        ownerUuid: owner,
        ownerServer: server,
      );

  group('isQueueOwner — сервер', () {
    test('запись другого сервера не своя, даже у того же uuid', () {
      expect(
        isQueueOwner('user-1', 'user-1',
            ownerServer: serverA, currentServer: testServer),
        isFalse,
      );
    });

    test('запись другого сервера не своя и без владельца', () {
      expect(
        isQueueOwner(null, 'user-1',
            ownerServer: serverA, currentServer: testServer),
        isFalse,
      );
    });

    test('тот же сервер — решает владелец', () {
      expect(
        isQueueOwner('user-1', 'user-1',
            ownerServer: testServer, currentServer: testServer),
        isTrue,
      );
      expect(
        isQueueOwner('user-2', 'user-1',
            ownerServer: testServer, currentServer: testServer),
        isFalse,
      );
    });

    test('слеш на конце и регистр — тот же сервер', () {
      expect(
        isQueueOwner('user-1', 'user-1',
            ownerServer: 'HTTPS://A.example/', currentServer: serverA),
        isTrue,
      );
    });

    test('сервер у записи не проставлен — по серверу не судим', () {
      expect(
        isQueueOwner('user-1', 'user-1', currentServer: testServer),
        isTrue,
      );
    });
  });

  group('ключи записей', () {
    test('осмотр для другого сервера не ложится на место этого', () {
      expect(
          scan(server: serverA).key(), isNot(scan(server: testServer).key()));
    });

    test('прежний ключ (без владельца) от сервера не зависит', () {
      expect(scan(server: serverA).legacyKey(),
          scan(server: testServer).legacyKey());
    });

    test('наработка: ключ с сервером, прежние — без него', () {
      UsageUpdate usage(String server) => UsageUpdate(
            usageParameterUuid: 'p-1',
            usageParameterValue: 10,
            equipmentUuid: 'eq-1',
            ownerUuid: 'user-1',
            ownerServer: server,
          );
      expect(usage(serverA).key(), isNot(usage(testServer).key()));
      expect(usage(serverA).ownerOnlyKey(), usage(testServer).ownerOnlyKey());
      expect(usage(serverA).legacyKey(), usage(testServer).legacyKey());
    });

    test('правка ремонта: ремонт, владелец и сервер', () {
      expect(pendingRepairUpdateKey('r-1', 'user-1', serverA),
          isNot(pendingRepairUpdateKey('r-1', 'user-1', testServer)));
      expect(pendingRepairUpdateKey('r-1', 'user-1', 'HTTPS://A.example/'),
          pendingRepairUpdateKey('r-1', 'user-1', serverA));
      expect(pendingRepairUpdateKey('r-1', 'user-1'), 'r-1@user-1');
      expect(pendingRepairUpdateKey('r-1', null, serverA), 'r-1');
    });
  });

  group('на устройстве', () {
    late Directory dir;

    setUpAll(() {
      Hive.registerAdapter(ScanAdapter(), override: true);
      Hive.registerAdapter(UsageUpdateAdapter(), override: true);
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('queue_server');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('осмотр другого сервера не считается и ждёт своего сервера', () async {
      final foreign = scan(server: serverA);
      final own = scan(server: testServer);
      final box = await Hive.openBox<Scan>('scans');
      await box.put(foreign.key(), foreign);
      await box.put(own.key(), own);
      final provider = await testDataProvider();

      expect(provider.scanBox.length, 2);
      expect(provider.myQueuedScansCount, 1);
      expect(provider.isMine(foreign), isFalse);
      expect(provider.isMine(own), isTrue);
    });

    test('запись прошлой версии получает сервер прошлого входа', () async {
      final old = scan(owner: null);
      final box = await Hive.openBox<Scan>('scans');
      await box.put(old.legacyKey(), old);
      final provider = await testDataProvider();
      await provider.stringBox.put('account_scope', 'user-1');
      await provider.stringBox.put('account_scope_server', serverA);

      await provider.assignQueueOwners();

      final stored = provider.scanBox.values.single;
      expect(stored.ownerUuid, 'user-1');
      expect(stored.ownerServer, serverA);
      // Перенесена под ключ с владельцем и сервером.
      expect(provider.scanBox.keys.single, stored.key());
      expect(provider.myQueuedScansCount, 0);
    });

    test('сервера прошлого входа нет — запись получает текущий', () async {
      final old = scan(owner: null);
      final box = await Hive.openBox<Scan>('scans');
      await box.put(old.legacyKey(), old);
      final provider = await testDataProvider();

      await provider.assignQueueOwners();

      expect(provider.scanBox.values.single.ownerServer, testServer);
      expect(provider.myQueuedScansCount, 1);
    });

    test('вход тем же uuid на другом сервере сбрасывает кэш', () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('account_scope', 'user-1');
      await provider.stringBox.put('account_scope_server', serverA);

      expect(await provider.ensureAccountScope('user-1'), isTrue);
      expect(provider.stringBox.get('account_scope_server'), testServer);
    });

    test('тот же uuid и сервер — кэш остаётся', () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('account_scope', 'user-1');
      await provider.stringBox.put('account_scope_server', testServer);

      expect(await provider.ensureAccountScope('user-1'), isFalse);
    });

    test('кэш прошлой версии без сервера — свой, сервер запоминается',
        () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('account_scope', 'user-1');

      expect(await provider.ensureAccountScope('user-1'), isFalse);
      expect(provider.stringBox.get('account_scope_server'), testServer);
    });

    test(
        'задачу прячут неотправленные осмотры этого сервера — и коллег, '
        'но не другого сервера', () async {
      final box = await Hive.openBox<Scan>('scans');
      final pending = await Hive.openBox<Scan>('pending_scans');
      // Копия базы: та же задача, осмотр сделан для сервера A.
      final foreign = scan(server: serverA, task: 'task-a');
      // Коллега на этом же сервере закрыл задачу без связи.
      final colleague =
          scan(owner: 'user-2', server: testServer, task: 'task-c');
      // Мой осмотр «в полёте».
      final mine = scan(server: testServer, task: 'task-m');
      // Запись прошлой версии без сервера — считается своего.
      final legacy = scan(owner: null, task: 'task-l');
      await box.put(foreign.key(), foreign);
      await box.put(colleague.key(), colleague);
      await pending.put(mine.key(), mine);
      await box.put(legacy.key(), legacy);
      final provider = await testDataProvider();

      expect(provider.scannedTaskUuids, {'task-c', 'task-m', 'task-l'});
    });
  });

  group('isQueueRecordForServer', () {
    test('запись другого сервера — нет', () {
      expect(isQueueRecordForServer(serverA, testServer), isFalse);
    });

    test('этого сервера, без сервера или текущий неизвестен — да', () {
      expect(isQueueRecordForServer(testServer, testServer), isTrue);
      expect(isQueueRecordForServer(null, testServer), isTrue);
      expect(isQueueRecordForServer(serverA, null), isTrue);
    });
  });
}
