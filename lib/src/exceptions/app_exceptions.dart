/// Исключение, возникающее когда только обходчик (walker) может авторизироваться
class WalkerOnlyException implements Exception {
  final String message;
  WalkerOnlyException([this.message = 'Only walkers can login']);

  @override
  String toString() => message;
}

/// Исключение, возникающее при отсутствии соединения с сервером
class NoConnectionException implements Exception {
  final String message;
  NoConnectionException([this.message = 'No connection to server']);

  @override
  String toString() => message;
}

/// Токен доступа истёк или отозван — сервер ответил 401.
///
/// Отдельный тип, а не просто текст ошибки: офлайн-очередь работает в фоне,
/// вне экранов, и по этому исключению она обязана вести себя иначе, чем при
/// обычном отказе — не помечать черновик отклонённым (данные не виноваты) и
/// поднять пометку в интерфейс, чтобы обходчик вошёл заново.
class AuthExpiredException implements Exception {
  final String message;
  AuthExpiredException([this.message = 'Authentication expired']);

  @override
  String toString() => message;
}

/// Исключение, возникающее при неверном логине или пароле
class InvalidCredentialsException implements Exception {
  final String message;
  InvalidCredentialsException([this.message = 'Invalid login or password']);

  @override
  String toString() => message;
}
