import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/model/session.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

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

  Future<void> me() async {
    // Проверяем наличие токена
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/v1/auth/me'),
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // final List<dynamic> data = jsonDecode(response.body);
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
      User user = User(role: responseData['role'], username: username);
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
      // debugPrint(decodedBytes);
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

  // Отправить данные о количестве актива
  Future<void> sendScan(Scan scan) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    //TODO: убрать привязку к сессии
    await getCurrentSession();
    if (currentSession == null) {
      throw Exception('No current session');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/v1/session/${currentSession!.id}/scans'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(scan.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send scan');
    }
  }

  Future<List<Task>> getAllCurrentTasks() async {
    final url = Uri.parse('$baseUrl/machines/current_tasks');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Task.fromJson(json)).toList();
      } else {
        throw Exception(
            'Ошибка загрузки задач: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      throw Exception('Сетевая ошибка: $e');
    }
  }

  Future<List<Task>> getEquipmentTasks(String equipmentUUID) async {
    if (jwtToken == null) {
      throw Exception('Not authenticated');
    }

    final url =
        Uri.parse('$baseUrl/v1/company/equipment/$equipmentUUID/grouped-tasks');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $jwtToken', // Используем JWT
      },
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      // final List<dynamic> data = jsonDecode(decodedBytes);
      final Map<String, dynamic> data = jsonDecode(decodedBytes);
      List<Task> tasks = [];
      debugPrint(data.toString());
      for (var period in data['periodic_tasks']) {
        for (var task in data['periodic_tasks'][period]) {
          tasks.add(Task.fromJson(task));
        }
      }
      return tasks;
      // return data.map((json) => Task.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load tasks: ${response.statusCode}');
    }
  }
}
