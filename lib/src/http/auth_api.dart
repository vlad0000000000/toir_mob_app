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
      user.effectiveRole = data['effective_role'];
      user.customRoleId = data['custom_role_id'];
      user.uuid = data['uuid'];
      return user;
    } else {
      throw Exception('Failed to authenticate: ${response.statusCode}');
    }
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

  Future<List<User>> getUsers() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/walker/list'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users: ${response.statusCode}');
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
    } catch (e) {
      // Разбор обрыва связи здесь был выписан вручную тремя ветками подряд и
      // не знал про `ClientException` — вход без сервера падал не в «нет
      // связи», а в общий «не удалось войти». Признак теперь общий на всё
      // приложение.
      if (isOfflineError(e)) throw NoConnectionException();
      throw Exception('Failed to login: $e');
    }
  }

  Future<Session> getCurrentSession() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/session/'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      List<Session> sessions =
          data.map((json) => Session.fromJson(json)).toList();
      sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
      if (sessions.length > 0) {
        API.currentSession = sessions.last;
        return sessions.last;
      }
      throw Exception('No session found');
    } else {
      throw Exception('Failed to load session: ${response.statusCode}');
    }
  }
}
