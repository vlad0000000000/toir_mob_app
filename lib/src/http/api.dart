import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class API {
  // static String baseUrl = 'http://localhost:4000';
  static String baseUrl = 'http://89.23.117.229:4000';

  // Получить список пользователей
  Future<List<User>> getUsers() async {

    final response = await http.get(Uri.parse('$baseUrl/users'));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users');
    }
  }

  Future<bool> notify() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/notify'))
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } on Exception catch (_) {
      return false;
    }
  }

  Future<bool> isAlive() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/test'))
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } on Exception catch (_) {
      return false;
    }
  }

  // Получить список машин
  Future<List<Machine>> getMachines() async {

    final response = await http.get(Uri.parse('$baseUrl/machines'));

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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(check.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send machine check');
    }
  }
}
