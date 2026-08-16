/// Исключение, возникающее когда только обходчик (walker) может авторизироваться
/// Сервер отказал в списании: на складе не хватает ЗИП.
///
/// Отдельный тип, а не разбор текста: с коммита `c6a430a` бэкенд отвечает
/// 409 с машиночитаемым телом — `detail_code: "insufficient_stock"` и списком
/// `shortages` вида `{spare_part_uuid, required, available}`. Числа в `detail`
/// больше не приходят, поэтому экран разрешения конфликта берёт их отсюда.
class InsufficientStockException implements Exception {
  /// Человекочитаемая причина от сервера («Недостаточно ЗИП на складе»).
  final String detail;

  /// Позиции, которых не хватило, — как их видит сервер. Пустой список
  /// возможен: тело могло прийти без `shortages`.
  final List<InsufficientStockItem> shortages;

  InsufficientStockException(this.detail, this.shortages);

  @override
  String toString() => detail;
}

/// Одна строка нехватки: сколько нужно и сколько есть по данным сервера.
class InsufficientStockItem {
  final String sparePartUuid;
  final double required;
  final double available;

  const InsufficientStockItem({
    required this.sparePartUuid,
    required this.required,
    required this.available,
  });

  factory InsufficientStockItem.fromJson(Map<String, dynamic> json) {
    double parse(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return InsufficientStockItem(
      sparePartUuid: json['spare_part_uuid'] as String? ?? '',
      required: parse(json['required']),
      available: parse(json['available']),
    );
  }

  Map<String, dynamic> toJson() => {
        'spare_part_uuid': sparePartUuid,
        'required': required,
        'available': available,
      };
}

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
