part of 'api.dart';

/// Раздел ППР (планово-предупредительный ремонт). ППР — это кампания
/// обслуживания со своим набором периодических задач. Мобильному клиенту
/// нужно лишь понять, какие периодические задачи входят в актуальные
/// (незакрытые) ППР, чтобы вынести их осмотры в отдельную группу «ППР».
extension PprApi on API {
  /// Возвращает UUID периодических задач, входящих в актуальные ППР
  /// (статусы `QUEUED` и `IN_PROGRESS`). Учитываются только активные
  /// членства задач в ППР (`active_membership == true`).
  ///
  /// Реализация: сначала список ППР по статусам, затем детали каждого ППР
  /// (список задач возвращается только в детальном ответе). Активных ППР
  /// обычно немного, поэтому N+1 здесь приемлем.
  Future<Set<String>> getActivePprPeriodicTaskUuids() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    const utf8Decoder = Utf8Decoder(allowMalformed: true);

    final listUrl = Uri.parse(
        '${API.baseUrl}/v1/company/ppr/?limit=100&statuses=QUEUED&statuses=IN_PROGRESS');
    final listResponse = await http.get(
      listUrl,
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);

    if (listResponse.statusCode != 200 && listResponse.statusCode != 201) {
      throw Exception('Failed to load PPR list: ${listResponse.statusCode}');
    }

    final List<dynamic> pprs =
        jsonDecode(utf8Decoder.convert(listResponse.bodyBytes));

    final Set<String> periodicTaskUuids = {};
    for (final ppr in pprs) {
      final pprUuid = ppr['uuid'] as String?;
      if (pprUuid == null) continue;

      final detailUrl =
          Uri.parse('${API.baseUrl}/v1/company/ppr/$pprUuid');
      final detailResponse = await http.get(
        detailUrl,
        headers: {'Authorization': 'Bearer ${API.jwtToken}'},
      ).timeout(API._readTimeout);

      if (detailResponse.statusCode != 200 &&
          detailResponse.statusCode != 201) {
        continue;
      }

      final Map<String, dynamic> detail =
          jsonDecode(utf8Decoder.convert(detailResponse.bodyBytes));
      final List<dynamic> tasks =
          (detail['tasks'] as List<dynamic>?) ?? const [];

      for (final task in tasks) {
        // Пропускаем задачи, которые уже не входят в ППР.
        if (task['active_membership'] != true) continue;
        final periodicTask = task['periodic_task'];
        final uuid = periodicTask is Map ? periodicTask['uuid'] : null;
        if (uuid is String && uuid.isNotEmpty) {
          periodicTaskUuids.add(uuid);
        }
      }
    }

    return periodicTaskUuids;
  }
}
