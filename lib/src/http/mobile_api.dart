part of 'api.dart';

extension MobileApi on API {
  /// Регистрирует установку [installationId] со сборкой [build] в текущем
  /// аккаунте (`PUT /v1/mobile/installations/{uuid}`, бэкенд `81f644c`).
  ///
  /// Повтор безопасен: сервер обновляет сборку и время последнего
  /// подключения. Ответ — установка со статусом поддержки (`status`,
  /// `support_ends_at`, `update_url`).
  Future<Map<String, dynamic>> putMobileInstallation(
    String installationId,
    MobileBuild build,
  ) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client
        .put(
          Uri.parse('${API.baseUrl}/v1/mobile/installations/$installationId'),
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(build.toJson()),
        )
        .timeout(API._readTimeout);

    if (response.statusCode == 200) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
      return data is Map<String, dynamic> ? data : const {};
    }
    _throwServerError(response, 'Не удалось зарегистрировать приложение');
  }

  /// Статус поддержки версии установки [installationId]
  /// (`GET /v1/mobile/support-status`). 404 — сервер не связывает установку
  /// с этим аккаунтом и сборкой: не зарегистрирована, после неё на телефоне
  /// входил другой сотрудник или [build] не та, что зарегистрирована
  /// (бэкенд `811c4dc`) — [ServerFailureException] с кодом 404.
  Future<Map<String, dynamic>> getMobileSupportStatus(
    String installationId, {
    int? build,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/mobile/support-status'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
        'Accept': 'application/json',
        API.installationHeader: installationId,
        if (build != null) API.buildHeader: '$build',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
      return data is Map<String, dynamic> ? data : const {};
    }
    _throwServerError(response, 'Не удалось узнать статус версии');
  }
}
