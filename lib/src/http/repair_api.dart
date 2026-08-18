part of 'api.dart';

extension RepairApi on API {
  /// Список ремонтов.
  ///
  /// Фильтр «мои» передавать не нужно: для роли «обходчик» сервер сам сужает
  /// выдачу до ремонтов, где пользователь — ответственный **или** где ремонт
  /// назначен на его должность (`access_user_id` / `access_role_id` в
  /// `crud/repair.list_repairs`).
  Future<List<Repair>> getRepairs({
    List<String>? statuses,
    int limit = 100,
    int offset = 0,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    // Статусы уходят повторяющимся параметром (`?status=open&status=...`),
    // поэтому собираем через Uri, а не интерполяцией строки.
    final uri = Uri.parse('${API.baseUrl}/v1/repairs/').replace(
      queryParameters: <String, dynamic>{
        'limit': '$limit',
        'skip': '$offset',
        if (statuses != null && statuses.isNotEmpty) 'status': statuses,
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => Repair.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load repairs: ${response.statusCode}');
    }
  }

  /// Последние 10 закрытых ремонтов, доступных текущему пользователю.
  /// Отдельный серверный эндпоинт: постранично закрытые не листаются, и в
  /// офлайн-кэш они не попадают.
  Future<List<Repair>> getRecentClosedRepairs() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('${API.baseUrl}/v1/repairs/recent-closed'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => Repair.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load closed repairs: ${response.statusCode}');
    }
  }

  /// Нормы расхода ЗИП для оборудования.
  ///
  /// Фильтры те же, что использует форма создания ремонта в веб-админке:
  /// конкретное оборудование и назначение «для ремонта». Роль «обходчик» к
  /// эндпоинту допущена, доработок на сервере не требуется.
  /// Нормы расхода компании.
  ///
  /// [equipmentUuid] пустой — берём все: так их выгружает синхронизация в
  /// кэш. Форма создания ремонта передаёт конкретное оборудование, чтобы при
  /// живой связи получить свежий список без лишнего.
  Future<List<ConsumptionNorm>> getConsumptionNorms({
    String equipmentUuid = '',
    String usageType = ConsumptionNorm.repairUsageType,
    int limit = 100,
    int skip = 0,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${API.baseUrl}/v1/company/consumption_norms/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$skip',
      if (equipmentUuid.isNotEmpty) 'equipment_uuid': [equipmentUuid],
      'usage_type': [usageType],
    });

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => ConsumptionNorm.fromJson(json)).toList();
    }
    throw Exception(_serverDetail(
      response,
      'Не удалось загрузить нормы расхода: ${response.statusCode}',
    ));
  }

  /// Создать ремонт по оборудованию.
  ///
  /// `responsible_user_uuid` не передаём: для роли «обходчик» сервер сам
  /// назначает ответственным автора запроса. Состояние «В ремонте»
  /// оборудованию тоже ставит сервер — приложение его не трогает.
  ///
  /// [idempotencyKey] — ключ повторной отправки для офлайн-очереди. Сервер
  /// помнит пару «компания + ключ»: на повтор он возвращает **уже созданный**
  /// ремонт (код 200 вместо 201) и не шлёт уведомление второй раз. Без ключа
  /// поведение прежнее — каждый запрос создаёт новый ремонт.
  Future<Repair> createRepair({
    required String equipmentUuid,
    String? consumptionNormUuid,
    DateTime? startedAt,
    String? comment,
    String? idempotencyKey,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final body = <String, dynamic>{
      'equipment_uuid': equipmentUuid,
      if (consumptionNormUuid != null && consumptionNormUuid.isNotEmpty)
        'consumption_norm_uuid': consumptionNormUuid,
      if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };

    final response = await http
        .post(
          Uri.parse('${API.baseUrl}/v1/repairs/'),
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
            if (idempotencyKey != null && idempotencyKey.isNotEmpty)
              'Idempotency-Key': idempotencyKey,
          },
          body: jsonEncode(body),
        )
        .timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Repair.fromJson(data);
    }
    _throwServerError(
      response,
      'Не удалось создать ремонт: ${response.statusCode}',
    );
  }

  /// Приложить фотографии к ремонту. Снимки приходят сюда base64-строками —
  /// так их отдаёт `image_picker` в остальном приложении.
  ///
  /// Лимит 10 снимков на ремонт проверяет и сервер: он считает уже
  /// сохранённые плюс присланные в этом запросе, поэтому обойти его
  /// несколькими файлами за раз нельзя.
  ///
  /// [idempotencyKey] — ключ повторной отправки. Если ответ на запрос
  /// потерялся (обрыв связи после того, как сервер уже сохранил файл), повтор
  /// с тем же ключом вернёт те же самые снимки, а не создаст дубли. Ключ
  /// обязателен для очереди; из интерактивного экрана его можно не задавать.
  Future<List<RepairPhoto>> uploadRepairPhotos(
    String repairUuid,
    List<String> base64Images, {
    String? idempotencyKey,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${API.baseUrl}/v1/repairs/$repairUuid/photos'),
    );
    request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
    request.headers['accept'] = 'application/json';
    // Пустую строку сервер считает ошибкой (400), поэтому заголовок ставим
    // только когда ключ действительно есть.
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }

    for (int i = 0; i < base64Images.length; i++) {
      final base64Image = base64Images[i];
      final cleanBase64 =
          base64Image.contains(',') ? base64Image.split(',').last : base64Image;
      try {
        request.files.add(http.MultipartFile.fromBytes(
          'files',
          base64Decode(cleanBase64),
          filename: 'repair_photo_$i.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } catch (e) {
        // Битый снимок пропускаем — из-за него не должна срываться отправка
        // остальных, как и в sendScan.
        print('Ошибка декодирования фото ремонта $i: $e');
      }
    }

    final streamed = await request.send().timeout(API._uploadTimeout);
    final body =
        await streamed.stream.bytesToString().timeout(API._uploadTimeout);

    if (streamed.statusCode == 200 || streamed.statusCode == 201) {
      final List<dynamic> data = jsonDecode(body);
      return data
          .map((json) => RepairPhoto.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_detailFromBody(
      body,
      'Не удалось загрузить фото: ${streamed.statusCode}',
    ));
  }

  Future<void> deleteRepairPhoto(String repairUuid, String photoUuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.delete(
      Uri.parse('${API.baseUrl}/v1/repairs/$repairUuid/photos/$photoUuid'),
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);

    // 204 No Content — штатный успех удаления.
    if (response.statusCode == 204 ||
        response.statusCode == 200 ||
        response.statusCode == 201) {
      return;
    }
    throw Exception(_serverDetail(
      response,
      'Не удалось удалить фото: ${response.statusCode}',
    ));
  }

  /// Взять свободный ролевой ремонт на себя.
  ///
  /// Единственное поле запроса — `responsible_user_uuid` со своим uuid:
  /// `_validate_walker_update` на сервере пропускает захват только в таком
  /// виде и только если ремонт открыт, ответственного нет, а должность
  /// ремонта совпадает с должностью пользователя.
  ///
  /// Отказ приходит с русским текстом в `detail` — пробрасываем его наружу,
  /// чтобы экран показал причину, а не код ответа.
  Future<Repair> claimRepair(String repairUuid, String userUuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http
        .patch(
          Uri.parse('${API.baseUrl}/v1/repairs/$repairUuid'),
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'responsible_user_uuid': userUuid}),
        )
        .timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Repair.fromJson(data);
    }
    throw Exception(_serverDetail(
      response,
      'Не удалось взять ремонт в работу: ${response.statusCode}',
    ));
  }

  /// Сохранить комментарий и фактический расход; при [submitForReview] —
  /// заодно перевести ремонт в «На рассмотрении».
  ///
  /// Белый список полей для обходчика на сервере — ровно
  /// `{status, comment, actual_consumptions}`, любое лишнее поле приведёт к
  /// 403. Позиции с нулевым количеством не отправляем: схема требует
  /// `quantity > 0`, и такая строка уронила бы весь запрос.
  Future<Repair> updateRepair(
    String repairUuid, {
    String? comment,
    List<RepairConsumption>? consumptions,
    bool submitForReview = false,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final body = <String, dynamic>{
      if (comment != null) 'comment': comment,
      if (consumptions != null)
        'actual_consumptions': consumptions
            .where((item) => item.quantity > 0)
            .map((item) => {
                  'spare_part_uuid': item.sparePartUuid,
                  'quantity': item.quantity,
                })
            .toList(),
      if (submitForReview) 'status': RepairStatuses.underReview,
    };

    final response = await http
        .patch(
          Uri.parse('${API.baseUrl}/v1/repairs/$repairUuid'),
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Repair.fromJson(data);
    }
    _throwServerError(
      response,
      'Не удалось сохранить ремонт: ${response.statusCode}',
    );
  }

  /// Карточка ремонта целиком: с комментарием, фактическим расходом и фото —
  /// в списке этих полей нет.
  Future<Repair> getRepair(String repairUuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('${API.baseUrl}/v1/repairs/$repairUuid'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Repair.fromJson(data);
    }
    _throwServerError(
        response, 'Failed to load repair: ${response.statusCode}');
  }
}
