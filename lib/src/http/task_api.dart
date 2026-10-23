part of 'api.dart';

extension TaskApi on API {
  /// Открытые задачи текущего обходчика — одним из двух видов назначения.
  ///
  /// [byInspector] `false` — где он **ответственный** (`responsible_user`):
  /// так назначаются открытые заявки. `true` — где он **исполнитель**
  /// (`inspector`): так сервер назначает экземпляр задачи при
  /// переназначении (`POST /fault_inspections/{uuid}/reassign` пишет
  /// исполнителя и переводит задачу в `open`, ответственного не трогает).
  /// Раньше второго вида мобилка не запрашивала вовсе, и переназначенная
  /// задача пропадала у нового исполнителя.
  Future<List<Task>> getCurrentOpenTasks({
    limit = 50,
    offset = 0,
    bool byInspector = false,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    // Отбор по ответственному делает сервер, а не телефон.
    //
    // Раньше запрос тянул открытые заявки **всей компании**, и лишнее
    // отбрасывалось уже здесь, в `where` ниже. При сотне обходчиков это
    // означало скачать в сто раз больше, чем нужно, — и так на каждой
    // синхронизации. Фильтр у эндпоинта был всё это время, им просто не
    // пользовались.
    //
    // Если uuid по какой-то причине неизвестен, фильтр не ставим и работаем
    // как раньше: лучше лишний трафик, чем пустой список задач.
    final userUuid = GlobalState.authUser?.uuid;
    final url = Uri.parse('${API.baseUrl}/v1/company/fault_inspections/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$offset',
      'status': 'open',
      if (userUuid != null && userUuid.isNotEmpty)
        byInspector ? 'inspector_uuids' : 'responsible_user_uuids': [userUuid],
    });

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      var scheduled = data
          .where((json) {
            return (json['result_status'] as String) == 'open' &&
                json[byInspector ? 'inspector' : 'responsible_user'] != null;
          })
          .map((json) => Task.fromJson(json))
          .toList();
      return scheduled;
    } else {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
  }

  /// Страница плановых задач. [fetched] — сколько записей пришло со страницы
  /// **до** отбора на телефоне: по нему загрузка понимает, что страницы
  /// кончились. Отобранных ([tasks]) бывает меньше и на полной странице —
  /// часть отсекает окно времени ниже.
  Future<({List<Task> tasks, int fetched})> getCurrentTasks({
    limit = 50,
    offset = 0,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    // `only_my_roles` — серверный отбор по должности обходчика. Плановые
    // осмотры назначаются не на человека, а на должность, и без этого
    // параметра сервер отдавал их все: на стенде 2217 записей, 23 страницы
    // подряд — и повторялось это на каждый вход в «Задачи», «Сканер», после
    // каждой отправки осмотра и фоновым циклом раз в минуту. Заодно на
    // телефон переставали приезжать задачи чужих должностей.
    //
    // `executable_only` — только то, что обходчик может выполнить: свободные
    // экземпляры и взятые им самим. Без него среди задач направления
    // приезжали взятые коллегой, и отсекать их приходилось на телефоне по
    // `allowed_actions` (`isScheduledTaskAvailable`). Отсев на телефоне
    // остаётся — для сервера прошлой версии, который параметр пропустит.
    final url = Uri.parse('${API.baseUrl}/v1/company/fault_inspections/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$offset',
      'status': 'scheduled',
      'only_my_roles': 'true',
      'executable_only': 'true',
    });

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      var now = DateTime.now().toUtc();
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      var scheduled = data
          .where((json) {
            return (json['result_status'] as String) == 'scheduled' &&
                json['periodic_task'] != null &&
                json['periodic_task']['next_due_at'] != null &&
                json['periodic_task']['last_run_at'] != null;
          })
          .where((json) {
            var a = (DateTime.parse(json['periodic_task']['last_run_at']));
            var b = (DateTime.parse(json['periodic_task']['next_due_at']));
            var len = b.difference(a);
            var c = (DateTime.parse(json['created_at']));
            var filteredA = now.compareTo(c);
            var filteredB = now.compareTo(c.add(len));
            return filteredA == 1 && filteredB == -1;
          })
          .map((json) => Task.fromJson(json))
          .toList();

      var once = data
          .where((json) {
            return (json['result_status'] as String) == 'scheduled' &&
                json['periodic_task'] != null &&
                json['periodic_task']['periodicity_rule'] == 'once';
          })
          .map((json) => Task.fromJson(json))
          .toList();
      for (var task in once) {
        scheduled.add(task);
      }

      var to = data
          .where((json) {
            return (json['result_status'] as String) == 'scheduled' &&
                json['periodic_task'] != null &&
                json['periodic_task']['next_due_at'] == null &&
                json['periodic_task']['last_run_at'] != null;
          })
          .where((json) {
            var c = (DateTime.parse(json['created_at']));
            var filteredA = now.compareTo(c);
            return filteredA == 1;
          })
          .map((json) => Task.fromJson(json))
          .toList();
      for (var task in to) {
        scheduled.add(task);
      }

      return (tasks: scheduled, fetched: data.length);
    } else {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
  }

  /// Страница задач, возвращённых обходчику на доработку.
  ///
  /// Возвращённый результат остаётся `closed`, поэтому в плановые и открытые
  /// он не попадает. `status=closed&executable_only=true` у сервера — ровно
  /// возвращённые: из закрытых «доступны к выполнению» только они, и только
  /// их исполнителю.
  ///
  /// [supported] `false` — сервер параметра не понял и отдал закрытые
  /// осмотры подряд (на странице есть не возвращённый): дальше не качаем.
  /// [fetched] — сколько записей пришло, для конца постраничной загрузки.
  Future<({List<Task> tasks, int fetched, bool supported})> getReturnedTasks({
    int limit = 100,
    int offset = 0,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${API.baseUrl}/v1/company/fault_inspections/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$offset',
      'status': 'closed',
      'executable_only': 'true',
    });

    final response = await _client.get(
      url,
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);
    if (response.statusCode != 200) {
      _throwServerError(response, 'Не удалось загрузить задачи на доработку');
    }

    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final List<dynamic> data =
        jsonDecode(utf8Decoder.convert(response.bodyBytes));
    final tasks = <Task>[];
    for (final json in data) {
      if (json is! Map<String, dynamic>) continue;
      final review = json['review'];
      if (review is! Map || review['state'] != 'returned') {
        return (tasks: const <Task>[], fetched: data.length, supported: false);
      }
      tasks.add(Task.fromJson(json));
    }
    return (tasks: tasks, fetched: data.length, supported: true);
  }

  /// Один осмотр по uuid. Нужен для задач ППР: в общую выборку
  /// [getCurrentTasks] они могут не попасть (она отсекает осмотры с
  /// вышедшим сроком), а задача ППР актуальна, пока ППР не закрыт.
  /// Возвращает `null`, если осмотра больше нет (404).
  Future<Task?> getTaskByUuid(String inspectionUuid) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await _client.get(
      Uri.parse('${API.baseUrl}/v1/company/fault_inspections/$inspectionUuid'),
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to load inspection: ${response.statusCode}');
    }

    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final Map<String, dynamic> data =
        jsonDecode(utf8Decoder.convert(response.bodyBytes));
    return Task.fromJson(data);
  }

  Future<List<TypicalProblem>> getTypicalProblems(
      {limit = 50, offset = 0}) async {
    final page = await getTypicalProblemsPage(limit: limit, offset: offset);
    return page.items;
  }

  /// Страница справочника типовых неисправностей — тот же инкрементальный
  /// протокол, что у оборудования и каталога ЗИП (см. [SyncPage]).
  Future<SyncPage<TypicalProblem>> getTypicalProblemsPage({
    int limit = 100,
    int offset = 0,
    DateTime? updatedSince,
    DateTime? syncUntil,
    bool cursorMode = false,
    String? cursor,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${API.baseUrl}/v1/company/eq_fault/').replace(
      queryParameters: syncPageParams(
        limit: limit,
        offset: offset,
        updatedSince: updatedSince,
        syncUntil: syncUntil,
        cursorMode: cursorMode,
        cursor: cursor,
      ),
    );

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    // Курсор отклонён — окно начнут заново (см. [getEquipmentPage]).
    if (response.statusCode == 422 && cursor != null) {
      throw const SyncCursorRejected();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    return parseSyncPage(
      jsonDecode(utf8Decoder.convert(response.bodyBytes)),
      TypicalProblem.fromJson,
      'Failed to load typical problems',
    );
  }

  Future<List<PeriodicityRule>> getPeriodicityRules() async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url =
        Uri.parse('${API.baseUrl}/v1/company/periodic_task/periodicity-rules');

    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer ${API.jwtToken}',
      },
    ).timeout(API._readTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      final List<dynamic> rules = data['rules'];
      return rules.map((json) => PeriodicityRule.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load periodicity rules: ${response.statusCode}');
    }
  }

  /// Создаёт задачу заявки «Другое». Возвращает uuid созданной задачи;
  /// `null` — сервер ответил успехом без uuid, запись повторится позже.
  ///
  /// С постоянным `Idempotency-Key` ([PeriodicTaskRequest.createIdempotencyKey]):
  /// заявка уходит из офлайн-очереди, и если ответ потерялся уже после
  /// создания, повтор через 120 секунд раньше заводил вторую такую же
  /// задачу. Теперь сервер узнаёт повтор и отвечает 200 той же задачей.
  /// Ключ он сверяет с телом запроса — [PeriodicTaskRequest.toJson] от
  /// повтора к повтору не меняется. Сервер прошлой версии заголовок
  /// пропускает мимо.
  ///
  /// Снимки — отдельным запросом, [uploadPeriodicTaskPhotos].
  Future<String?> createPeriodicTask(PeriodicTaskRequest taskRequest) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${API.baseUrl}/v1/company/periodic_task/');

    final response = await _client
        .post(
          url,
          headers: {
            'Authorization': 'Bearer ${API.jwtToken}',
            'Content-Type': 'application/json',
            'Idempotency-Key': taskRequest.createIdempotencyKey,
          },
          body: jsonEncode(taskRequest.toJson()),
        )
        .timeout(API._readTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwServerError(response, 'Не удалось создать задачу');
    }
    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
    final uuid = data is Map ? data['uuid'] : null;
    return uuid is String && uuid.isNotEmpty ? uuid : null;
  }

  /// Грузит снимки к уже созданной задаче заявки [taskUuid].
  ///
  /// Сервер принимает их от автора заявки по праву создания осмотров, пока
  /// задачу никто не взял в работу (дальше — 409), и с правом изменения
  /// задач. [idempotencyKey] — постоянный на все повторы: потерянный ответ
  /// не добавит те же кадры второй раз.
  ///
  /// Отказ бросается исключением: что повторять, а что бросить, решает
  /// очередь (`isRetryableProblemPhotoError`). Битый кадр пропускается с
  /// записью в журнал — гонять его по кругу бессмысленно.
  Future<void> uploadPeriodicTaskPhotos(
    String taskUuid,
    List<String> photos, {
    required String idempotencyKey,
  }) async {
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${API.baseUrl}/v1/company/periodic_task/$taskUuid/photos'),
    );
    request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
    request.headers['accept'] = 'application/json';
    request.headers['Idempotency-Key'] = idempotencyKey;

    for (int i = 0; i < photos.length; i++) {
      final base64Image = photos[i];
      final cleanBase64 =
          base64Image.contains(',') ? base64Image.split(',').last : base64Image;
      try {
        request.files.add(http.MultipartFile.fromBytes(
          'files',
          base64Decode(cleanBase64),
          filename: 'image_$i.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } catch (e) {
        _apiLog.severe('Ошибка декодирования изображения $i: $e');
      }
    }
    if (request.files.isEmpty) return;

    final response = await _client.send(request).timeout(API._uploadTimeout);
    final body =
        await response.stream.bytesToString().timeout(API._uploadTimeout);
    if (response.statusCode == 200 || response.statusCode == 201) return;
    if (response.statusCode == 401) throw AuthExpiredException();
    final denied =
        AccessDeniedException.fromResponse(response.statusCode, body);
    if (denied != null) throw denied;
    throw ServerFailureException(
      response.statusCode,
      _detailFromBody(body, 'Не удалось загрузить фото заявки'),
    );
  }
}
