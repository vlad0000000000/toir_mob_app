import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import '../../src/model/usage_update.dart';
import '../../global_state.dart';
import '../../src/model/company.dart';
import '../../src/model/consumption_norm.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/notification.dart';
import '../../src/model/notification_settings.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/ppr.dart';
import '../../src/model/repair.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/spare_part.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../exceptions/app_exceptions.dart';
import '../utils/offline_error.dart';

part 'auth_api.dart';
part 'equipment_api.dart';
part 'task_api.dart';
part 'scan_api.dart';
part 'notifications_api.dart';
part 'spare_part_api.dart';
part 'repair_api.dart';
part 'ppr_api.dart';

/// Журнал сетевого слоя.
///
/// Пишет только о том, что иначе исчезло бы бесследно, — сейчас это неразбор
/// снимка перед отправкой. Уровень `severe`: в релизной сборке
/// `Logger.root.level` поднят до `Level.WARNING` (`main.dart`), а именно эти
/// сообщения нужны, когда фотография не доехала до администратора.
final _apiLog = Logger('API');

/// Соединение, которое живёт дольше одного запроса и сдаётся быстро.
///
/// Раньше каждый вызов шёл через top-level `http.get/post/...`, а они на каждый
/// запрос поднимают собственный `IOClient` и закрывают его после ответа. Из
/// этого следовали две беды: TCP- и TLS-рукопожатие заново на каждый запрос —
/// и, главное, некуда было поставить `connectionTimeout`. Когда сеть есть, а
/// сервера нет, SYN уходит в пустоту, ошибки не приходит, ОС молча ретраит — и
/// запрос висел до `.timeout()` на самом верху, то есть все 15 секунд. Теперь
/// попытка соединения сдаётся за три.
http.Client _newIoClient() => IOClient(
      HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 20),
    );

/// Клиент обычных запросов: помнит, что сервер только что не отозвался.
///
/// **Через него обязаны идти все запросы приложения.** Top-level `http.get`,
/// `http.post` и им подобные в методах API не место: они поднимают свой
/// клиент, мимо трёхсекундного `connectionTimeout`, и — главное — мимо отметки
/// о недоступности. Пять таких вызовов пережили переход на общий клиент
/// (создание, правка и взятие ремонта, создание заявки, вход) и вели себя
/// заметно: успешный запрос мимо обёртки не снимал отметку, и очередь осмотров
/// ещё полминуты отказывала «по памяти» после того, как сервер уже ответил.
final http.Client _client = _OfflineAwareClient(_newIoClient());

/// Клиент пинга живости. Окно недоступности он обязан игнорировать — иначе
/// выйти из окна было бы нечем.
final http.Client _probeClient = _newIoClient();

/// Обёртка, через которую проходят все запросы приложения.
///
/// Одно место вместо тридцати: отметка о недоступности ставится и снимается
/// здесь, а не в каждом методе API, и заодно накрывает multipart-загрузки,
/// которые идут мимо `get`/`post`.
class _OfflineAwareClient extends http.BaseClient {
  final http.Client _inner;

  _OfflineAwareClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (API.isServerKnownUnreachable) {
      // Тип тот же, что при реальном обрыве: вызывающий код уже кладёт данные
      // в очередь именно по нему, отдельная ветка не нужна.
      throw const SocketException('Сервер не отвечает, попытка отложена');
    }
    try {
      final response = await _inner.send(request);
      API.markServerReachable();
      return response;
    } catch (error) {
      if (isOfflineError(error)) API.markServerUnreachable();
      rethrow;
    }
  }
}

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
      Duration(seconds: 8); // GET и мелкие записи + login
  static const Duration _uploadTimeout =
      Duration(seconds: 60); // multipart с фото
  static const Duration _aliveTimeout =
      Duration(seconds: 5); // ping живости isAlive

  /// Отладочный параметр: при `true` все сетевые запросы имитируют
  /// отсутствие интернета — `isAlive()` возвращает `false`, а остальные
  /// методы бросают [SocketException], как при реальном обрыве связи.
  /// Включается из кода/дебаггера: `API.simulateOffline = true;`.
  static bool simulateOffline = false;

  /// Сколько держим отметку «сервер не отвечает», не трогая сеть.
  ///
  /// Тридцать секунд — компромисс: за это время обходчик успевает сделать
  /// несколько действий подряд, и ни одно из них не упирается в ожидание
  /// соединения, а вернувшуюся связь замечает пинг живости (он окно
  /// игнорирует) или первый запрос после истечения окна.
  static const Duration offlineWindow = Duration(seconds: 30);

  static DateTime? _unreachableUntil;

  /// Сервер только что не отозвался, и ходить в сеть пока незачем.
  ///
  /// Это ответ на «почему офлайн так долго»: без такой отметки каждое
  /// следующее действие заново открывало соединение к недоступному серверу и
  /// ждало таймаута. Здесь отказ выдаётся мгновенно и того же вида, что при
  /// реальном обрыве, — очередь и экраны уже умеют его разбирать.
  static bool get isServerKnownUnreachable {
    final until = _unreachableUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _unreachableUntil = null;
    return false;
  }

  /// Запрос не доехал до сервера — закрываем сеть на [offlineWindow].
  static void markServerUnreachable() {
    _unreachableUntil = DateTime.now().add(offlineWindow);
  }

  /// Сервер ответил — неважно чем: связь есть, окно снимаем.
  static void markServerReachable() {
    _unreachableUntil = null;
  }

  /// Забыть отметку недоступности перед действием, которое обходчик запустил
  /// сам: вход, «Синхронизировать данные», «Повторить».
  ///
  /// Он мог только что подключиться к сети, и отвечать ему мгновенным «связи
  /// нет» по памяти полуминутной давности нельзя — на явное действие
  /// приложение обязано честно сходить в сеть.
  static void retryConnectionNow() {
    _unreachableUntil = null;
  }

  /// Бросает [SocketException], если включена имитация офлайна.
  void _guardOffline() {
    if (simulateOffline) {
      throw const SocketException(
          'Имитация отсутствия интернета (API.simulateOffline)');
    }
  }

  /// Дешёвый пинг живости — единственный способ выйти из окна недоступности,
  /// поэтому идёт мимо него, через [_probeClient]. Ответ сервера снимает окно
  /// сразу: остальные запросы после этого не ждут его истечения.
  Future<bool> isAlive() async {
    if (simulateOffline) return false;
    try {
      final response = await _probeClient.get(
        Uri.parse('$baseUrl/docs'),
        headers: {'Authorization': basicAuth},
      ).timeout(_aliveTimeout);

      markServerReachable();
      return response.statusCode == 200 || response.statusCode == 201;
    } on Exception catch (error) {
      if (isOfflineError(error)) markServerUnreachable();
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
  // Код ответа тащим дальше: по нему очередь отличает отказ по существу от
  // временного сбоя сервера и решает, повторять отправку или нет.
  throw ServerFailureException(
    response.statusCode,
    _serverDetail(response, fallback),
  );
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
