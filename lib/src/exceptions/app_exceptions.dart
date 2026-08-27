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

  /// Название позиции, как его прислал сервер вместе с отказом.
  ///
  /// Сервер кладёт его в `shortages` (`crud/fault_inspection.py:513`), но
  /// разбор его раньше терял, и экран конфликта искал подпись в четырёх
  /// запасных источниках — вплоть до голого uuid. При этом самое авторитетное
  /// название приезжало прямо в отказе: оно взято из той же записи склада, по
  /// которой сервер и посчитал нехватку.
  ///
  /// Пустая строка — сервер прислал `null` (позицию удалили между проверкой и
  /// формированием ответа) либо это отказ старого формата.
  final String sparePartName;

  final double required;
  final double available;

  const InsufficientStockItem({
    required this.sparePartUuid,
    this.sparePartName = '',
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
      sparePartName: json['spare_part_name'] as String? ?? '',
      required: parse(json['required']),
      available: parse(json['available']),
    );
  }

  /// Формат намеренно совпадает с серверным: отказ сохраняется в осмотре
  /// (`Scan.lastShortages`) и разбирается тем же `fromJson`. Название сюда
  /// обязано попасть — иначе оно терялось бы при первой же записи в Hive, и
  /// правка не пережила бы перезапуск приложения.
  Map<String, dynamic> toJson() => {
        'spare_part_uuid': sparePartUuid,
        if (sparePartName.isNotEmpty) 'spare_part_name': sparePartName,
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

/// Сервер ответил, но отказал. Хранит код ответа — без него отказ «оборудование
/// уже в ремонте» (409, повторять бессмысленно) неотличим от «шлюз не достучался
/// до бэкенда» (502/503/504, повторить обязательно).
///
/// Именно это ломало создание ремонта без связи: телефон в сети, но сервер
/// недоступен — прокси отвечает 502, приложение считало это отказом по делу и
/// показывало «Не удалось создать ремонт», вместо того чтобы положить черновик
/// в очередь.
///
/// [toString] печатается ровно как прежний `Exception(текст)`: переводы ошибок
/// разбирают строку, и менять её формат нельзя.
class ServerFailureException implements Exception {
  final int statusCode;
  final String message;

  ServerFailureException(this.statusCode, this.message);

  /// Сбой на стороне сервера или шлюза, а не отказ по существу запроса.
  /// 408 — таймаут запроса, 429 — «слишком часто»: оба лечатся повтором.
  bool get isTransient =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => 'Exception: $message';
}
