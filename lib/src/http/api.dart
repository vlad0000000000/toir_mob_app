import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class API {
  static String baseUrl = 'http://localhost:4000';
  // static String baseUrl = 'http://92.255.107.158:4000';

  // Получить список пользователей
  Future<List<User>> getUsers() async {
    // return [
    //   User(id: 1, login: 'user', passwordHash: GlobalState.digest('1234')),
    //   User(id: 2, login: 'test', passwordHash: GlobalState.digest('666')),
    // ];

    final response = await http.get(Uri.parse('$baseUrl/users'));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load users');
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
    // return [
    //   Machine(
    //       id: 1,
    //       name: 'lathe1',
    //       imageData:
    //           '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AEApAQAoJQAApQQAoJQAAJQSAIBSAgBQSgAASgkAQCkBACglAAClBACglAAAlBIAgFICAFBKAABKCQBAKQEAKCUAAKUEAKCUAACUEgCAUgIAUGrw1anbow9s/vu9o/tHP/WT6P7s9xwZ3d/v6sXR/XcOPRLd3/eC347uLzxhQnR/r6HDovvL9psT3X9m5cLo/vDGwej+41/7VHT/0AnXRPfHvn1zdP/LG46I7rsAAEoJAEApAQAoJQAApQQAoJQAAJQSAIBSAgBQSgAASgkAQCkBACglAAClBACglAAAlBIAgFICAFBKAABKCQBAKQEAKCUAAKUEAKCUAACUEgCAUgIAUEoAAEoJAEApAQAoJQAApQQAoJQAAJQSAIBSg/MvOzP6wJqLR0f3t8ybH90//o710f0Ht90W3X/s0oHo/tzTD4/uT5z2oej+mguuj+6fMXef6P4L37o9uv+N/XdE99d97ovR/fN/+s3o/j67bonu7/xy9v+XCwCglAAAlBIAgFICAFBKAABKCQBAKQEAKCUAAKUEAKCUAACUEgCAUgIAUEoAAEoJAEApAQAoJQAApQQAoJQAAJQSAIBSAgBQSgAASgkAQCkBACglAAClBACglAAAlBIAgFICAFBKAABKCQBAKQEAKDVwwj0Log9sGzsY3V824bjo/qSbvhfdv+7n86L7r529O7o/86UV0f0bLp8U3Z/22sLo/rK7Dozu79o0I7o/alp0fsTZu86I7v/VS9nft+k/+Ivo/pm3T47uuwAASgkAQCkBACglAAClBACglAAAlBIAgFICAFBKAABKCQBAKQEAKCUAAKUEAKCUAACUEgCAUgIAUEoAAEoJAEApAQAoJQAApQQAoJQAAJQSAIBSAgBQSgAASgkAQCkBACglAAClBACglAAAlBIAgFL/HwAA//9ednoyuCm9vQAAAABJRU5ErkJggg==',
    //       description: '')
    // ];

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
