import '../../strings.dart';

/// Что осталось неотправленным после «Синхронизировать данные».
///
/// Раньше итог был одним значением, и окно называло только первую беду по
/// порядку «ремонты → осмотры → заявки»: не ушли и осмотры, и заявки — окно
/// говорило только про осмотры. Теперь собираются все, и окно перечисляет
/// каждую ([troubles]).
class SyncReport {
  /// Связи с сервером нет — ничего не отправлялось.
  final bool noConnection;

  /// В очереди были осмотры или наработка — для «и осмотры успешно
  /// синхронизированы».
  final bool scansWereQueued;

  /// Часть осмотров или наработки не ушла.
  final bool scansLeft;

  /// Черновики или правки ремонтов не ушли.
  final bool repairsLeft;

  /// Заявки «Проблема» не ушли по временной причине (связь, сбой сервера,
  /// ждут повтора) — уйдут сами.
  final bool problemReportsLeft;

  /// Причины, по которым сервер отклонил заявки «Проблема», — без повторов.
  /// Сами такие заявки не уйдут: ждут ручного повтора или смены доступа.
  final List<String> problemReportReasons;

  const SyncReport({
    this.noConnection = false,
    this.scansWereQueued = false,
    this.scansLeft = false,
    this.repairsLeft = false,
    this.problemReportsLeft = false,
    this.problemReportReasons = const [],
  });

  static const SyncReport offline = SyncReport(noConnection: true);

  /// Всё, что не ушло, — по пункту на каждую беду, в порядке важности для
  /// обходчика: сначала то, что само не уйдёт.
  List<SyncTrouble> get troubles => [
        for (final reason in problemReportReasons)
          SyncTrouble(
            title: DialogStrings.syncProblemReportsRejectedTitle,
            body: reason,
            rejected: true,
          ),
        if (repairsLeft)
          const SyncTrouble(
            title: DialogStrings.syncRepairsFailedTitle,
            body: DialogStrings.syncRepairsFailedBody,
          ),
        if (scansLeft)
          const SyncTrouble(
            title: DialogStrings.syncScansFailedTitle,
            body: DialogStrings.syncScansFailedBody,
          ),
        if (problemReportsLeft)
          const SyncTrouble(
            title: DialogStrings.syncProblemReportsFailedTitle,
            body: DialogStrings.syncProblemReportsFailedBody,
          ),
      ];
}

/// Одна беда из [SyncReport.troubles].
class SyncTrouble {
  final String title;
  final String body;

  /// Сервер отказал — само не уйдёт (в отличие от временного сбоя).
  final bool rejected;

  const SyncTrouble({
    required this.title,
    required this.body,
    this.rejected = false,
  });
}
