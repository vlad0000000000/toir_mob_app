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

    try {
      final response = await request.send().timeout(API._uploadTimeout);

      final responseBody =
          await response.stream.bytesToString().timeout(API._uploadTimeout);
      final Map<String, dynamic> responseData = jsonDecode(responseBody);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Failed to send scan: ${response.statusCode} - $responseBody');
      }

      if (responseData.containsKey('uuid')) {
        return true;
      }
    } catch (e) {
      throw Exception('Failed to send scan: $e');
    }
    return false;
  }
}
