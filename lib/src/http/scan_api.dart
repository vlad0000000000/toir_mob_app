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

        try {
          final bytes = base64Decode(cleanBase64);
          final file = http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: 'image_$i.jpg',
            contentType: MediaType('image', 'jpeg'),
          );
          request.files.add(file);
        } catch (e) {
          print('Ошибка декодирования изображения $i: $e');
        }
      }
    }

    // Без обёртки try/catch вокруг всего: раньше любая ошибка превращалась в
    // `Exception('Failed to send scan: ...')`, и очередь не могла отличить
    // обрыв связи от отказа сервера — а с расходом ЗИП разница стала
    // принципиальной. Сетевые исключения летят как есть, отказ сервера
    // приходит его же текстом.
    final response = await request.send().timeout(API._uploadTimeout);
    final responseBody =
        await response.stream.bytesToString().timeout(API._uploadTimeout);

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      // Код ответа приклеиваем к сообщению: по нему очередь отличает
      // временный сбой сервера (5xx) от отказа по существу (4xx), например
      // «Недостаточно ЗИП на складе». Из текста для обходчика метку
      // вырезает `scanErrorMessage`.
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
}
