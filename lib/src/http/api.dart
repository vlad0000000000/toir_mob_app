import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../src/model/usage_update.dart';
import '../../global_state.dart';
import '../../src/model/company.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/notification.dart';
import '../../src/model/notification_settings.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/ppr.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../exceptions/app_exceptions.dart';

part 'auth_api.dart';
part 'equipment_api.dart';
part 'task_api.dart';
part 'scan_api.dart';
part 'notifications_api.dart';
part 'ppr_api.dart';

/// Тонкое ядро HTTP-клиента. Методы по доменам вынесены в part-файлы
/// (auth/equipment/task/scan/notifications) как extension на [API];
/// вызовы остаются прежними — `api.login(...)`, `api.sendScan(...)` и т.д.
class API {
  static String baseUrl = dotenv.env["API_ENDPOINT"]!;
  static String username = dotenv.env["API_USER"]!;
  static String password = dotenv.env["API_PASSWORD"]!;
  static String basicAuth =
      'Basic ' + base64.encode(utf8.encode('$username:$password'));

  static String? get jwtToken {
    if (GlobalState.authUser == null) {
      return null;
    }
    return GlobalState.authUser!.JWTToken;
  }

  static Session? currentSession;

  // Таймауты сетевых запросов
  static const Duration _readTimeout =
      Duration(seconds: 15); // GET и мелкие записи + login
  static const Duration _uploadTimeout =
      Duration(seconds: 60); // multipart с фото
  static const Duration _aliveTimeout =
      Duration(seconds: 5); // ping живости isAlive

  /// Отладочный параметр: при `true` все сетевые запросы имитируют
  /// отсутствие интернета — `isAlive()` возвращает `false`, а остальные
  /// методы бросают [SocketException], как при реальном обрыве связи.
  /// Включается из кода/дебаггера: `API.simulateOffline = true;`.
  static bool simulateOffline = false;

  /// Бросает [SocketException], если включена имитация офлайна.
  void _guardOffline() {
    if (simulateOffline) {
      throw const SocketException(
          'Имитация отсутствия интернета (API.simulateOffline)');
    }
  }

  Future<bool> isAlive() async {
    if (simulateOffline) return false;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/docs'),
        headers: {'Authorization': basicAuth},
      ).timeout(_aliveTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        return false;
      }
    } on Exception catch (_) {
      return false;
    }
  }
}

class StreamedResponseHandle {
  final http.Client client;
  final http.StreamedResponse response;

  StreamedResponseHandle({required this.client, required this.response});

  void close() {
    try {
      client.close();
    } catch (_) {}
  }
}
