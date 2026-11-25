part of 'api.dart';

/// Ответ условного GET (`If-None-Match`, бэкенд `81f644c`).
///
/// [data] `null` — 304: справочник не менялся, показываем сохранённый.
/// [etag] — валидатор ответа для следующего запроса; `null` — сервер его не
/// прислал (прошлая версия), тогда следующий запрос уйдёт без условия.
class Conditional<T> {
  final T? data;
  final String? etag;

  const Conditional(this.data, this.etag);

  bool get notModified => data == null;
}

/// Заголовки условного GET: токен и, если есть, `If-None-Match`.
Map<String, String> _conditionalHeaders(String? ifNoneMatch) => {
      'Authorization': 'Bearer ${API.jwtToken}',
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };

/// Разбирает ответ условного GET: 304 — без данных, 200 — [parse] тела.
Conditional<T> _conditionalResult<T>(
  http.Response response,
  String? ifNoneMatch,
  T Function(Map<String, dynamic> data) parse,
  String failure,
) {
  final etag = response.headers['etag'];
  if (response.statusCode == 304) {
    return Conditional<T>(null, etag ?? ifNoneMatch);
  }
  if (response.statusCode == 200 || response.statusCode == 201) {
    const utf8Decoder = Utf8Decoder(allowMalformed: true);
    final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
    return Conditional<T>(parse(data as Map<String, dynamic>), etag);
  }
  throw Exception('$failure: ${response.statusCode}');
}
