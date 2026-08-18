import 'dart:io';

import 'package:http/http.dart' as http;

/// «Это обрыв связи, а не отказ сервера».
///
/// Проверка нужна везде, где решение зависит от причины сбоя: очередь при
/// обрыве не считает попытку неудачной, а экран показывает «нет интернета»
/// вместо текста ошибки. Раньше она была скопирована в трёх местах
/// (`auth_api`, `repair_error_messages`, `qr_result_screen`) — при добавлении
/// расхода ЗИП в осмотр появилась бы четвёртая копия, поэтому вынесена сюда.
///
/// Разбор по тексту, а не только по типам, потому что часть ошибок доезжает
/// уже завёрнутой в `Exception('... SocketException ...')` — очередь и API
/// оборачивают их по дороге.
bool isOfflineError(Object error) {
  // `http.ClientException` — это всегда сбой транспорта: ответ сервера, каким
  // бы он ни был, доезжает до нас обычным `Response`. Клиент бросает её, когда
  // соединение оборвалось на полпути («Connection closed before full header
  // was received»), было сброшено ОС при потере сети («Software caused
  // connection abort») или закрыто прокси. Раньше такие сбои под проверку не
  // попадали — ни один из текстовых признаков ниже в них не встречается, — и
  // приложение принимало обрыв за отказ сервера: черновик ремонта не уходил в
  // очередь, а обходчик получал красное «Не удалось создать».
  if (error is http.ClientException) return true;
  if (error is SocketException || error is HttpException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Connection reset') ||
      text.contains('Connection closed') ||
      text.contains('Connection terminated') ||
      text.contains('connection abort') ||
      text.contains('Network is unreachable') ||
      text.contains('TimeoutException');
}
