import 'dart:io';

import 'package:http/http.dart' as http;

/// Пара токенов из ответа `POST /v1/auth/refresh`. Сервер выдаёт новый
/// `refresh_token` при каждом обмене.
class TokenPair {
  final String access;
  final String refresh;

  const TokenPair({required this.access, required this.refresh});
}

/// Пробовать ли обмен `refresh_token` на ответ [statusCode] запроса с токеном
/// [requestToken] на адрес [url].
///
/// Только 401 на запрос с токеном. Не на сам вход и не на сам обмен: отказ
/// обмена означает, что `refresh_token` не годится, и обменивать его снова
/// бессмысленно — это «Сессия истекла».
bool shouldRefreshOn401({
  required int statusCode,
  required String? requestToken,
  required Uri url,
}) {
  if (statusCode != 401) return false;
  if (requestToken == null || requestToken.isEmpty) return false;
  var path = url.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return !path.endsWith('/auth/refresh') && !path.endsWith('/auth/login');
}

/// Чем кончилась попытка получить свежий токен ([TokenRefresher.freshToken]).
sealed class RefreshOutcome {
  const RefreshOutcome();
}

/// Свежий токен: запрос повторяется с ним.
final class RefreshedToken extends RefreshOutcome {
  final String token;

  const RefreshedToken(this.token);
}

/// Окончательный отказ: `refresh_token` нет, сервер его не принял (401
/// «Invalid refresh token», `user_inactive`). Прежний сценарий «Сессия
/// истекла».
final class RefreshRejected extends RefreshOutcome {
  const RefreshRejected();
}

/// Временный сбой: обрыв, таймаут, 5xx на `/auth/refresh`. Сессию не
/// трогаем — запрос отваливается как без связи, и очередь повторит его,
/// когда сервер ответит. Иначе обходчика выкинуло бы на вход, а выход стёр бы
/// ещё годный `refresh_token`.
final class RefreshUnavailable extends RefreshOutcome {
  const RefreshUnavailable();
}

/// Сессия входа сменилась (выход, вход другого), пока запрос летел или шёл
/// обмен. Ни обмена, ни повтора: запрос прошлой сессии не должен уйти с
/// токеном следующей — иначе осмотр обходчика А принял бы сервер от имени Б.
final class RefreshSessionChanged extends RefreshOutcome {
  const RefreshSessionChanged();
}

/// Обмен `refresh_token` на новый `access_token` — один на все запросы
/// одной сессии входа.
///
/// Получив 401, запрос просит свежий токен ([freshToken]) и передаёт номер
/// сессии, в которой он ушёл:
/// * сессия уже другая — [RefreshSessionChanged];
/// * токен уже сменился в той же сессии (обменял другой запрос) — просто
///   текущий, без нового обмена;
/// * обмен этой сессии уже идёт — ждёт его результата, а не запускает свой;
/// * иначе запускает обмен.
class TokenRefresher {
  /// Текущий `access_token` вошедшего; `null` — никто не вошёл.
  final String? Function() currentAccess;

  /// Текущий `refresh_token` вошедшего; `null` — его нет.
  final String? Function() currentRefresh;

  /// Номер текущей сессии входа (`DataProvider.accessSession`).
  final int Function() currentSession;

  /// Сам обмен на сервере: пара — успех, `null` — окончательный отказ,
  /// исключение — временный сбой.
  final Future<TokenPair?> Function(String refreshToken) exchange;

  /// Сохраняет новую пару вошедшему.
  final Future<void> Function(TokenPair pair) save;

  TokenRefresher({
    required this.currentAccess,
    required this.currentRefresh,
    required this.currentSession,
    required this.exchange,
    required this.save,
  });

  Future<RefreshOutcome>? _inFlight;
  int? _inFlightSession;

  /// Свежий `access_token` взамен [failedToken], получившего 401 в сессии
  /// [session].
  Future<RefreshOutcome> freshToken(String failedToken,
      {required int session}) {
    if (currentSession() != session) {
      return Future.value(const RefreshSessionChanged());
    }
    final current = currentAccess();
    if (current == null || current.isEmpty) {
      return Future.value(const RefreshRejected());
    }
    if (current != failedToken) return Future.value(RefreshedToken(current));
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightSession == session) return inFlight;
    _inFlightSession = session;
    late final Future<RefreshOutcome> started;
    started = _run(session).whenComplete(() {
      if (identical(_inFlight, started)) {
        _inFlight = null;
        _inFlightSession = null;
      }
    });
    return _inFlight = started;
  }

  Future<RefreshOutcome> _run(int session) async {
    final refresh = currentRefresh();
    if (refresh == null || refresh.isEmpty) return const RefreshRejected();
    final startedFor = currentAccess();
    TokenPair? pair;
    try {
      pair = await exchange(refresh);
    } catch (_) {
      return const RefreshUnavailable();
    }
    // Пока шёл обмен, обходчик вышел или вошёл другой: пара — не его.
    if (currentSession() != session || currentAccess() != startedFor) {
      return const RefreshSessionChanged();
    }
    if (pair == null) return const RefreshRejected();
    await save(pair);
    return RefreshedToken(pair.access);
  }
}

/// Обмен токена не дошёл до сервера или тот ответил сбоем — запрос
/// отваливается как без связи (`isOfflineError`), сессия цела.
class RefreshUnavailableException extends SocketException {
  const RefreshUnavailableException()
      : super('Не удалось обновить вход, попытка отложена');
}

/// Отправляет [request] через [send] и при 401 один раз обменивает токен и
/// повторяет запрос с новым ([shouldRefreshOn401], [TokenRefresher]).
///
/// [session] — номер сессии входа на момент отправки: обмен и повтор только в
/// ней ([RefreshSessionChanged]). Возвращает ответ и запрос, который его
/// получил: по токену и сессии этого запроса общий клиент решает, поднимать ли
/// «Сессия истекла». Повтор — один: повторный 401 уходит вызывающему как есть.
/// Временный сбой обмена — [RefreshUnavailableException].
///
/// [request] должен быть повторяемым — см. [replayableRequest].
Future<(http.StreamedResponse, http.Request)> sendWithTokenRefresh(
  http.Request request, {
  required Future<http.StreamedResponse> Function(http.Request) send,
  required TokenRefresher? refresher,
  required int session,
}) async {
  final response = await send(request);
  final token = bearerToken(request);
  if (refresher == null ||
      !shouldRefreshOn401(
        statusCode: response.statusCode,
        requestToken: token,
        url: request.url,
      )) {
    return (response, request);
  }
  final outcome = await refresher.freshToken(token!, session: session);
  switch (outcome) {
    case RefreshRejected():
    case RefreshSessionChanged():
      return (response, request);
    case RefreshUnavailable():
      await response.stream.drain<void>();
      throw const RefreshUnavailableException();
    case RefreshedToken(:final token):
      // Тело отказа дочитываем, чтобы освободить соединение, — до проверки
      // сессии: чтение тоже ждёт, и выход за это время иначе остался бы
      // незамеченным, и запрос прежнего аккаунта ушёл бы после выхода.
      final body = await response.stream.toBytes();
      // Последняя проверка — непосредственно перед отправкой: сессия могла
      // смениться, пока ждали чужой обмен или дочитывали тело.
      if (refresher.currentSession() != session) {
        return (_withBody(response, body), request);
      }
      final retry = copyRequest(request, token: token);
      return (await send(retry), retry);
  }
}

/// [response] с уже прочитанным телом [body]: поток исходного ответа второй
/// раз не прочитать, а вызывающий ждёт ответ целиком.
http.StreamedResponse _withBody(
        http.StreamedResponse response, List<int> body) =>
    http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      contentLength: body.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );

/// JWT из заголовка `Authorization`. `null` — запрос без токена.
String? bearerToken(http.BaseRequest request) {
  final authorization = request.headers['Authorization'];
  return authorization != null && authorization.startsWith('Bearer ')
      ? authorization.substring('Bearer '.length)
      : null;
}

/// Копия [request] для повторной отправки, с токеном [token], если задан.
http.Request copyRequest(http.Request request, {String? token}) {
  final copy = http.Request(request.method, request.url)
    ..headers.addAll(request.headers)
    ..bodyBytes = request.bodyBytes
    ..followRedirects = request.followRedirects
    ..maxRedirects = request.maxRedirects
    ..persistentConnection = request.persistentConnection;
  if (token != null) copy.headers['Authorization'] = 'Bearer $token';
  return copy;
}

/// [request] в виде, который можно отправить второй раз.
///
/// Тело multipart-запроса (осмотр, фото ремонта) читается одним потоком, и
/// второй раз его не отправить. Поэтому тело любого запроса, кроме обычного
/// `http.Request`, один раз собирается в байты: фото к этому моменту и так
/// лежат в памяти. Заголовки — после сборки: `finalize()` у multipart
/// проставляет `content-type` с границей частей.
Future<http.Request> replayableRequest(http.BaseRequest request) async {
  if (request is http.Request) return request;
  final bytes = await request.finalize().toBytes();
  return http.Request(request.method, request.url)
    ..headers.addAll(request.headers)
    ..bodyBytes = bytes
    ..followRedirects = request.followRedirects
    ..maxRedirects = request.maxRedirects
    ..persistentConnection = request.persistentConnection;
}
