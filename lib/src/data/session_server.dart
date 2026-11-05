/// Какой сервер выдал вход пользователю — ключ в `stringBox`.
///
/// Токен одного сервера другой не примет никогда: подписи разные. А сменить
/// сервер у установленного приложения — обычное дело для тестировщика:
/// другая сборка, другой стенд, другой `API_ENDPOINT`. Без этой отметки
/// приложение восстанавливало сессию прошлого сервера и работало «вслепую» —
/// синхронизация падала на 401, а обходчик смотрел на старый кэш (стенд
/// 05.11). Отметка — на логин, а не на текущую сессию: по ней же офлайн-вход
/// отличает локальную запись этого сервера от записи прошлого.
String userServerKey(String username) => 'user_server:$username';

/// Адрес сервера для сравнения: без пробелов и завершающих слешей, без
/// учёта регистра — `https://Host/` и `https://host` один сервер.
String normalizeServerAddress(String address) {
  var result = address.trim().toLowerCase();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Вход, выданный сервером [stored], годится для сервера [current].
///
/// `null` — отметки нет: запись прошлой версии приложения, где сервер не
/// запоминали. Считаем своей — иначе обновление выкинуло бы всех на вход и
/// закрыло офлайн-вход. Если сервер на самом деле другой, первый же ответ 401
/// выведет на вход (`shouldSignOutExpiredSession`).
bool isSameServer({required String? stored, required String current}) =>
    stored == null ||
    normalizeServerAddress(stored) == normalizeServerAddress(current);
