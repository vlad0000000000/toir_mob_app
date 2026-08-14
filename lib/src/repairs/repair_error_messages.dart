import '../exceptions/app_exceptions.dart';
import '../utils/offline_error.dart';

/// Человекочитаемое сообщение об ошибке для экранов ремонтов и карточки ЗИП.
///
/// Бэкенд отвечает вперемешку: часть отказов уже по-русски («Обходчик может
/// редактировать только открытый ремонт»), часть — служебными английскими
/// строками из CRUD-слоя («Equipment is already in repair»). Показывать
/// обходчику английский текст нельзя, поэтому переводим известные и
/// оставляем как есть те, что и так на русском.
String repairErrorMessage(Object error) {
  if (error is AuthExpiredException) {
    return 'Сессия истекла. Войдите в приложение заново.';
  }
  if (isOfflineError(error)) {
    return 'Нет связи с сервером. Проверьте интернет и повторите.';
  }
  final raw = _stripExceptionPrefix(error.toString()).trim();
  for (final entry in _translations.entries) {
    if (raw == entry.key || raw.contains(entry.key)) {
      return entry.value;
    }
  }
  // Уже по-русски — отдаём как есть. Иначе не мучаем пользователя
  // английским и служебными кодами.
  return _looksRussian(raw) ? raw : 'Не удалось выполнить действие';
}

/// `Exception('текст')` печатается как `Exception: текст`.
String _stripExceptionPrefix(String text) {
  const prefix = 'Exception: ';
  var result = text;
  // Отсекаем и вложенные обёртки вида «Exception: Exception: …».
  while (result.startsWith(prefix)) {
    result = result.substring(prefix.length);
  }
  return result;
}

bool _looksRussian(String text) => RegExp('[а-яА-ЯёЁ]').hasMatch(text);

/// Точный текст сервера для «ключ идемпотентности ещё обрабатывается»
/// (`backend/crud/repair.create_repair_idempotently`).
const String _idempotencyInFlight =
    'Idempotency key is being processed; retry the request';

/// То же самое, но для загрузки снимка
/// (`backend/crud/repair.reserve_repair_photo_upload_idempotency_key`).
const String _photoIdempotencyInFlight =
    'Photo upload idempotency key is being processed; retry the request';

/// Файловое хранилище (S3) недоступно временно — сервер отвечает 503.
/// В отличие от 404 «Storage is not available», это стоит повторить.
const String _storageTemporarilyUnavailable =
    'Storage is temporarily unavailable';

/// Отказ временный — черновик надо оставить в очереди и повторить, а не
/// показывать обходчику ошибку и не считать попытку неудачной.
///
/// Случаи: связи нет вовсе; сервер занят обработкой того же самого ключа
/// идемпотентности (наш же предыдущий запрос ещё не закоммитился — отдельно
/// для создания ремонта и для загрузки снимка); файловое хранилище прилегло.
bool isRetryableRepairError(Object error) {
  if (isOfflineError(error)) return true;
  final text = error.toString();
  return text.contains(_idempotencyInFlight) ||
      text.contains(_photoIdempotencyInFlight) ||
      text.contains(_storageTemporarilyUnavailable);
}

/// Ключи — точные строки из `backend/api/v1/repair.py` и
/// `backend/crud/repair.py`. При изменении текстов на сервере ломается
/// не логика, а только перевод: непереведённое уйдёт в общий фолбэк.
const Map<String, String> _translations = {
  // Офлайн-очередь: повтор пришёлся ровно на момент, когда первый запрос с тем
  // же Idempotency-Key ещё не закоммитился. Отказ временный.
  _idempotencyInFlight:
      'Ремонт уже отправляется. Повторим через несколько секунд.',
  _photoIdempotencyInFlight:
      'Фотография уже отправляется. Повторим через несколько секунд.',

  // Хранилище файлов (S3). Сервер больше не показывает исходный текст AWS —
  // отдаёт две обобщённые строки: 404 «настроено неверно / нет доступа» и
  // 503 «прилегло, можно повторить».
  'Storage is not available':
      'Хранилище файлов недоступно. Сообщите администратору.',
  _storageTemporarilyUnavailable:
      'Хранилище файлов временно недоступно. Повторим позже.',

  // Повтор загрузки снимка с тем же Idempotency-Key, но с другим содержимым.
  // Отказ окончательный: сервер уже принял по этому ключу другие файлы.
  //
  // Парного «Idempotent photo upload is incomplete» больше нет: если снимок,
  // записанный по ключу, потом удалили, сервер сам сбрасывает резервацию и
  // принимает загрузку заново, а не отвечает вечным 409.
  'Idempotency-Key was already used with a different photo upload':
      'Этот ключ отправки уже использован для другого снимка',

  // Доступ и состояние ремонта
  'Repair not found': 'Ремонт не найден',
  'No access to this repair': 'Нет доступа к этому ремонту',
  'Company was not found': 'Компания не найдена',
  'Company is deactivated. Please renew your subscription.':
      'Доступ компании приостановлен. Обратитесь к администратору.',
  'Closed repair cannot be edited': 'Ремонт закрыт — изменить его нельзя',
  'Closed repair cannot be deleted': 'Закрытый ремонт нельзя удалить',
  'Repair is already closed': 'Ремонт уже закрыт администратором',
  'Repair has already been submitted for review':
      'Ремонт уже отправлен на рассмотрение',
  'Only a repair under review can be closed':
      'Закрыть можно только ремонт на рассмотрении',
  'Only a repair under review can be returned for rework':
      'Вернуть на доработку можно только ремонт на рассмотрении',

  // Оборудование и справочники
  'Equipment is already in repair': 'Для этого оборудования уже есть ремонт',
  'Equipment not found': 'Оборудование не найдено',
  'One or more spare parts were not found':
      'Часть позиций ЗИП не найдена. Обновите справочник и повторите.',
  'Responsible user was not found in this company':
      'Ответственный не найден в компании',
  'Responsible role was not found in this company':
      'Должность не найдена в компании',
  'Repair photo not found': 'Фотография не найдена',

  // Даты
  'Completion date cannot be earlier than start date':
      'Дата завершения не может быть раньше даты начала',
  'Review date cannot be earlier than start date':
      'Дата отправки на рассмотрение не может быть раньше даты начала',

  // Общие сбои сервера
  'Failed to create repair': 'Не удалось создать ремонт',
  'Failed to update repair': 'Не удалось сохранить изменения',
  'Failed to delete repair': 'Не удалось удалить ремонт',
  'Failed to upload repair photos': 'Не удалось загрузить фотографии',
  'Failed to delete repair photo': 'Не удалось удалить фотографию',
  'Failed to delete repair photo from storage':
      'Не удалось удалить фотографию из хранилища',
  'Failed to fill actual consumptions from norm':
      'Не удалось заполнить расход из нормы',

  // Клиентские
  'Not authenticated': 'Требуется войти в приложение заново',
};
