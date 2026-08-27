part of 'api.dart';

extension TaskApi on API {
  Future<List<Task>> getCurrentOpenTasks({limit = 50, offset = 0}) async {
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
        'responsible_user_uuids': [userUuid],
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
                json['responsible_user'] != null;
          })
          .map((json) => Task.fromJson(json))
          .toList();
      return scheduled;
    } else {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
  }

  Future<List<Task>> getCurrentTasks({limit = 50, offset = 0}) async {
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
    final url = Uri.parse('${API.baseUrl}/v1/company/fault_inspections/')
        .replace(queryParameters: <String, dynamic>{
      'limit': '$limit',
      'skip': '$offset',
      'status': 'scheduled',
      'only_my_roles': 'true',
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

      return scheduled;
    } else {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
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
    _guardOffline();
    if (API.jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '${API.baseUrl}/v1/company/eq_fault/?limit=${limit}&skip=${offset}');

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
      return data.map((json) => TypicalProblem.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load typical problems: ${response.statusCode}');
    }
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

  Future<bool> createPeriodicTask(PeriodicTaskRequest taskRequest) async {
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
          },
          body: jsonEncode(taskRequest.toJson()),
        )
        .timeout(API._readTimeout);

    final responseBody = response.body;
    final Map<String, dynamic> responseData = jsonDecode(responseBody);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to create periodic task: ${response.statusCode} - $responseBody');
    }

    if (responseData.containsKey('uuid')) {
      final photoUrl = Uri.parse(
          '${API.baseUrl}/v1/company/periodic_task/${responseData['uuid']}/photos');

      var request = http.MultipartRequest(
        'POST',
        photoUrl,
      );

      request.headers['Authorization'] = 'Bearer ${API.jwtToken}';
      request.headers['accept'] = 'application/json';

      if (taskRequest.photos != null && taskRequest.photos!.isNotEmpty) {
        for (int i = 0; i < taskRequest.photos!.length; i++) {
          final base64Image = taskRequest.photos![i];

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
            // То же, что и у снимков ремонта: заявка уедет без этого кадра, но
            // след останется. Прекращать отправку нельзя — очередь заявок
            // повторяемый отказ от невосстановимого не отличает и гоняла бы
            // битый файл по кругу.
            _apiLog.severe('Ошибка декодирования изображения $i: $e');
          }
        }
      }

      final response = await _client.send(request).timeout(API._uploadTimeout);
      await response.stream.bytesToString().timeout(API._uploadTimeout);

      return true;
    }

    return false;
  }
}
