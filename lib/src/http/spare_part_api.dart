part of 'api.dart';

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
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse(
          '${API.baseUrl}/v1/company/spare_parts/?limit=${limit}&skip=${offset}'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => SparePart.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load spare parts: ${response.statusCode}');
    }
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
