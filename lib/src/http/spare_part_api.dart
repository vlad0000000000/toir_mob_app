part of 'api.dart';

/// Одна страница каталога ЗИП — вместе с тем, что удалено, если проход
/// инкрементальный.
class SparePartsPage {
  final List<SparePart> items;

  /// Позиции, которых на сервере больше нет: удалённые (сервер ведёт для них
  /// отдельную таблицу) и заархивированные интеграцией. Без этого списка
  /// клиент никогда бы не узнал об удалении — при полной перезаписи оно
  /// «исчезало» само, а при инкрементальном проходе позиция осталась бы в
  /// хранилище навсегда.
  final List<String> deletedUuids;

  /// Момент, до которого сервер посчитал изменения. Его же кладут в отметку
  /// последней синхронизации: брать локальное «сейчас» нельзя — часы
  /// телефона и сервера расходятся, и часть изменений выпала бы из окна.
  final DateTime? syncUntil;

  const SparePartsPage({
    required this.items,
    this.deletedUuids = const [],
    this.syncUntil,
  });
}

extension SparePartApi on API {
  /// Справочник ЗИП. Роль «обходчик» допущена к эндпоинту на сервере.
  ///
  /// Фильтры (склад, группа номенклатуры, поиск) сервер тоже умеет, но мы их
  /// не передаём: справочник выкачивается целиком ради офлайна, а экран
  /// фильтрует локально — без сети серверные фильтры всё равно недоступны.
  ///
  /// Параметр пагинации на бэкенде называется `skip`, хотя аргумент здесь —
  /// `offset`; так же во всех остальных методах проекта.
  Future<List<SparePart>> getSpareParts({limit = 100, offset = 0}) async {
    final page = await getSparePartsPage(limit: limit, offset: offset);
    return page.items;
  }

  /// Страница каталога ЗИП.
  ///
  /// С [updatedSince] сервер отдаёт не список, а объект
  /// `{items, deleted, sync_until}`: только изменившееся плюс uuid удалённых и
  /// заархивированных позиций. Без него — прежний полный список, как и раньше.
  ///
  /// [syncUntil] задаёт верхнюю границу окна и обязателен со второй страницы:
  /// без него сервер каждый раз брал бы «сейчас», и позиция, изменившаяся
  /// между запросами, съехала бы на уже прочитанную страницу — то есть
  /// потерялась бы. Границу берут из `sync_until` первого ответа.
  Future<SparePartsPage> getSparePartsPage({
    int limit = 100,
    int offset = 0,
    DateTime? updatedSince,
    DateTime? syncUntil,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${API.baseUrl}/v1/company/spare_parts/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$offset',
      if (updatedSince != null)
        'updated_since': updatedSince.toUtc().toIso8601String(),
      if (syncUntil != null) 'sync_until': syncUntil.toUtc().toIso8601String(),
    });

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to load spare parts: ${response.statusCode}');
    }
    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final decoded = jsonDecode(utf8Decoder.convert(response.bodyBytes));

    // Форму ответа определяем по самому ответу, а не по тому, что попросили:
    // так клиент переживёт сервер, который ещё не умеет инкрементальный режим
    // и на незнакомый параметр просто отдаст обычный список.
    if (decoded is List) {
      return SparePartsPage(
        items: [for (final json in decoded) SparePart.fromJson(json)],
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Failed to load spare parts: unexpected payload');
    }
    return SparePartsPage(
      items: [
        for (final json in (decoded['items'] as List<dynamic>? ?? const []))
          SparePart.fromJson(json as Map<String, dynamic>),
      ],
      deletedUuids: [
        for (final item in (decoded['deleted'] as List<dynamic>? ?? const []))
          if (item is Map<String, dynamic> && item['uuid'] is String)
            item['uuid'] as String,
      ],
      syncUntil: DateTime.tryParse(decoded['sync_until']?.toString() ?? ''),
    );
  }

  /// Одна позиция справочника — карточка ЗИП открывается по кэшу, но остаток
  /// перечитывает с сервера: каталог выкачивается раз в минуту, а в карточке
  /// показано крупное число, которому обходчик поверит буквально.
  ///
  /// Ответ (`SparePartDetailSchema`) содержит ещё и вложенную `stock_history`,
  /// но мы её игнорируем: лента грузится постранично отдельным запросом, а
  /// вложенная отдаётся целиком и без пагинации.
  Future<SparePart> getSparePart(String uuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/company/spare_parts/$uuid'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      return SparePart.fromJson(jsonDecode(decodedBytes));
    }
    throw Exception(_serverDetail(
      response,
      'Failed to load spare part: ${response.statusCode}',
    ));
  }

  /// История движений позиции. Сервер отдаёт записи от новых к старым и на
  /// первой странице (`skip=0`) кладёт общее число в заголовок
  /// `X-Total-Count` — из него берётся счётчик «показано N из M».
  Future<StockHistoryPage> getStockHistory({
    required String sparePartUuid,
    int limit = 50,
    int offset = 0,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/company/spare_parts/history'
          '?spare_part_uuid=$sparePartUuid&limit=$limit&skip=$offset'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return StockHistoryPage(
        entries: data.map((json) => StockHistoryEntry.fromJson(json)).toList(),
        total: int.tryParse(response.headers['x-total-count'] ?? ''),
      );
    }
    throw Exception(_serverDetail(
      response,
      'Failed to load stock history: ${response.statusCode}',
    ));
  }
}
