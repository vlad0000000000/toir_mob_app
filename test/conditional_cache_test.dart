import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/global_state.dart';
import 'package:qr_scan_industry/src/data/conditional_cache.dart';
import 'package:qr_scan_industry/src/http/api.dart';

import 'support/test_data_provider.dart';

/// Условные запросы справочников (бэкенд `81f644c`): 304 — показываем
/// сохранённое. Ошибка опасна одним: 304 на пустой бокс оставил бы
/// справочник пустым, а единицы наработки и состояния оборудования нужны
/// экрану скана без связи.
void main() {
  group('что слать в If-None-Match', () {
    test('ETag и данные на месте — шлём ETag', () {
      expect(
        ifNoneMatchFor(storedEtag: '"abc"', hasCachedData: true),
        '"abc"',
      );
    });

    test('данных нет — без условия, даже если ETag остался', () {
      expect(ifNoneMatchFor(storedEtag: '"abc"', hasCachedData: false), isNull);
    });

    test('ETag нет — без условия', () {
      expect(ifNoneMatchFor(storedEtag: null, hasCachedData: true), isNull);
      expect(ifNoneMatchFor(storedEtag: '', hasCachedData: true), isNull);
    });
  });

  test('304 — данных нет, ETag прежний', () {
    const notModified = Conditional<List<int>>(null, '"abc"');
    const fresh = Conditional<List<int>>([1], '"def"');
    expect(notModified.notModified, isTrue);
    expect(fresh.notModified, isFalse);
  });

  group('смена аккаунта', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('conditional_cache');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('ETag справочников стираются вместе с их боксами', () async {
      final provider = await testDataProvider();
      GlobalState.dataProvider = provider;
      for (final key in lookupEtagKeys) {
        await provider.stringBox.put(key, '"etag"');
      }
      await provider.stringBox.put('themeId', 'fresh');

      await provider.clearCachedData();

      for (final key in lookupEtagKeys) {
        expect(provider.stringBox.containsKey(key), isFalse, reason: key);
      }
      // Настройки обходчика к аккаунту не относятся и остаются.
      expect(provider.stringBox.get('themeId'), 'fresh');
    });
  });

  test('ключи ETag у справочников разные', () {
    expect(lookupEtagKeys.toSet().length, lookupEtagKeys.length);
  });
}
