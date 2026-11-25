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

  /// Черновики или правки ремонтов ждут отправки: связи нет, сервер не
  /// ответил, ремонт ещё не начался — уйдут сами.
  final bool repairsLeft;

  /// Черновики или правки ремонтов сервер отклонил — сами не уйдут, обходчик
  /// решает в «Ремонтах» (блок «Не отправлено»): повторить или удалить.
  final bool repairsRejected;

  /// Заявки «Проблема» не ушли по временной причине (связь, сбой сервера,
  /// ждут повтора) — уйдут сами.
  final bool problemReportsLeft;

  /// Причины, по которым сервер отклонил заявки «Проблема», — без повторов.
  /// Сами такие заявки не уйдут: ждут ручного повтора или смены доступа.
  final List<String> problemReportReasons;

  /// Работа этой версии ограничена (`work_blocked`, бэкенд `811c4dc`) —
  /// по статусу, перечитанному в конце синхронизации. Очередь при этом
  /// уходит как обычно, остальные пункты отчёта — её итог.
  final bool workBlocked;

  /// Ссылка на RuStore для кнопки «Открыть RuStore»; `null` — сервер её не
  /// дал.
  final Uri? storeUri;

  const SyncReport({
    this.noConnection = false,
    this.scansWereQueued = false,
    this.scansLeft = false,
    this.repairsLeft = false,
    this.repairsRejected = false,
    this.problemReportsLeft = false,
    this.problemReportReasons = const [],
    this.workBlocked = false,
    this.storeUri,
  });

  static const SyncReport offline = SyncReport(noConnection: true);

  /// Строка о фактическом итоге отправки, когда из бед — только ограничение
  /// работы: данные ушли, и обходчик должен видеть это рядом с ограничением
  /// (бэкенд просит показывать результат отправки отдельно).
  String? get sentNote {
    if (!workBlocked) return null;
    if (troubles.any((trouble) => !trouble.isWorkBlocked)) return null;
    return scansWereQueued
        ? DialogStrings.syncScansDone
        : DialogStrings.syncAllDone;
  }

  /// Всё, что не ушло, — по пункту на каждую беду, в порядке важности для
  /// обходчика: сначала то, что само не уйдёт.
  List<SyncTrouble> get troubles => [
        // Первым: обходчику важнее всего узнать, что новых задач не будет.
        if (workBlocked)
          SyncTrouble(
            title: MobileSupportStrings.workBlockedTitle,
            body: MobileSupportStrings.workBlockedBody(storeUri != null),
            rejected: true,
            opensStore: storeUri != null,
            isWorkBlocked: true,
          ),
        for (final reason in problemReportReasons)
          SyncTrouble(
            title: DialogStrings.syncProblemReportsRejectedTitle,
            body: reason,
            rejected: true,
          ),
        if (repairsRejected)
          const SyncTrouble(
            title: DialogStrings.syncRepairsRejectedTitle,
            body: DialogStrings.syncRepairsRejectedBody,
            rejected: true,
            opensRepairs: true,
          ),
        if (repairsLeft)
          const SyncTrouble(
            title: DialogStrings.syncRepairsFailedTitle,
            body: DialogStrings.syncRepairsFailedBody,
            opensRepairs: true,
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

  /// Разбирается в «Ремонтах» — окно предлагает туда перейти.
  final bool opensRepairs;

  /// Лечится обновлением — окно предлагает открыть RuStore.
  final bool opensStore;

  /// Пункт об ограничении работы ([SyncReport.workBlocked]) — своим
  /// признаком, а не по тексту заголовка.
  final bool isWorkBlocked;

  const SyncTrouble({
    required this.title,
    required this.body,
    this.rejected = false,
    this.opensRepairs = false,
    this.opensStore = false,
    this.isWorkBlocked = false,
  });
}
