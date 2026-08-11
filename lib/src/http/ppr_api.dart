part of 'api.dart';

/// Раздел ППР (планово-предупредительный ремонт). У ППР свой набор
/// периодических задач и срок проведения. Мобильному клиенту
/// нужны актуальные (незакрытые) ППР и состав их задач: по ним строится
/// кнопка «ППР» на главном экране, экран задач ППР и группа «ППР» в списке
/// задач оборудования.
extension PprApi on API {
  /// Возвращает актуальные ППР (статусы `QUEUED` и `IN_PROGRESS`) вместе с
  /// UUID входящих в них периодических задач. Учитываются только активные
  /// членства задач в ППР (`active_membership == true`).
  ///
  /// Реализация: сначала список ППР по статусам, затем детали каждого ППР
  /// (список задач возвращается только в детальном ответе). Активных ППР
  /// обычно немного, поэтому N+1 здесь приемлем.
  Future<List<Ppr>> getActivePprs() async {
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

    final List<Ppr> result = [];
    for (final ppr in pprs) {
      if (ppr is! Map<String, dynamic>) continue;
      final pprUuid = ppr['uuid'] as String?;
      if (pprUuid == null) continue;

      final detailUrl = Uri.parse('${API.baseUrl}/v1/company/ppr/$pprUuid');
      final detailResponse = await http.get(
        detailUrl,
        headers: {'Authorization': 'Bearer ${API.jwtToken}'},
      ).timeout(API._readTimeout);

      // Детали не отдались — прерываем всю синхронизацию ППР. Пропустить
      // один ППР нельзя: он исчезнет из списков до следующего удачного
      // обхода, а сохранённый прошлый снимок останется целым.
      if (detailResponse.statusCode != 200 &&
          detailResponse.statusCode != 201) {
        throw Exception(
            'Failed to load PPR $pprUuid: ${detailResponse.statusCode}');
      }

      final Map<String, dynamic> detail =
          jsonDecode(utf8Decoder.convert(detailResponse.bodyBytes));
      final List<dynamic> tasks =
          (detail['tasks'] as List<dynamic>?) ?? const [];

      final Set<String> periodicTaskUuids = {};
      final Set<String> inspectionUuids = {};
      for (final task in tasks) {
        // Пропускаем задачи, которые уже не входят в ППР.
        if (task['active_membership'] != true) continue;
        final periodicTask = task['periodic_task'];
        final uuid = periodicTask is Map ? periodicTask['uuid'] : null;
        if (uuid is String && uuid.isNotEmpty) {
          periodicTaskUuids.add(uuid);
        }
        // Осмотр задачи ППР — пока он не выполнен, его нужно показать
        // независимо от срока.
        if (task['is_completed'] == true) continue;
        final inspection = task['inspection'];
        if (inspection is Map && inspection['result_status'] != 'closed') {
          final inspectionUuid = inspection['uuid'];
          if (inspectionUuid is String && inspectionUuid.isNotEmpty) {
            inspectionUuids.add(inspectionUuid);
          }
        }
      }

      result.add(Ppr.fromListJson(ppr, periodicTaskUuids, inspectionUuids));
    }

    return result;
  }
}
