import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class API {
  static String baseUrl = dotenv.env["API_ENDPOINT"]!;
  static String username = dotenv.env["API_USER"]!;
  static String password = dotenv.env["API_PASSWORD"]!;
  static String basicAuth =
      'Basic ' + base64.encode(utf8.encode('$username:$password'));

  // Получить список пользователей
  Future<List<User>> getUsers() async {
    debugPrint('$baseUrl/users');

    final response = await http.get(
      Uri.parse('$baseUrl/users'),
      headers: {'Authorization': basicAuth},
    ).timeout(Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users');
    }
  }

  Future<bool> isAlive() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/test'),
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
            'Ошибка загрузки задач: ${response.statusCode}\n${response.body}'
        );
      }
    } catch (e) {
      throw Exception('Сетевая ошибка: $e');
    }
  }

  Future<List<Task>> getCurrentTasks(int machineId) async {
    final url = Uri.parse('$baseUrl/machines/$machineId/current_tasks');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/json',
        },
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Task.fromJson(json)).toList();
      } else {
        throw Exception(
            'Ошибка загрузки задач: ${response.statusCode}\n${response.body}'
        );
      }
    } catch (e) {
      throw Exception('Сетевая ошибка: $e');
    }
  }

  // Получить список оборудования
  Future<List<Machine>> getMachines() async {
    final response = await http.get(
      Uri.parse('$baseUrl/machines'),
      headers: {'Authorization': basicAuth},
    ).timeout(Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Machine.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load machines');
    }
  }

  // Отправить данные о проверке машины
  Future<void> sendMachineCheck(Check check) async {
    // throw "API Error";
    // return;
    final response = await http.post(
      Uri.parse('$baseUrl/checks'),
      headers: {'Content-Type': 'application/json', 'Authorization': basicAuth},
      body: jsonEncode(check.toJson()),
    ).timeout(Duration(seconds: 5));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send machine check');
    }
  }
}
