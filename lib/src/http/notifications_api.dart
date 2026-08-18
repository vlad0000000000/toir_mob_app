part of 'api.dart';

extension NotificationsApi on API {
  Future<NotificationSettings> getNotificationSettings() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/company/notifications/mobile/settings'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return NotificationSettings.fromJson(data);
    } else {
      throw Exception(
          'Failed to load notification settings: ${response.statusCode}');
    }
  }

  Future<NotificationSettings> patchNotificationSettings(
      Map<String, dynamic> partial) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client
        .patch(
          Uri.parse('${API.baseUrl}/v1/company/notifications/mobile/settings'),
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(partial),
        )
        .timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return NotificationSettings.fromJson(data);
    } else {
      throw Exception(
          'Failed to update notification settings: ${response.statusCode}');
    }
  }

  Future<NotificationListResponse> getNotifications({
    int skip = 0,
    int limit = 50,
    List<String>? notificationTypes,
    List<String>? statuses,
    String? equipmentUuid,
    String? priority,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final params = <String, String>{
      'skip': skip.toString(),
      'limit': limit.toString(),
    };
    if (notificationTypes != null && notificationTypes.isNotEmpty) {
      params['notification_types'] = notificationTypes.join(',');
    }
    if (statuses != null && statuses.isNotEmpty) {
      params['statuses'] = statuses.join(',');
    }
    if (equipmentUuid != null) {
      params['equipment_uuid'] = equipmentUuid;
    }
    if (priority != null) {
      params['priority'] = priority;
    }
    if (createdFrom != null) {
      params['created_from'] = createdFrom.toUtc().toIso8601String();
    }
    if (createdTo != null) {
      params['created_to'] = createdTo.toUtc().toIso8601String();
    }

    final uri = Uri.parse('${API.baseUrl}/v1/company/notifications/mobile')
        .replace(queryParameters: params);

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return NotificationListResponse.fromJson(data);
    } else {
      throw Exception('Failed to load notifications: ${response.statusCode}');
    }
  }

  Future<int> markNotificationRead(String notificationUuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.post(
      Uri.parse(
          '${API.baseUrl}/v1/company/notifications/mobile/$notificationUuid/read'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return (data['unread_count'] ?? 0) as int;
    } else {
      throw Exception(
          'Failed to mark notification read: ${response.statusCode}');
    }
  }

  Future<StreamedResponseHandle> openNotificationStream() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final request = http.Request('GET',
        Uri.parse('${API.baseUrl}/v1/company/notifications/mobile/stream'));
    request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    // Поток живёт долго и закрывается своим `StreamedResponseHandle`, поэтому
    // общий клиент ему не подходит — закрытие ручки убило бы и остальные
    // запросы. Но клиент берём тот же по настройкам: попытка соединения
    // сдаётся за три секунды, а не висит до таймаута.
    if (API.isServerKnownUnreachable) {
      throw const SocketException('Сервер не отвечает, попытка отложена');
    }
    final client = _newIoClient();
    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (error) {
      if (isOfflineError(error)) API.markServerUnreachable();
      client.close();
      rethrow;
    }
    API.markServerReachable();
    if (response.statusCode != 200) {
      client.close();
      throw Exception('Failed to open stream: ${response.statusCode}');
    }
    return StreamedResponseHandle(client: client, response: response);
  }
}
