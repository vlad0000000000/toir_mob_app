import '../../strings.dart';
import '../exceptions/app_exceptions.dart';
import '../utils/offline_error.dart';

/// Человекочитаемая причина, по которой сервер не принял осмотр.
///
/// Сделано по образцу `repairs/repair_error_messages.dart`: бэкенд отвечает
/// вперемешку — отказы по расходу ЗИП уже по-русски («Недостаточно ЗИП на
/// складе: …»), служебные проверки по-английски. Английский обходчику не
/// показываем, русское отдаём как есть.
String scanErrorMessage(Object error) {
  if (error is AuthExpiredException) {
    return ScanQueueStrings.errorAuthExpired;
  }
  // Нехватка ЗИП: текст сервера уже по-русски и без чисел — сами числа
  // лежат в `shortages` и показываются отдельным блоком.
  if (error is InsufficientStockException) {
    return error.detail;
  }
  if (isOfflineError(error)) {
    return ScanQueueStrings.errorNoConnection;
  }
  final raw = _stripExceptionPrefix(error.toString()).trim();
  for (final entry in _translations.entries) {
    if (raw == entry.key || raw.contains(entry.key)) {
      return entry.value;
    }
  }
  return _looksRussian(raw) ? raw : ScanQueueStrings.errorGeneric;
}

/// Отказ, который сам рассосётся: связи нет или сервер временно недоступен.
///
/// Всё остальное — отказ по существу: осмотр так и будет отклоняться, пока
/// обходчик что-то не изменит, и долбить сервер каждые пять секунд нельзя.
///
/// 5xx считаем временным: это сбой сервера, а не наших данных.
bool isRetryableScanError(Object error) {
  if (isOfflineError(error)) return true;
  // Нет токена — осмотр не виноват. Цикл отправки не запускается без
  // авторизации, но выход мог случиться ровно между проверкой и запросом.
  // Помечать такой осмотр отклонённым нельзя: он уйдёт после входа сам.
  if (error is AuthExpiredException ||
      error.toString().contains(_notAuthenticated)) {
    return true;
  }
  // Нехватка ЗИП сама не рассосётся: пока склад не пополнят, ответ будет тот
  // же. Решение принимает обходчик на экране разрешения конфликта.
  if (error is InsufficientStockException) return false;
  final status = scanErrorStatusCode(error);
  return status != null && status >= 500;
}

/// Текст, которым методы `API` отвечают на пустой токен.
const String _notAuthenticated = 'Not authenticated';

/// Точный текст сервера для «осмотр уже закрыт»
/// (`backend/crud/fault_inspection.update_inspection_by_uuid`).
const String _inspectionAlreadyClosed = 'Закрытый осмотр нельзя изменить';

/// Отказ, который на самом деле означает успех.
///
/// Осмотр закрывается одним `PATCH`. Если ответ на него потерялся по дороге
/// (обрыв ровно между commit'ом и приёмом ответа), повтор придёт на уже
/// закрытый осмотр, и сервер откажет. Данные при этом на месте — считать это
/// отказом нельзя: обходчик увидел бы ошибку по успешно закрытой задаче.
///
/// Тот же приём, что у удаления снимка ремонта: «на сервере этого уже нет» —
/// цель достигнута.
bool isScanAlreadyDelivered(Object error) =>
    error.toString().contains(_inspectionAlreadyClosed);

/// Код ответа, если он был приклеен к тексту ошибки методом `sendScan`.
/// `null` — до сервера не дошли вовсе.
int? scanErrorStatusCode(Object error) {
  // Остальные методы `API` несут код в самом исключении — метка в тексте нужна
  // только `sendScan`, который собирает сообщение сам.
  if (error is ServerFailureException) return error.statusCode;
  final match = RegExp(r'\[HTTP (\d{3})\]').firstMatch(error.toString());
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// `Exception('текст')` печатается как `Exception: текст`.
String _stripExceptionPrefix(String text) {
  const prefix = 'Exception: ';
  var result = text;
  while (result.startsWith(prefix)) {
    result = result.substring(prefix.length);
  }
  // Метку кода ответа в сообщении для обходчика не показываем — она нужна
  // только для того, чтобы отличить 5xx от 4xx.
  return result.replaceAll(RegExp(r'\s*\[HTTP \d{3}\]'), '');
}

bool _looksRussian(String text) => RegExp('[а-яА-ЯёЁ]').hasMatch(text);

/// Ключи — точные строки из `backend/api/v1/company/fault_inspection.py` и
/// `backend/crud/fault_inspection.py`.
const Map<String, String> _translations = {
  'Company was not found': 'Компания не найдена',
  'Company is deactivated. Please renew your subscription.':
      'Доступ компании приостановлен. Обратитесь к администратору.',
  'Inspection was not found': 'Задача не найдена — возможно, её удалили',
  'Inspection does not belong to user\'s company':
      'Задача относится к другой компании',
  'Fault not found': 'Типовая неисправность не найдена',
  'Fault belongs to another equipment':
      'Неисправность относится к другому оборудованию',
  'Failed to update inspection': 'Не удалось сохранить осмотр',
  _notAuthenticated: 'Требуется войти в приложение заново',
  // Форма multipart разбирается до схемы: сюда попадает битый JSON расхода.
  'actual_consumptions must be a JSON array':
      'Не удалось передать расход ЗИП. Сообщите администратору.',
};
