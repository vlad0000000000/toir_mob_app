import 'dart:io';

/// «Это обрыв связи, а не отказ сервера».
///
/// Проверка нужна везде, где решение зависит от причины сбоя: очередь при
/// обрыве не считает попытку неудачной, а экран показывает «нет интернета»
/// вместо текста ошибки. Раньше она была скопирована в трёх местах
/// (`auth_api`, `repair_error_messages`, `qr_result_screen`) — при добавлении
/// расхода ЗИП в осмотр появилась бы четвёртая копия, поэтому вынесена сюда.
///
/// Разбор по тексту, а не по типам, потому что часть ошибок доезжает уже
/// завёрнутой в `Exception('... SocketException ...')` — очередь и API
/// оборачивают их по дороге.
bool isOfflineError(Object error) {
  if (error is SocketException || error is HttpException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable') ||
      text.contains('TimeoutException');
}
