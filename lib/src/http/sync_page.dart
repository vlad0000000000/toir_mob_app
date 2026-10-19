part of 'api.dart';

/// Страница инкрементального справочника: что изменилось, что удалено и до
/// какого момента сервер посчитал изменения.
///
/// Общая для оборудования и типовых неисправностей: протокол у них один и тот
/// же (`updated_since` + `sync_until` + `deleted`), отличается только тип
/// записи. У каталога ЗИП своя [SparePartsPage] — она появилась первой и
/// менять её ради общего типа значило бы трогать работающую синхронизацию.
class SyncPage<T> {
  final List<T> items;

  /// Записи, которых на сервере больше нет: удалённые и заархивированные
  /// интеграцией. Без этого списка удалённая позиция осталась бы в хранилище
  /// навсегда — полная перезапись её просто не возвращала, а инкрементальный
  /// проход о ней не узнает.
  final List<String> deletedUuids;

  /// Граница окна по часам **сервера**. Её же кладут в курсор: часы телефона
  /// и сервера расходятся, и подставить местное «сейчас» значило бы либо
  /// потерять изменения, либо тянуть их повторно.
  final DateTime? syncUntil;

  /// Сервер ответил в курсорном режиме (`pagination=cursor`): в ответе есть
  /// поле `next_cursor`, пусть и `null`. Старый сервер незнакомый параметр
  /// пропускает и отвечает по-старому — тогда `false`, и клиент идёт по
  /// `skip`.
  final bool cursorMode;

  /// Подписанный курсор следующей страницы. `null` в курсорном режиме —
  /// окно выбрано **целиком**, и только это признак конца: пустой [items]
  /// им не является — сервер может ещё отдавать [deletedUuids].
  final String? nextCursor;

  const SyncPage({
    required this.items,
    this.deletedUuids = const [],
    this.syncUntil,
    this.cursorMode = false,
    this.nextCursor,
  });
}

/// Курсор отклонён сервером (422): подпись не сошлась, устарел, другие
/// фильтры. Окно начинают заново от сохранённой границы.
class SyncCursorRejected implements Exception {
  const SyncCursorRejected();

  @override
  String toString() => 'SyncCursorRejected';
}

/// Метод API, отдающий страницу инкрементального справочника, — им
/// пользуется `loadSyncWindow`.
typedef SyncPageFetch<T> = Future<SyncPage<T>> Function({
  int limit,
  int offset,
  DateTime? updatedSince,
  DateTime? syncUntil,
  bool cursorMode,
  String? cursor,
});

/// Параметры запроса страницы справочника.
///
/// `skip` — имя параметра на бэкенде, хотя аргумент у методов называется
/// `offset`; так во всех остальных методах проекта.
///
/// Курсорный режим ([cursorMode]): `pagination=cursor`, без `skip`. Первая
/// страница несёт окно (`updated_since`, при нужде `sync_until`), следующие —
/// только [cursor]: окно и фильтры зашиты в него сервером, и передавать их
/// повторно не нужно.
Map<String, String> syncPageParams({
  required int limit,
  required int offset,
  DateTime? updatedSince,
  DateTime? syncUntil,
  bool cursorMode = false,
  String? cursor,
}) {
  if (cursorMode) {
    return <String, String>{
      'limit': '$limit',
      'pagination': 'cursor',
      if (cursor != null)
        'cursor': cursor
      else ...{
        if (updatedSince != null)
          'updated_since': updatedSince.toUtc().toIso8601String(),
        if (syncUntil != null)
          'sync_until': syncUntil.toUtc().toIso8601String(),
      },
    };
  }
  return <String, String>{
    'limit': '$limit',
    'skip': '$offset',
    if (updatedSince != null)
      'updated_since': updatedSince.toUtc().toIso8601String(),
    if (syncUntil != null) 'sync_until': syncUntil.toUtc().toIso8601String(),
  };
}

/// Разбирает ответ справочника в обеих формах.
///
/// Форму определяем по самому ответу, а не по тому, что попросили: так клиент
/// переживёт сервер, который инкрементальный режим ещё не умеет и на
/// незнакомый параметр просто отдаёт обычный список. [SyncPage.syncUntil] у
/// такого ответа пустой — вызывающий по нему и понимает, что остаётся на
/// полных проходах.
SyncPage<T> parseSyncPage<T>(
  dynamic decoded,
  T Function(Map<String, dynamic>) fromJson,
  String failureMessage,
) {
  if (decoded is List) {
    return SyncPage<T>(
      items: [
        for (final json in decoded) fromJson(json as Map<String, dynamic>),
      ],
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw Exception('$failureMessage: unexpected payload');
  }
  return SyncPage<T>(
    items: [
      for (final json in (decoded['items'] as List<dynamic>? ?? const []))
        fromJson(json as Map<String, dynamic>),
    ],
    deletedUuids: [
      for (final item in (decoded['deleted'] as List<dynamic>? ?? const []))
        if (item is Map<String, dynamic> && item['uuid'] is String)
          item['uuid'] as String,
    ],
    syncUntil: DateTime.tryParse(decoded['sync_until']?.toString() ?? ''),
    // Режим — по наличию поля, а не по значению: `null` у него и значит
    // «окно выбрано целиком».
    cursorMode: decoded.containsKey('next_cursor'),
    nextCursor: decoded['next_cursor'] as String?,
  );
}
