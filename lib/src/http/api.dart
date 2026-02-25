import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../src/model/usage_update.dart';
import '../../global_state.dart';
import '../../src/model/company.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../exceptions/login_exceptions.dart';

class API {
  static String baseUrl = dotenv.env["API_ENDPOINT"]!;
  static String username = dotenv.env["API_USER"]!;
  static String password = dotenv.env["API_PASSWORD"]!;
  static String basicAuth =
      'Basic ' + base64.encode(utf8.encode('$username:$password'));

  // Добавляем переменную для хранения JWT токена
  static String? get jwtToken {
    if (GlobalState.authUser == null) {
      return null;
    }
    return GlobalState.authUser!.JWTToken;
  }

  static Session? currentSession;

  Future<User> me() async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/user/me'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // final Map<String, dynamic> responseData = jsonDecode(response.body);
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

  // Получить информацию о компании
  Future<Company> getCompany() async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/company/me'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return Company.fromJson(data);
    } else {
      throw Exception('Failed to load company: ${response.statusCode}');
    }
  }

  // Получить список пользователей (с использованием JWT)
  Future<List<User>> getUsers() async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/walker/list'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users: ${response.statusCode}');
    }
  }

  // Метод для авторизации и получения JWT токена
  Future<User> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/v1/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              // Если требуется базовая аутентификация для этого эндпоинта, раскомментировать:
              // 'Authorization': basicAuth,
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        User user = User(role: responseData['role'], username: username);
        user.password = password;
        user.JWTToken = responseData['access_token'];
        return user;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Неверные учетные данные
        throw InvalidCredentialsException();
      } else {
        // Другие ошибки сервера
        throw Exception('Failed to login: ${response.statusCode}');
      }
    } on SocketException catch (_) {
      // Ошибка соединения с сервером
      throw NoConnectionException();
    } on HttpException catch (_) {
      // Ошибка HTTP соединения
      throw NoConnectionException();
    } on InvalidCredentialsException {
      // Перебрасываем исключение о неверных учетных данных
      rethrow;
    } on NoConnectionException {
      // Перебрасываем исключение об отсутствии соединения
      rethrow;
    } on Exception catch (e) {
      // Проверяем, не является ли это ошибкой соединения
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('TimeoutException')) {
        throw NoConnectionException();
      }
      // Для других исключений пробрасываем дальше
      rethrow;
    } catch (e) {
      // Обработка любых других ошибок (например, TimeoutException)
      if (e.toString().contains('Timeout') ||
          e.toString().contains('timeout')) {
        throw NoConnectionException();
      }
      throw Exception('Failed to login: $e');
    }
  }

  Future<bool> isAlive() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/docs'),
        headers: {'Authorization': basicAuth},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } on Exception catch (_) {
      return false;
    }
  }

  // Получить текущую сессию
  Future<Session> getCurrentSession() async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/session/'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // throw Exception(response.body);
      final List<dynamic> data = jsonDecode(response.body);
      List<Session> sessions =
          data.map((json) => Session.fromJson(json)).toList();
      sessions.sort((a, b) => a.startTime.compareTo(b.startTime));
      if (sessions.length > 0) {
        currentSession = sessions.last;
        return sessions.last;
      }
      throw Exception('No session found');
    } else {
      throw Exception('Failed to load session: ${response.statusCode}');
    }
  }

  // Получить список машин
  Future<List<InventoryRecord>> getEquipment({limit = 10, offset = 0}) async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/company/equipment?limit=${limit}&skip=${offset}'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.statusCode}');
    }
  }

  // Получить список машин
  Future<List<InventoryRecord>> getInventoryRecords(
      {limit = 10, offset = 0}) async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse(
          '$baseUrl/v1/inventory_record/list?limit=${limit}&offset=${offset}'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      // debugPrint(decodedBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.statusCode}');
    }
  }

// Отправить данные о количестве актива с изображениями
  Future<bool> sendScan(Scan scan) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    var method = 'POST';
    if (scan.taskUuid != null && scan.taskUuid!.length > 0) {
      method = 'PATCH';
    }

    // Создаем multipart request
    var request = http.MultipartRequest(
      method,
      Uri.parse('$baseUrl/v1/company/fault_inspections/'),
    );
    if (method == 'PATCH') {
      request = http.MultipartRequest(
        method,
        Uri.parse('$baseUrl/v1/company/fault_inspections/${scan.taskUuid}'),
      );
    }

    // Добавляем заголовки
    request.headers['Authorization'] = 'Bearer $jwtToken';
    request.headers['accept'] = 'application/json';

    // Добавляем поля из объекта Scan (кроме files)
    var scanJson = scan.toJson();
    scanJson.forEach((key, value) {
      if (key != 'files' && value != null && (value as String).length > 0) {
        request.fields[key] = value.toString();
      }
    });

    // Добавляем изображения из поля files
    if (scan.files != null && scan.files!.isNotEmpty) {
      for (int i = 0; i < scan.files!.length; i++) {
        final base64Image = scan.files![i];

        // Убираем префикс data:image/...;base64, если присутствует
        final cleanBase64 = base64Image.contains(',')
            ? base64Image.split(',').last
            : base64Image;

        try {
          final bytes = base64Decode(cleanBase64);
          final file = http.MultipartFile.fromBytes(
            'files', // Имя поля (должно совпадать с серверным)
            bytes,
            filename: 'image_$i.jpg', // Имя файла
            contentType:
                MediaType('image', 'jpeg'), // Замените при необходимости
          );
          request.files.add(file);
        } catch (e) {
          print('Ошибка декодирования изображения $i: $e');
          // Можно продолжить отправку без этого изображения или прервать операцию
        }
      }
    }

    try {
      // Отправляем запрос
      // await GlobalState.dataProvider.scanBox.delete(scan.key());
      // await GlobalState.dataProvider.scanPendingBox.put(scan.key(), scan);

      final response = await request.send().timeout(Duration(seconds: 10));

      // Получаем и проверяем ответ
      final responseBody = await response.stream.bytesToString();
      final Map<String, dynamic> responseData = jsonDecode(responseBody);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Failed to send scan: ${response.statusCode} - $responseBody');
      }

      if (responseData.containsKey('uuid')) {
        // await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
        return true;
      }
      // await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
      // await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
    } catch (e) {
      // await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
      // await GlobalState.dataProvider.scanBox.put(scan.key(), scan);

      throw Exception('Failed to send scan: $e');
    }
    return false;
  }

  Future<List<Task>> getCurrentOpenTasks({limit = 50, offset = 0}) async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '$baseUrl/v1/company/fault_inspections/?limit=${limit}&skip=${offset}&status=open');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

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
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '$baseUrl/v1/company/fault_inspections/?limit=${limit}&skip=${offset}&status=scheduled');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

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
            var a = (DateTime.parse(json['periodic_task']['last_run_at']));
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

  Future<List<TypicalProblem>> getTypicalProblems(
      {limit = 50, offset = 0}) async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '$baseUrl/v1/company/eq_fault/?limit=${limit}&skip=${offset}');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

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
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url =
        Uri.parse('$baseUrl/v1/company/periodic_task/periodicity-rules');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

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

  Future<List<UsageUnit>> getUsageUnitTypes() async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('$baseUrl/v1/company/equipment/usage-unit-types');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      final List<dynamic> unitTypes = data['unit_types'];
      return unitTypes.map((json) => UsageUnit.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load usage unit types: ${response.statusCode}');
    }
  }

  Future<EquipmentState> getEquipmentStates() async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('$baseUrl/v1/company/equipment/states');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      return EquipmentState.fromJson(data);
    } else {
      throw Exception(
          'Failed to load equipment states: ${response.statusCode}');
    }
  }

  Future<bool> updateUsageParameter(UsageUpdate usageUpdate) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '$baseUrl/v1/company/equipment/${usageUpdate.equipmentUuid}/usage-parameters/${usageUpdate.usageParameterUuid}');

    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'current_value': usageUpdate.usageParameterValue}),
    );

    final responseBody = response.body;
    final Map<String, dynamic> responseData = jsonDecode(responseBody);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to update usage params: ${response.statusCode} - $responseBody');
    }

    if (responseData.containsKey('uuid')) {
      return true;
    }

    return false;
  }

  // Обновить статус оборудования
  Future<bool> updateEquipmentState(String equipmentUuid, String state) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    // Создаем multipart request
    var request = http.MultipartRequest(
      'PATCH',
      Uri.parse('$baseUrl/v1/company/equipment/$equipmentUuid'),
    );

    // Добавляем заголовки
    request.headers['Authorization'] = 'Bearer $jwtToken';
    request.headers['accept'] = 'application/json';

    // Добавляем state как строку в multipart form data
    request.fields['state'] = state;

    try {
      final response = await request.send().timeout(Duration(seconds: 10));

      // Получаем и проверяем ответ
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Failed to update equipment state: ${response.statusCode} - $responseBody');
      }

      return true;
    } catch (e) {
      throw Exception('Failed to update equipment state: $e');
    }
  }

  // Создать периодическую задачу
  Future<bool> createPeriodicTask(PeriodicTaskRequest taskRequest) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('$baseUrl/v1/company/periodic_task/');

    final response = await http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $jwtToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(taskRequest.toJson()),
        )
        .timeout(Duration(seconds: 10));

    final responseBody = response.body;
    final Map<String, dynamic> responseData = jsonDecode(responseBody);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'Failed to create periodic task: ${response.statusCode} - $responseBody');
    }

    if (responseData.containsKey('uuid')) {
      final photoUrl = Uri.parse(
          '$baseUrl/v1/company/periodic_task/${responseData['uuid']}/photos');

      // Создаем multipart request
      var request = http.MultipartRequest(
        'POST',
        photoUrl,
      );

      // Добавляем заголовки
      request.headers['Authorization'] = 'Bearer $jwtToken';
      request.headers['accept'] = 'application/json';

      // Добавляем изображения из поля files
      if (taskRequest.photos != null && taskRequest.photos!.isNotEmpty) {
        for (int i = 0; i < taskRequest.photos!.length; i++) {
          final base64Image = taskRequest.photos![i];

          // Убираем префикс data:image/...;base64, если присутствует
          final cleanBase64 = base64Image.contains(',')
              ? base64Image.split(',').last
              : base64Image;

          try {
            final bytes = base64Decode(cleanBase64);
            final file = http.MultipartFile.fromBytes(
              'files', // Имя поля (должно совпадать с серверным)
              bytes,
              filename: 'image_$i.jpg', // Имя файла
              contentType:
                  MediaType('image', 'jpeg'), // Замените при необходимости
            );
            request.files.add(file);
          } catch (e) {
            print('Ошибка декодирования изображения $i: $e');
            // Можно продолжить отправку без этого изображения или прервать операцию
          }
        }
      }

      final response = await request.send().timeout(Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        // throw Exception(
        //     'Failed to create periodic task photos: ${response.statusCode} - ${responseBody}');
      }
      return true;
    }

    return false;
  }
}
