part of 'api.dart';

extension AuthApi on API {
  Future<User> me(String meJWTToken) async {
    _guardOffline();
    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/user/me'),
      headers: {
        'Authorization': 'Bearer $meJWTToken',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      User user = User(role: '', username: '');
      // Профиль — только от сервера с ролями доступа: у него в ответе есть
      // `access_scope`. Сервер прошлой версии этих полей не знает, и разбор
      // такого ответа дал бы «нет компании, нет роли» — обходчика не пустили
      // бы вовсе. Профиль тогда неизвестен (`null`), и приложение работает,
      // как до ролей: ничего не запирает, решает сервер.
      final profile = AccessProfile.fromServer(data);
      user.accessProfile = profile;
      user.companyFlags = CompanyFlags.fromMe(data);
      final scope = data['access_scope'];
      if (scope is Map && scope['company_id'] != null) {
        user.companyId = '${scope['company_id']}';
      }
      // Поля совместимости бэкенд отдаёт как `null`, когда у роли нет
      // направления. Раньше они читались как обязательные: `null` в поле
      // `int` — это `TypeError`, а не `Exception`, мимо всех веток разбора
      // входа, и обходчик без направления видел «не удалось войти».
      user.effectiveRole = data['effective_role'] as String? ?? '';
      user.customRoleId = data['custom_role_id'] as int? ?? -1;
      user.uuid = data['uuid'] as String? ?? '';
      return user;
    }
    // Отказ — через общий разбор: 401 отдельно, у прочих код ответа. По нему
    // вход отличает «сервер ответил отказом» (пускать по локальной записи
    // нельзя) от «сервер не дошёл» (можно).
    _throwServerError(response, 'Не удалось получить данные пользователя');
  }

  Future<Company> getCompany() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/company/me'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Company.fromJson(data);
    } else {
      throw Exception('Failed to load company: ${response.statusCode}');
    }
  }

  Future<User> login(String username, String password) async {
    try {
      _guardOffline();
      final response = await _client
          .post(
            Uri.parse('${API.baseUrl}/v1/auth/login'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(API._readTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        // Сервер пускает на вход и при истёкшем тарифе — токены выдаёт, а
        // состояние доступа кладёт рядом. Работать при нём нельзя: следующий
        // же запрос получит 403. Не пускаем сразу, с понятной причиной.
        final accessState = responseData['access_state'];
        if (accessState is String &&
            SubscriptionBlockedException.blockedStates.contains(accessState)) {
          throw SubscriptionBlockedException(accessState);
        }
        User user = User(role: responseData['role'], username: username);
        user.password = password;
        user.JWTToken = responseData['access_token'];
        return user;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw InvalidCredentialsException();
      } else {
        throw Exception('Failed to login: ${response.statusCode}');
      }
    } on InvalidCredentialsException {
      rethrow;
    } on NoConnectionException {
      rethrow;
    } on SubscriptionBlockedException {
      rethrow;
    } catch (e) {
      // Разбор обрыва связи здесь был выписан вручную тремя ветками подряд и
      // не знал про `ClientException` — вход без сервера падал не в «нет
      // связи», а в общий «не удалось войти». Признак теперь общий на всё
      // приложение.
      if (isOfflineError(e)) throw NoConnectionException();
      throw Exception('Failed to login: $e');
    }
  }
}
