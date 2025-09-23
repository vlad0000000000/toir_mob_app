import 'dart:convert';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/model/session.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';
import 'package:qr_machine_scanner/src/model/typical_problem.dart';
import 'package:qr_machine_scanner/src/model/periodicity_rule.dart';

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
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      User user =
          User(role: '', username: '', effectiveRole: data['effective_role']);
      return user;
    } else {
      throw Exception('Failed to authenticate: ${response.statusCode}');
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
    final response = await http.post(
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
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      User user = User(
          role: responseData['role'], username: username, effectiveRole: '');
      user.password = password;
      user.JWTToken = responseData['access_token'];
      return user;
    } else {
      throw Exception('Failed to login: ${response.statusCode}');
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
      await GlobalState.dataProvider.scanBox.delete(scan.key());
      await GlobalState.dataProvider.scanPendingBox.put(scan.key(), scan);

      final response = await request.send().timeout(Duration(seconds: 10));

      // Получаем и проверяем ответ
      final responseBody = await response.stream.bytesToString();
      final Map<String, dynamic> responseData = jsonDecode(responseBody);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Failed to send scan: ${response.statusCode} - $responseBody');
      }

      if (responseData.containsKey('uuid')) {
        await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
        return true;
      }
      await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
      await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
    } catch (e) {
      await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
      await GlobalState.dataProvider.scanBox.put(scan.key(), scan);

      throw Exception('Failed to send scan: $e');
    }
    return false;
  }

  Future<List<Task>> getCurrentTasks({limit = 50, offset = 0}) async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse(
        '$baseUrl/v1/company/fault_inspections/?limit=${limit}&skip=${offset}&today_only=1&status=scheduled');

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
      return data
          .where((json) {
            return (json['result_status'] as String) == 'scheduled';
          })
          .map((json) => Task.fromJson(json))
          .where((x) {
            return x.periodicTask.customRoles.where((x) {
                  return x.name == GlobalState.authUser!.effectiveRole;
                }).length >
                0;
          })
          .toList();
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
}
