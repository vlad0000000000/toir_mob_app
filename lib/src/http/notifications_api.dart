part of 'api.dart';

extension NotificationsApi on API {
  Future<NotificationSettings> getNotificationSettings() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
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

    final response = await http.patch(
      Uri.parse('${API.baseUrl}/v1/company/notifications/mobile/settings'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(partial),
    ).timeout(API._readTimeout);

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

    final response = await http.get(
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

    final response = await http.post(
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

    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode != 200) {
      client.close();
      throw Exception('Failed to open stream: ${response.statusCode}');
    }
    return StreamedResponseHandle(client: client, response: response);
  }
}
