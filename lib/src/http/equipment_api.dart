part of 'api.dart';

extension EquipmentApi on API {
  Future<List<InventoryRecord>> getEquipment({limit = 10, offset = 0}) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse(
          '${API.baseUrl}/v1/company/equipment?limit=${limit}&skip=${offset}'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.statusCode}');
    }
  }

  Future<List<InventoryRecord>> getInventoryRecords(
      {limit = 10, offset = 0}) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse(
          '${API.baseUrl}/v1/inventory_record/list?limit=${limit}&offset=${offset}'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.statusCode}');
    }
  }

  Future<EquipmentState> getEquipmentStates() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${API.baseUrl}/v1/company/equipment/states');

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return EquipmentState.fromJson(data);
    } else {
      throw Exception(
          'Failed to load equipment states: ${response.statusCode}');
    }
  }

  Future<List<UsageUnit>> getUsageUnitTypes() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url =
        Uri.parse('${API.baseUrl}/v1/company/equipment/usage-unit-types');

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      final List<dynamic> unitTypes = data['unit_types'];
      return unitTypes.map((json) => UsageUnit.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load usage unit types: ${response.statusCode}');
    }
  }

  Future<bool> updateUsageParameter(UsageUpdate usageUpdate) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '${API.baseUrl}/v1/company/equipment/${usageUpdate.equipmentUuid}/usage-parameters/${usageUpdate.usageParameterUuid}');

    final response = await _client
        .patch(
          url,
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'current_value': usageUpdate.usageParameterValue}),
        )
        .timeout(API._readTimeout);

    // Сперва код ответа, только потом разбор тела.
    //
    // Раньше `jsonDecode` стоял выше и был типизирован как `Map`: ответ шлюза
    // 502 с HTML-телом или JSON-массив вместо объекта давали `FormatException`
    // или `TypeError` вместо заготовленного сообщения. Для очереди наработки
    // это стало важно с тех пор, как она научилась отличать временный сбой от
    // отказа по существу: нераспознаваемое исключение классифицировать нечем.
    //
    // `_throwServerError` вместо голого `Exception` — по той же причине: он
    // выделяет 401 в `AuthExpiredException` и несёт код ответа в
    // `ServerFailureException`, по которому `isRetryableScanError` и решает,
    // повторять отправку или пометить наработку отклонённой.
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwServerError(response, 'Не удалось сохранить наработку');
    }

    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> && decoded.containsKey('uuid');
    } catch (_) {
      // Успешный код, но тело не разобралось — считаем неудачей: наработка
      // останется в очереди и уйдёт следующим проходом. Так же поступает
      // `sendScan`.
      return false;
    }
  }

  Future<bool> updateEquipmentState(String equipmentUuid, String state) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    var request = http.MultipartRequest(
      'PATCH',
      Uri.parse('${API.baseUrl}/v1/company/equipment/$equipmentUuid'),
    );

    request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
    request.headers['accept'] = 'application/json';
    request.fields['state'] = state;

    try {
      final response = await _client.send(request).timeout(API._readTimeout);

      final responseBody =
          await response.stream.bytesToString().timeout(API._readTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Failed to update equipment state: ${response.statusCode} - $responseBody');
      }

      return true;
    } catch (e) {
      throw Exception('Failed to update equipment state: $e');
    }
  }
}
