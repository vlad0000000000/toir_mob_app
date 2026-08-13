import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../src/model/usage_update.dart';
import '../../global_state.dart';
import '../../src/model/company.dart';
import '../../src/model/consumption_norm.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/notification.dart';
import '../../src/model/notification_settings.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/repair.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/spare_part.dart';
import '../../src/model/stock_history_entry.dart';
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
part 'spare_part_api.dart';
part 'repair_api.dart';

/// Тонкое ядро HTTP-клиента. Методы по доменам вынесены в part-файлы
/// (auth/equipment/task/scan/notifications/spare_part/repair) как extension на [API];
/// вызовы остаются прежними — `api.login(...)`, `api.sendScan(...)` и т.д.
class API {
  /// Базовый адрес бэкенда **без** завершающего слеша.
  ///
  /// Слеш срезаем намеренно: все методы склеивают путь как `'$baseUrl/v1/...'`,
  /// и если он останется, получится `https://host//v1/...`. Бэкенд на двойной
  /// слеш отвечает 404 — то есть отваливается вообще всё, включая `isAlive()`,
  /// и приложение показывает «нет соединения», хотя сервер жив и сеть в
  /// порядке. Диагностируется это плохо, а опечатка в `.env` стоит одного
  /// символа, поэтому чиним на входе, а не в каждом методе.
  static String baseUrl = _normalizeBaseUrl(dotenv.env["API_ENDPOINT"]!);

  static String _normalizeBaseUrl(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

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

/// Бросает подходящее исключение по неуспешному ответу.
///
/// 401 выделен в отдельный тип: очередь отправки работает в фоне, и разница
/// между «сервер отказал по существу» и «протух токен» для неё
/// принципиальна — во втором случае данные не виноваты и терять их нельзя.
Never _throwServerError(http.Response response, String fallback) {
  if (response.statusCode == 401) {
    throw AuthExpiredException();
  }
  throw Exception(_serverDetail(response, fallback));
}

/// Достаёт человекочитаемое сообщение из ответа сервера.
///
/// Бэкенд отдаёт осмысленный русский текст в поле `detail` («Оборудование уже
/// в ремонте», «Обходчик может редактировать только открытый ремонт»). Его и
/// показываем обходчику, а код ответа оставляем на случай, когда разобрать
/// тело не удалось.
String _serverDetail(http.Response response, String fallback) {
  const utf8Decoder = Utf8Decoder(allowMalformed: true);
  return _detailFromBody(utf8Decoder.convert(response.bodyBytes), fallback);
}

/// То же самое для уже прочитанного тела — multipart-ответы приходят
/// строкой из `StreamedResponse`, а не как [http.Response].
String _detailFromBody(String body, String fallback) {
  try {
    final data = jsonDecode(body);
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'] as String;
      if (detail.trim().isNotEmpty) return detail;
    }
  } catch (_) {
    // Тело не JSON или без detail — покажем запасной текст.
  }
  return fallback;
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
