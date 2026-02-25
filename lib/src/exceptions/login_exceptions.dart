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

/// Исключение, возникающее при неверном логине или пароле
class InvalidCredentialsException implements Exception {
  final String message;
  InvalidCredentialsException([this.message = 'Invalid login or password']);
  
  @override
  String toString() => message;
}
