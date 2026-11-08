import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qr_scan_industry/src/http/token_refresher.dart';
import 'package:qr_scan_industry/src/notifications/push/push_notifications_controller.dart';
import 'package:qr_scan_industry/src/utils/offline_error.dart';

/// Обмен `refresh_token` при 401 (задача 4 промпта `standalone-fixes`):
/// раньше первый же 401 выводил на вход, хотя сервер выдавал refresh-токен
/// на 7 суток, а приложение его отбрасывало.
void main() {
  final url = Uri.parse('http://test.local:8000/v1/company/equipment/');

  http.Request request(String token) =>
      http.Request('GET', url)..headers['Authorization'] = 'Bearer $token';

  http.StreamedResponse respond(int code) =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), code);

  /// Сервер, принимающий только токен [valid].
  Future<http.StreamedResponse> Function(http.Request) server(
    List<String?> seen, {
    required String Function() valid,
  }) =>
      (req) async {
        final token = bearerToken(req);
        seen.add(token);
        return respond(token == valid() ? 200 : 401);
      };

  group('shouldRefreshOn401', () {
    bool should(int code, {String? token = 'a', String path = '/v1/x/'}) =>
        shouldRefreshOn401(
          statusCode: code,
          requestToken: token,
          url: Uri.parse('http://h$path'),
        );

    test('401 на запрос с токеном — пробуем обмен', () {
      expect(should(401), isTrue);
    });

    test('другие коды и запрос без токена — нет', () {
      expect(should(200), isFalse);
      expect(should(403), isFalse);
      expect(should(401, token: null), isFalse);
    });

    test('сам обмен и вход обмен не запускают', () {
      expect(should(401, path: '/v1/auth/refresh'), isFalse);
      expect(should(401, path: '/v1/auth/refresh/'), isFalse);
      expect(should(401, path: '/v1/auth/login'), isFalse);
    });
  });

  group('обмен и повтор', () {
    late String access;
    late String? refresh;
    late int session;
    late int exchanges;
    late List<TokenPair> saved;

    TokenRefresher refresher({
      Future<TokenPair?> Function(String)? exchange,
    }) =>
        TokenRefresher(
          currentAccess: () => access,
          currentRefresh: () => refresh,
          currentSession: () => session,
          exchange: exchange ??
              (token) async {
                exchanges++;
                await Future<void>.delayed(const Duration(milliseconds: 10));
                return const TokenPair(
                  access: 'new-access',
                  refresh: 'new-refresh',
                );
              },
          save: (pair) async {
            saved.add(pair);
            access = pair.access;
            refresh = pair.refresh;
          },
        );

    Future<(http.StreamedResponse, http.Request)> send(
      TokenRefresher shared, {
      List<String?>? seen,
      String Function()? valid,
      int? at,
    }) =>
        sendWithTokenRefresh(
          request('old-access'),
          send: server(seen ?? [], valid: valid ?? () => 'new-access'),
          refresher: shared,
          session: at ?? session,
        );

    setUp(() {
      access = 'old-access';
      refresh = 'old-refresh';
      session = 1;
      exchanges = 0;
      saved = [];
    });

    test('401 — обмен, сохранение и повтор с новым токеном', () async {
      final seen = <String?>[];
      final (response, sent) = await send(refresher(), seen: seen);

      expect(response.statusCode, 200);
      expect(seen, ['old-access', 'new-access']);
      expect(bearerToken(sent), 'new-access');
      expect(exchanges, 1);
      expect(saved.single.refresh, 'new-refresh');
    });

    test('несколько параллельных 401 — один обмен', () async {
      final shared = refresher();

      final results = await Future.wait([
        for (var i = 0; i < 5; i++) send(shared),
      ]);

      expect(exchanges, 1);
      expect(results.map((r) => r.$1.statusCode), everyElement(200));
    });

    test('токен уже обменян в той же сессии — повтор без нового обмена',
        () async {
      access = 'new-access';

      final (response, _) = await send(refresher());

      expect(response.statusCode, 200);
      expect(exchanges, 0);
    });

    test('сервер отказал в обмене — исходный 401, «Сессия истекла»', () async {
      final seen = <String?>[];
      final (response, sent) = await send(
        refresher(exchange: (_) async => null),
        seen: seen,
        valid: () => 'never',
      );

      expect(response.statusCode, 401);
      expect(seen, ['old-access']);
      // По токену этого запроса клиент и поднимает «Сессия истекла».
      expect(bearerToken(sent), 'old-access');
      expect(saved, isEmpty);
    });

    test('временный сбой обмена — запрос отваливается как без связи', () async {
      final attempt = send(
        refresher(exchange: (_) => throw Exception('503')),
        valid: () => 'never',
      );

      final error =
          await attempt.then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<RefreshUnavailableException>());
      // Очереди держат такой запрос и повторят его, а не выкидывают на вход.
      expect(isOfflineError(error!), isTrue);
      expect(saved, isEmpty);
    });

    test('запись без refresh_token — прежний сценарий без обмена', () async {
      refresh = null;

      final (response, _) = await send(refresher());

      expect(response.statusCode, 401);
      expect(exchanges, 0);
    });

    test('повторный 401 после обмена — повтор один, дальше как есть', () async {
      final seen = <String?>[];
      final (response, sent) =
          await send(refresher(), seen: seen, valid: () => 'never');

      expect(response.statusCode, 401);
      expect(seen, ['old-access', 'new-access']);
      expect(bearerToken(sent), 'new-access');
    });

    test('запрос прошлой сессии не повторяется с токеном нового входа',
        () async {
      // Запрос ушёл от А в сессии 1, затем вошёл Б (сессия 2, свой токен).
      session = 2;
      access = 'token-b';
      final seen = <String?>[];

      final (response, sent) = await send(
        refresher(),
        seen: seen,
        valid: () => 'token-b',
        at: 1,
      );

      expect(response.statusCode, 401);
      expect(seen, ['old-access']);
      expect(bearerToken(sent), 'old-access');
      expect(exchanges, 0);
    });

    test('вход сменился во время обмена — ни сохранения, ни повтора', () async {
      final gate = Completer<TokenPair?>();
      final seen = <String?>[];
      final pending = send(
        refresher(exchange: (_) => gate.future),
        seen: seen,
        valid: () => 'n',
      );
      await Future<void>.delayed(Duration.zero);
      session = 2;
      access = 'token-b';
      gate.complete(const TokenPair(access: 'n', refresh: 'r'));

      final (response, _) = await pending;
      expect(response.statusCode, 401);
      expect(seen, ['old-access']);
      expect(saved, isEmpty);
    });

    test('выход, пока дочитывается тело 401, — повтора нет, тело цело',
        () async {
      // Токен уже обменян другим запросом той же сессии: обмена нет, сразу
      // повтор — но тело отказа ещё читается, и в это время обходчик выходит.
      access = 'new-access';
      final sent = <String?>[];
      late final StreamController<List<int>> body;
      body = StreamController<List<int>>(onListen: () {
        session = 2;
        body
          ..add(utf8.encode('{"detail":"expired"}'))
          ..close();
      });

      final (response, _) = await sendWithTokenRefresh(
        request('old-access'),
        send: (req) async {
          sent.add(bearerToken(req));
          return http.StreamedResponse(body.stream, 401);
        },
        refresher: refresher(),
        session: 1,
      );

      expect(sent, ['old-access']);
      expect(response.statusCode, 401);
      expect(await response.stream.bytesToString(), '{"detail":"expired"}');
    });
  });

  test('после обмена фоновый сервис перезапускается с новым токеном', () {
    // Сервис держит токен, сохранённый при запуске, — после обмена он
    // устарел, и `ensureRunning` должен перезапустить сервис.
    expect(
      pushServiceNeedsRestart(
        savedUrl: 'http://test.local:8000',
        savedJwt: 'old-access',
        currentUrl: 'http://test.local:8000',
        currentJwt: 'new-access',
      ),
      isTrue,
    );
  });

  group('replayableRequest', () {
    test('multipart собирается в байты и повторяется целиком', () async {
      final multipart = http.MultipartRequest('PATCH', url)
        ..headers['Authorization'] = 'Bearer old'
        ..fields['comment'] = 'осмотр'
        ..files.add(http.MultipartFile.fromBytes('files', [1, 2, 3],
            filename: 'photo.jpg'));

      final replayable = await replayableRequest(multipart);
      final retry = copyRequest(replayable, token: 'new');

      expect(replayable.method, 'PATCH');
      expect(replayable.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(retry.bodyBytes, replayable.bodyBytes);
      expect(utf8.decode(retry.bodyBytes, allowMalformed: true),
          contains('осмотр'));
      expect(bearerToken(retry), 'new');
      expect(bearerToken(replayable), 'old');
    });

    test('обычный запрос не копируется до повтора', () async {
      final plain = request('a');
      expect(identical(await replayableRequest(plain), plain), isTrue);
    });
  });
}
