import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/sync_schedule.dart';

/// Редкая полная перечитка справочника — предохранитель дельта-синхронизации.
///
/// Дельта держится на том, что сервер сообщает обо всех изменениях, включая
/// удаления. Любая дыра в этом контракте оседает в хранилище навсегда: окно
/// следующего прохода начинается там, где кончилось прошлое. Полная перечитка
/// такие расхождения стирает — но только если случается.
void main() {
  final now = DateTime(2026, 10, 17, 12);
  const interval = Duration(days: 3);

  group('isFullResyncDue', () {
    test('полного прохода ещё не было — нужен', () {
      expect(
        isFullResyncDue(lastFullSyncAt: null, now: now, interval: interval),
        isTrue,
      );
    });

    test('прошло меньше интервала — хватит дельты', () {
      expect(
        isFullResyncDue(
          lastFullSyncAt: now.subtract(const Duration(days: 2, hours: 23)),
          now: now,
          interval: interval,
        ),
        isFalse,
      );
    });

    test('интервал истёк ровно — уже пора', () {
      expect(
        isFullResyncDue(
          lastFullSyncAt: now.subtract(interval),
          now: now,
          interval: interval,
        ),
        isTrue,
      );
    });

    test('отметка из будущего не откладывает проход на сутки', () {
      // Часы телефона перевели назад: без этой ветки разница была бы
      // отрицательной, и полная перечитка не случилась бы до тех пор, пока
      // время не догонит отметку.
      expect(
        isFullResyncDue(
          lastFullSyncAt: now.add(const Duration(days: 5)),
          now: now,
          interval: interval,
        ),
        isTrue,
      );
    });
  });
}
