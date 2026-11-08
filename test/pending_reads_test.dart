import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/notifications/pending_reads.dart';

import 'support/test_data_provider.dart';

/// Очередь недошедших отметок прочтения уведомлений — по паре «сервер +
/// логин», как остальные офлайн-данные (`73f87bf`). Раньше ключом был один
/// логин: отметки, не дошедшие до стенда, после смены сервера ушли бы на его
/// копию с тем же логином.
void main() {
  const serverA = 'https://a.example';

  group('pendingReadKey', () {
    test('тот же логин на другом сервере — другой ключ', () {
      expect(
        pendingReadKey('ttt', serverA),
        isNot(pendingReadKey('ttt', testServer)),
      );
    });

    test('слеш на конце и регистр — тот же сервер', () {
      expect(
        pendingReadKey('ttt', 'HTTPS://A.example/'),
        pendingReadKey('ttt', serverA),
      );
    });

    test('новый ключ не принимается за ключ прошлой версии', () {
      expect(legacyPendingReadLogin(pendingReadKey('ttt', serverA)), isNull);
      expect(
        legacyPendingReadLogin(pendingReadKey('user@mail.ru', serverA)),
        isNull,
      );
    });
  });

  group('legacyPendingReadLogin', () {
    test('ключ прошлой версии — логин', () {
      expect(legacyPendingReadLogin('notifications_pending_read:ttt'), 'ttt');
      expect(
        legacyPendingReadLogin('notifications_pending_read:user@mail.ru'),
        'user@mail.ru',
      );
    });

    test('чужие ключи — не очередь отметок', () {
      expect(legacyPendingReadLogin('account_scope'), isNull);
      expect(legacyPendingReadLogin('notifications_pending_read:'), isNull);
      expect(legacyPendingReadLogin(42), isNull);
    });
  });

  group('mergePendingReads', () {
    test('объединяет без повторов', () {
      final merged = mergePendingReads('["a","b"]', '["b","c"]');
      expect(jsonDecode(merged!), unorderedEquals(['a', 'b', 'c']));
    });

    test('битая запись — как пустая', () {
      expect(jsonDecode(mergePendingReads('{oops', '["a"]')!), ['a']);
    });

    test('обе пусты — нечего сохранять', () {
      expect(mergePendingReads(null, '[]'), isNull);
    });
  });

  group('перенос на устройстве', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pending_reads');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('отметки прошлой версии уходят под сервер прошлой работы', () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('account_scope_server', serverA);
      await provider.stringBox
          .put('notifications_pending_read:ttt', '["n1","n2"]');

      await provider.assignQueueOwners();

      expect(provider.stringBox.get('notifications_pending_read:ttt'), isNull);
      expect(
        jsonDecode(provider.stringBox.get(pendingReadKey('ttt', serverA))!),
        ['n1', 'n2'],
      );
      // На другом сервере с тем же логином их нет.
      expect(provider.stringBox.get(pendingReadKey('ttt', testServer)), isNull);
    });

    test('сервера прошлой работы нет — под текущий', () async {
      final provider = await testDataProvider();
      await provider.stringBox.put('notifications_pending_read:ttt', '["n1"]');

      await provider.assignQueueOwners();

      expect(
        jsonDecode(provider.stringBox.get(pendingReadKey('ttt', testServer))!),
        ['n1'],
      );
    });

    test('под новым ключом уже есть отметки — объединяем', () async {
      final provider = await testDataProvider();
      await provider.stringBox
          .put(pendingReadKey('ttt', testServer), '["n0","n1"]');
      await provider.stringBox.put('notifications_pending_read:ttt', '["n1"]');

      await provider.assignQueueOwners();

      expect(
        jsonDecode(provider.stringBox.get(pendingReadKey('ttt', testServer))!),
        unorderedEquals(['n0', 'n1']),
      );
    });
  });
}
