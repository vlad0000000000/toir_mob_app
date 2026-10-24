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
  // Нехватка ЗИП. Текст сервера здесь **английский** и таким останется: он
  // помечен в `backend/exceptions/common.py` как legacy и стабильный, а
  // локализовать его велено клиенту по `detail_code`. Числа не подставляем —
  // они лежат в `shortages` и показываются отдельным блоком.
  if (error is InsufficientStockException) {
    return ScanQueueStrings.errorInsufficientStock;
  }
  // Отказ по модели доступа — своими словами, а не текстом сервера: по этой
  // строке экран разбора и повтор после смены доступа узнают вид отказа
  // ([isClosedByOtherReason], [isTakenByOtherReason], [isNoRightsReason]).
  if (error is AccessDeniedException) {
    if (error.isClosedByOther) return ScanQueueStrings.errorClosedByOther;
    if (error.isTakenByOther) return ScanQueueStrings.errorTakenByOther;
    if (error.isNoRights) return ScanQueueStrings.errorNoRights;
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

/// Причина отказа, уже лежащая в очереди, — для показа на экране.
///
/// [scanErrorMessage] переводит ошибку в момент отказа, но результат остаётся
/// в Hive навсегда. Осмотры, отклонённые прежними версиями приложения, хранят
/// английский текст сервера, и без этой проверки он доезжал до обходчика как
/// есть («Insufficient spare parts in warehouses»). Прогоняем сохранённое
/// через тот же словарь: непереведённое английское заменяем общей фразой —
/// показать английский хуже, чем показать «сервер не принял осмотр».
String scanStoredReason(String? stored) {
  final raw = _stripExceptionPrefix((stored ?? '').trim()).trim();
  if (raw.isEmpty) return ScanQueueStrings.errorGeneric;
  for (final entry in _translations.entries) {
    if (raw == entry.key || raw.contains(entry.key)) {
      return entry.value;
    }
  }
  return _looksRussian(raw) ? raw : ScanQueueStrings.errorGeneric;
}

/// Сохранённая причина — «задачу уже выполнил другой исполнитель»: повторять
/// отправку бессмысленно, остаётся удалить запись.
bool isClosedByOtherReason(String? stored) =>
    stored == ScanQueueStrings.errorClosedByOther;

/// Сохранённая причина — «задачу взял в работу другой исполнитель»: задачу
/// ещё могут переназначить обратно, поэтому повтор доступен.
bool isTakenByOtherReason(String? stored) =>
    stored == ScanQueueStrings.errorTakenByOther;

/// Сохранённая прошлой версией причина «взял или закрыл другой» — какой из
/// двух, неизвестно. Не окончательная: повтор доступен, и ответ сервера
/// заменит её точной ([ScanQueueStrings.errorTakenOrClosedLegacy]).
bool isTakenOrClosedLegacyReason(String? stored) =>
    stored == ScanQueueStrings.errorTakenOrClosedLegacy;

/// Сохранённая причина — «нет прав»: запись повторяют, когда доступ меняется
/// (`DataProvider.retryNoRightsRejections`).
bool isNoRightsReason(String? stored) =>
    stored == ScanQueueStrings.errorNoRights;

/// Сохранённая причина — «сервер не нашёл оборудование» (404 на прямом
/// осмотре). Чаще всего это не удалённое оборудование, а доступ: оно в
/// чужом подразделении, а флаг компании «Осмотр без QR» выключен. Включение
/// флага или смена роли меняют версию доступа — тогда запись повторяется
/// сама, как и «нет прав» (`DataProvider.retryNoRightsRejections`).
///
/// Через [scanStoredReason]: записи прошлых версий хранят английский текст
/// сервера.
bool isEquipmentNotFoundReason(String? stored) =>
    stored != null &&
    scanStoredReason(stored) == ScanQueueStrings.errorEquipmentNotFound;

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
  // 409 по ключу события, который сервер ещё обрабатывает: параллельный
  // запрос с тем же ключом пока не завершился. Это не отказ — сервер прямо
  // просит повторить; пометить осмотр отклонённым значило бы бросить его.
  if (error.toString().contains(_keyInProgress)) return true;
  final status = scanErrorStatusCode(error);
  return status != null && status >= 500;
}

/// Текст, которым методы `API` отвечают на пустой токен.
const String _notAuthenticated = 'Not authenticated';

/// 409 сервера: запрос с этим `Idempotency-Key` ещё выполняется
/// (`backend/services/inspection_operations.py`).
const String _keyInProgress = 'Idempotency-Key is being processed';

/// 410 сервера: событие по этому ключу было принято, но осмотр с тех пор
/// удалили. Повторно сервер его не создаёт.
const String _keyResultDeleted =
    'The inspection for this Idempotency-Key no longer exists';

/// 400 сервера на повтор создания по ключу события
/// (`backend/mappers/fault_inspection.py`): осмотр по оборудованию чужого
/// подразделения создан, но повтор грузит его без допуска к чужому
/// оборудованию, и собрать ответ сервер не может. Тот же текст бывает, если
/// ответ не собрался сразу после создания (там он уходит как 500, и
/// следующий повтор приходит сюда). В обоих случаях осмотр уже на сервере.
const String _replayEquipmentHidden =
    'is not linked to any equipment or periodic task';

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
///
/// Сюда же 410 по ключу события: осмотр сервер когда-то принял, а потом его
/// удалил администратор. Отправлять его заново некуда и незачем — событие
/// доставлено, его судьбой распорядились на сервере.
///
/// И повтор создания осмотра по чужому оборудованию
/// ([_replayEquipmentHidden]): сервер узнал ключ — осмотр создан, отказ
/// только в том, что ответ не собрался.
bool isScanAlreadyDelivered(Object error) {
  final text = error.toString();
  return text.contains(_inspectionAlreadyClosed) ||
      text.contains(_keyResultDeleted) ||
      text.contains(_replayEquipmentHidden);
}

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
  // `InsufficientStockError.detail` из `backend/exceptions/common.py`. Ловится
  // и типом выше — здесь на случай осмотров, отклонённых прежней версией
  // приложения: у них английский текст уже лежит в базе.
  'Insufficient spare parts in warehouses':
      ScanQueueStrings.errorInsufficientStock,
  'Company was not found': 'Компания не найдена',
  'Company is deactivated. Please renew your subscription.':
      'Доступ компании приостановлен. Обратитесь к администратору.',
  'Inspection was not found': 'Задача не найдена — возможно, её удалили',
  'Inspection does not belong to user\'s company':
      'Задача относится к другой компании',
  'Fault not found': 'Типовая неисправность не найдена',
  // Прямой осмотр по оборудованию, которого сервер не видит: удалено или в
  // чужом подразделении, пока сервер пускает к чужому оборудованию только с
  // флагом компании «Осмотр без QR» (`backend/crud/fault_inspection.py`).
  'Equipment not found': ScanQueueStrings.errorEquipmentNotFound,
  'Fault belongs to another equipment':
      'Неисправность относится к другому оборудованию',
  'Failed to update inspection': 'Не удалось сохранить осмотр',
  _notAuthenticated: 'Требуется войти в приложение заново',
  // Форма multipart разбирается до схемы: сюда попадает битый JSON расхода.
  'actual_consumptions must be a JSON array':
      'Не удалось передать расход ЗИП. Сообщите администратору.',
  // Наработка: и отдельным запросом, и в составе осмотра
  // (`backend/crud/equipment_usage_parameter.py`,
  // `backend/services/inspection_operations.py`). В составе осмотра отказ
  // откатывает и сам осмотр — текст об этом и говорит.
  'Cannot decrease current_value':
      'Наработка меньше текущей, а уменьшать её запрещено. Удалите запись и '
          'внесите верное показание при следующем сканировании.',
  'was not found for inspection equipment':
      'Параметр наработки не найден у этого оборудования — возможно, его '
          'удалили.',
  'usage_updates requires equipment':
      'Не удалось передать наработку: не указано оборудование.',
  'usage_updates must be a JSON array':
      'Не удалось передать наработку. Сообщите администратору.',
  'no more than 2 decimal places':
      'Наработка указана точнее сотых — сервер её не принял.',
  'A closed inspection cannot accept new usage_updates':
      'Задача уже закрыта — добавить к ней наработку нельзя. Внесите '
          'показание при следующем сканировании.',
  // Доработка возвращённого результата (`update_fault_inspection_endpoint`):
  // пока осмотр ждал связи, проверяющий вернул задачу ещё раз — сданное
  // отвечает на прежний возврат. Машинного кода у отказа нет, узнаём по
  // имени поля в тексте.
  'review_revision': ScanQueueStrings.errorReworkOutdated,
  // Ключ события.
  'Idempotency-Key was already used with a different request':
      'Этот осмотр уже был отправлен с другими данными. Сообщите '
          'администратору.',
  'File exceeds 10 MB': 'Фото больше 10 МБ — переснимите его.',
};
