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

  const SyncPage({
    required this.items,
    this.deletedUuids = const [],
    this.syncUntil,
  });
}

/// Параметры запроса страницы справочника.
///
/// `skip` — имя параметра на бэкенде, хотя аргумент у методов называется
/// `offset`; так во всех остальных методах проекта.
Map<String, String> syncPageParams({
  required int limit,
  required int offset,
  DateTime? updatedSince,
  DateTime? syncUntil,
}) {
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
  );
}
