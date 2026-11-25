part of 'api.dart';

/// Сервисные объявления для мобильного приложения (бэкенд `81f644c`).
///
/// Везде `surface=mobile` и заголовок установки: по нему сервер выбирает
/// объявления о новой версии для этой сборки. Без зарегистрированной
/// установки не зовутся — объявления тогда приходят карточками 1.0 в ленте.
extension AnnouncementsApi on API {
  Map<String, String> _announcementHeaders(String installationId) => {
        'Authorization': 'Bearer ${API.jwtToken}',
        'Accept': 'application/json',
        API.installationHeader: installationId,
      };

  /// Текущие объявления: `{items, next_change_at}`. 409 `access_changed` —
  /// область доступа поменялась во время загрузки, повторить позже.
  Future<Map<String, dynamic>> getAnnouncements(String installationId) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }
    final response = await _client
        .get(
          Uri.parse('${API.baseUrl}/v1/system/announcements')
              .replace(queryParameters: {'surface': 'mobile'}),
          headers: _announcementHeaders(installationId),
        )
        .timeout(API._readTimeout);
    if (response.statusCode == 200) return _jsonObject(response);
    _throwServerError(response, 'Не удалось загрузить объявления');
  }

  /// Отмечает объявление прочитанным. 404 — объявления больше нет или оно не
  /// выдавалось ([ServerFailureException] с кодом 404): повторять незачем.
  Future<void> markAnnouncementRead(
    String installationId,
    String announcementUuid,
  ) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }
    final response = await _client
        .put(
          Uri.parse('${API.baseUrl}/v1/system/announcements/'
                  '$announcementUuid/read')
              .replace(queryParameters: {'surface': 'mobile'}),
          headers: _announcementHeaders(installationId),
        )
        .timeout(API._readTimeout);
    if (response.statusCode == 200) return;
    _throwServerError(response, 'Не удалось отметить объявление прочитанным');
  }

  Map<String, dynamic> _jsonObject(http.Response response) {
    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
    return data is Map<String, dynamic> ? data : const {};
  }
}
