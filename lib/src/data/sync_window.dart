import '../http/api.dart';

/// Всё, что сервер сообщил за одно окно справочника.
///
/// [syncUntil] `null` — сервер инкрементальный режим не понял (старый
/// сервер, обычный список): границу сохранять нечем, клиент остаётся на
/// полных проходах.
typedef SyncWindow<T> = ({
  List<T> items,
  Set<String> deleted,
  DateTime? syncUntil,
});

/// Выбирает окно `(since, sync_until]` справочника **целиком** — и только
/// тогда возвращает. Записывать данные и двигать границу вызывающий должен
/// по результату, а не по ходу: оборвись выборка на середине (ошибка сети,
/// предохранитель), неполное окно не должно лечь ни в бокс, ни в границу.
///
/// Сначала курсором (`pagination=cursor`): страницы связаны подписанным
/// курсором, и удаление записи между запросами ничего не сдвигает. По `skip`
/// так случалось: запись выпадала из выборки, смещение уезжало, и следующая
/// за ней оказывалась пропущенной до полной сверки. Конец окна — **только**
/// `next_cursor == null`: пустая страница [SyncPage.items] не конец, сервер
/// может ещё отдавать удаления, у них свой отдельный счёт страниц.
///
/// Сервер курсор не умеет (в ответе нет `next_cursor`) — прежний проход по
/// `skip` с закреплённым `sync_until`.
///
/// [fullPass] `false` — инкрементальный проход: если сервер не понял окна,
/// дальше не качаем — вызывающий перейдёт на полный, и выкачанное здесь
/// всё равно выбросил бы.
///
/// Курсор отклонён (422, [SyncCursorRejected]) — окно начинается заново от
/// [since], один раз; повтор безвреден, записи кладутся по ключу.
///
/// [guard] — предохранитель от бесконечной выборки, получает число
/// выбранных записей и бросает, если их подозрительно много.
Future<SyncWindow<T>> loadSyncWindow<T>(
  SyncPageFetch<T> fetch, {
  required DateTime since,
  required bool fullPass,
  required void Function(int loaded) guard,
  int pageSize = 100,
}) async {
  for (var attempt = 0;; attempt++) {
    try {
      return await _loadOnce(fetch, since, fullPass, guard, pageSize);
    } on SyncCursorRejected {
      if (attempt >= 1) rethrow;
    }
  }
}

Future<SyncWindow<T>> _loadOnce<T>(
  SyncPageFetch<T> fetch,
  DateTime since,
  bool fullPass,
  void Function(int loaded) guard,
  int pageSize,
) async {
  final first = await fetch(
    limit: pageSize,
    offset: 0,
    updatedSince: since,
    cursorMode: true,
  );
  final items = <T>[...first.items];
  final deleted = <String>{...first.deletedUuids};

  if (first.cursorMode) {
    var next = first.nextCursor;
    while (next != null) {
      final page = await fetch(limit: pageSize, cursorMode: true, cursor: next);
      items.addAll(page.items);
      deleted.addAll(page.deletedUuids);
      guard(items.length + deleted.length);
      next = page.nextCursor;
    }
    return (items: items, deleted: deleted, syncUntil: first.syncUntil);
  }

  if (first.syncUntil == null && !fullPass) {
    return (items: items, deleted: deleted, syncUntil: null);
  }
  if (first.items.length == pageSize) {
    for (var offset = pageSize;; offset += pageSize) {
      final page = await fetch(
        limit: pageSize,
        offset: offset,
        updatedSince: since,
        syncUntil: first.syncUntil,
      );
      items.addAll(page.items);
      deleted.addAll(page.deletedUuids);
      if (page.items.length < pageSize) break;
      guard(offset);
    }
  }
  return (items: items, deleted: deleted, syncUntil: first.syncUntil);
}
