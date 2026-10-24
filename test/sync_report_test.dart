import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/data/sync_report.dart';
import 'package:qr_scan_industry/src/notifications/max_future_days.dart';
import 'package:qr_scan_industry/strings.dart';

void main() {
  group('итог ручной синхронизации', () {
    test('всё ушло — бед нет', () {
      expect(const SyncReport(scansWereQueued: true).troubles, isEmpty);
    });

    test('несколько бед — перечислены все, отказы сервера первыми', () {
      // Раньше окно называло только первую по порядку «ремонты → осмотры →
      // заявки», и застрявшие заявки при застрявших осмотрах не упоминались.
      const report = SyncReport(
        scansWereQueued: true,
        scansLeft: true,
        repairsLeft: true,
        problemReportsLeft: true,
        problemReportReasons: [
          ProblemReportStrings.rejectedNotFound,
          ProblemReportStrings.rejectedNoRights,
        ],
      );

      final troubles = report.troubles;

      expect(troubles.map((t) => t.title), [
        DialogStrings.syncProblemReportsRejectedTitle,
        DialogStrings.syncProblemReportsRejectedTitle,
        DialogStrings.syncRepairsFailedTitle,
        DialogStrings.syncScansFailedTitle,
        DialogStrings.syncProblemReportsFailedTitle,
      ]);
      expect(troubles.take(2).every((t) => t.rejected), isTrue);
      expect(troubles.skip(2).any((t) => t.rejected), isFalse);
      expect(troubles.first.body, ProblemReportStrings.rejectedNotFound);
    });

    test('временный сбой заявок — не отказ: «уйдут сами»', () {
      final troubles = const SyncReport(problemReportsLeft: true).troubles;

      expect(troubles.single.rejected, isFalse);
      expect(troubles.single.body, DialogStrings.syncProblemReportsFailedBody);
    });
  });

  group('горизонт показа задач', () {
    test('пусто — без ограничения', () {
      expect(parseMaxFutureDays('  '), (valid: true, value: null));
    });

    test('целое от 0 до предела — принимается', () {
      expect(parseMaxFutureDays('0'), (valid: true, value: 0));
      expect(parseMaxFutureDays(' 30 '), (valid: true, value: 30));
      expect(parseMaxFutureDays('$maxFutureDaysLimit'),
          (valid: true, value: maxFutureDaysLimit));
    });

    test('мусор, отрицательное, дробное, слишком большое — не сохраняется', () {
      // Раньше такой ввод уходил как null и молча сбрасывал горизонт.
      for (final input in [
        'abc',
        '-5',
        '1.5',
        '${maxFutureDaysLimit + 1}',
      ]) {
        expect(parseMaxFutureDays(input).valid, isFalse, reason: input);
      }
    });
  });
}
