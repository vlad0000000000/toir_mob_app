part of 'api.dart';

extension ScanApi on API {
  // Отправить осмотр (fault_inspection) с изображениями
  Future<bool> sendScan(Scan scan) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    var method = 'POST';
    if (scan.taskUuid != null && scan.taskUuid!.length > 0) {
      method = 'PATCH';
    }

    var request = http.MultipartRequest(
      method,
      Uri.parse('${API.baseUrl}/v1/company/fault_inspections/'),
    );
    if (method == 'PATCH') {
      request = http.MultipartRequest(
        method,
        Uri.parse(
            '${API.baseUrl}/v1/company/fault_inspections/${scan.taskUuid}'),
      );
    }

    request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
    request.headers['accept'] = 'application/json';

    var scanJson = scan.toJson();
    scanJson.forEach((key, value) {
      if (key != 'files' && value != null && (value as String).length > 0) {
        request.fields[key] = value.toString();
      }
    });

    if (scan.files != null && scan.files!.isNotEmpty) {
      for (int i = 0; i < scan.files!.length; i++) {
        final base64Image = scan.files![i];

        final cleanBase64 = base64Image.contains(',')
            ? base64Image.split(',').last
            : base64Image;

        // Кадр не разобрался — прекращаем отправку, а не отправляем осмотр
        // без него.
        //
        // Раньше ошибка уходила в `print`, запрос летел с оставшимися
        // снимками, сервер отвечал 200, и очередь считала осмотр
        // доставленным. Снимок исчезал молча: ни обходчик, ни администратор
        // никогда не узнали бы, что кадр вообще был. А испортиться строка
        // может — на то она и лежит в базе на диске.
        //
        // Исключение намеренно не ловим здесь в отказ: `syncScans`
        // классифицирует его как невосстановимый, осмотр останется в очереди
        // с внятной причиной, и обходчик сможет переснять.
        final List<int> bytes;
        try {
          bytes = base64Decode(cleanBase64);
        } catch (e) {
          throw Exception(
            'Снимок ${i + 1} повреждён и не может быть отправлен: $e',
          );
        }
        request.files.add(http.MultipartFile.fromBytes(
          'files',
          bytes,
          filename: 'image_$i.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      }
    }

    // Без обёртки try/catch вокруг всего: раньше любая ошибка превращалась в
    // `Exception('Failed to send scan: ...')`, и очередь не могла отличить
    // обрыв связи от отказа сервера — а с расходом ЗИП разница стала
    // принципиальной. Сетевые исключения летят как есть, отказ сервера
    // приходит его же текстом.
    final response = await _client.send(request).timeout(API._uploadTimeout);
    final responseBody =
        await response.stream.bytesToString().timeout(API._uploadTimeout);

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      // Нехватку ЗИП сервер отдаёт машиночитаемо (409 + detail_code +
      // shortages) — разбираем её в типизированное исключение, чтобы экран
      // разрешения конфликта показал серверные числа, а не считал их по
      // локальному справочнику, который между синхронизациями отстаёт.
      final stockError = _parseInsufficientStock(responseBody);
      if (stockError != null) throw stockError;

      // Код ответа приклеиваем к сообщению: по нему очередь отличает
      // временный сбой сервера (5xx) от отказа по существу (4xx). Из текста
      // для обходчика метку вырезает `scanErrorMessage`.
      throw Exception(
        '${_detailFromBody(responseBody, 'Не удалось отправить осмотр')}'
        ' [HTTP ${response.statusCode}]',
      );
    }

    try {
      final data = jsonDecode(responseBody);
      return data is Map<String, dynamic> && data.containsKey('uuid');
    } catch (_) {
      // Успешный код, но тело не разобралось — считаем неудачей, осмотр
      // останется в очереди и уйдёт следующим проходом.
      return false;
    }
  }

  /// Разбирает тело отказа по нехватке ЗИП. `null` — отказ по другой причине.
  ///
  /// Опознаём по `detail_code`, а не по тексту: формулировка `detail` на
  /// сервере может меняться, код — нет.
  InsufficientStockException? _parseInsufficientStock(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      if (data['detail_code'] != 'insufficient_stock') return null;
      final raw = data['shortages'];
      return InsufficientStockException(
        data['detail'] as String? ?? 'Недостаточно ЗИП на складе',
        [
          if (raw is List)
            for (final item in raw)
              if (item is Map<String, dynamic>)
                InsufficientStockItem.fromJson(item),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
