import 'dart:convert';

import 'package:hive_ce/hive.dart';

import 'server_decimal.dart';

/// Позиция справочника ЗИП. Приходит из `GET /v1/company/spare_parts/`.
///
/// Вложенные `warehouse` и `nomenclature_group` намеренно разложены в пары
/// «uuid + название»: экрану они нужны только для фильтров и подписей, а
/// плоские поля избавляют от двух рукописных адаптеров и двух лишних typeId.
///
/// Одна номенклатура лежит ровно на одном складе — на сервере это единственный
/// nullable FK `spare_part.warehouse_id`. Поэтому «остаток» здесь одно число,
/// а не разрез по складам: одна и та же деталь на двух складах — это две
/// разные записи справочника.
class SparePart {
  final String uuid;
  final String name;
  final String? supplierCode;
  final String? unitCode;
  final String? unitName;
  final String? warehouseUuid;
  final String? warehouseName;
  final String? nomenclatureGroupUuid;
  final String? nomenclatureGroupName;
  final double quantity;
  final double? minimumStock;
  final double? stockNorm;

  /// Счёт бухгалтерского учёта («10.06.5»). Показывается только в карточке
  /// позиции — в поиске и фильтрах не участвует.
  final String? accountingAccount;

  /// Копия с другим остатком. См. [parseConsumptionWriteOff].
  ///
  /// Единственный случай — списание, только что принятое сервером: до
  /// ближайшей синхронизации каталога (раз в минуту) приложение обязано
  /// показывать уже уменьшенный остаток, иначе предупреждение о нехватке
  /// считалось бы по числу, которого на складе больше нет. Все остальные поля
  /// списание не меняет, поэтому отдельного полноценного `copyWith` тут не
  /// заводим — он только приглашал бы менять каталог мимо синхронизации.
  SparePart copyWithQuantity(double quantity) => SparePart(
        uuid: uuid,
        name: name,
        supplierCode: supplierCode,
        unitCode: unitCode,
        unitName: unitName,
        warehouseUuid: warehouseUuid,
        warehouseName: warehouseName,
        nomenclatureGroupUuid: nomenclatureGroupUuid,
        nomenclatureGroupName: nomenclatureGroupName,
        quantity: quantity,
        minimumStock: minimumStock,
        stockNorm: stockNorm,
        accountingAccount: accountingAccount,
      );

  SparePart({
    required this.uuid,
    required this.name,
    this.supplierCode,
    this.unitCode,
    this.unitName,
    this.warehouseUuid,
    this.warehouseName,
    this.nomenclatureGroupUuid,
    this.nomenclatureGroupName,
    this.quantity = 0,
    this.minimumStock,
    this.stockNorm,
    this.accountingAccount,
  });

  /// Название и артикул в нижнем регистре — заранее, для поиска.
  ///
  /// Считаются один раз при первом обращении и кэшируются (`late final`).
  /// На каталоге в десятки тысяч позиций `toLowerCase()` на каждое нажатие
  /// клавиши был бы главной статьёй расходов: две новые строки на позицию
  /// на каждый введённый символ.
  ///
  /// В Hive не пишутся — адаптер сохраняет только перечисленные в нём поля.
  late final String _nameLower = name.toLowerCase();
  late final String _codeLower = supplierCode?.toLowerCase() ?? '';

  /// Ключ сортировки каталога по русскому алфавиту.
  ///
  /// `String.compareTo` сравнивает кодовые единицы UTF-16, а не буквы, и на
  /// кириллице это заметно ломает порядок:
  ///
  /// * `Ё` (U+0401) стоит до `А` (U+0410) — «Ёмкость» уезжала в самое начало
  ///   каталога;
  /// * все строчные (`а` — U+0430) идут после всех прописных (`Я` — U+042F) —
  ///   «болт М6» оказывался ниже «Ящика», а «Болт М6» — в начале.
  ///
  /// В справочнике, где часть номенклатуры заведена с заглавной, а часть нет,
  /// список выглядел перемешанным, и найти позицию прокруткой было нельзя.
  ///
  /// Нижний регистр убирает вторую беду, замена `ё` → `е` — первую. Настоящей
  /// локале-зависимой коллации в Dart без сторонних пакетов нет, но эти два
  /// шага закрывают практически все реальные названия.
  ///
  /// Считается лениво и кэшируется, как и ключи поиска: сортировка идёт по
  /// всему каталогу, и пересчитывать строку на каждое сравнение нельзя.
  late final String _nameSortKey = _nameLower.replaceAll('ё', 'е');

  /// Сравнение двух позиций для сортировки каталога.
  static int compareByName(SparePart a, SparePart b) {
    final byName = a._nameSortKey.compareTo(b._nameSortKey);
    // При совпадении ключей — по исходному названию, чтобы порядок не «плавал»
    // между проходами: «Болт» и «болт» иначе вставали бы в случайном порядке.
    return byName != 0 ? byName : a.name.compareTo(b.name);
  }

  /// Совпадение с уже приведённым к нижнему регистру запросом.
  ///
  /// Два отдельных `contains` вместо одной склеенной строки: не нужен
  /// разделитель (через него запрос мог бы ложно совпасть, зацепив конец
  /// названия и начало артикула), и проверка короткозамкнута — у большинства
  /// позиций совпадение находится или отбрасывается уже по названию.
  bool matchesQuery(String lowerQuery) =>
      _nameLower.contains(lowerQuery) || _codeLower.contains(lowerQuery);

  /// Насколько остаток благополучен — одна оценка на все экраны.
  ///
  /// Раньше правило было записано трижды и трижды по-разному: строка
  /// справочника считала красным только нулевой остаток, а оранжевым — всё,
  /// что не выше минимума (`quantity <= minimum`); карточка позиции считала
  /// красным всё ниже минимума (`quantity < minimum`), оранжевым — ниже
  /// нормы. Одна и та же позиция получала в списке оранжевый, а в карточке
  /// красный.
  ///
  /// Порядок проверок важен: сначала «нет вовсе», потом минимум, потом норма.
  ///
  /// Нулевой остаток выделен отдельно намеренно. По формуле он попадал бы в
  /// [belowMinimum] только при заданном минимуме, а у позиции без порогов
  /// оказывался бы «достаточным» — то есть «списывать нечего» выглядело бы
  /// благополучно. Для склада это худшее из состояний, и от порогов оно не
  /// зависит.
  SparePartStockLevel get stockLevel {
    if (quantity <= 0) return SparePartStockLevel.out;
    final minimum = minimumStock;
    if (minimum != null && quantity < minimum) {
      return SparePartStockLevel.belowMinimum;
    }
    final norm = stockNorm;
    if (norm != null && quantity < norm) return SparePartStockLevel.belowNorm;
    return SparePartStockLevel.sufficient;
  }

  /// Подпись единицы измерения. Сначала название («шт», «кг»), и только
  /// потом код — в `unit_of_measure.code` лежит служебный код, а не то, что
  /// показывают человеку. Тот же порядок в веб-админке
  /// (`SparePartDetailDialog`: `unit?.name ?? unit?.code`).
  ///
  /// В отличие от админки не подставляем «шт», когда единицы нет вовсе:
  /// выдуманная единица измерения на складе хуже, чем её отсутствие.
  String get unitLabel {
    final name = unitName;
    if (name != null && name.isNotEmpty) return name;
    final code = unitCode;
    if (code != null && code.isNotEmpty) return code;
    return '';
  }

  factory SparePart.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] as Map<String, dynamic>?;
    final warehouse = json['warehouse'] as Map<String, dynamic>?;
    final group = json['nomenclature_group'] as Map<String, dynamic>?;
    return SparePart(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      supplierCode: json['supplier_code'] as String?,
      unitCode: unit?['code'] as String?,
      unitName: unit?['name'] as String?,
      warehouseUuid: warehouse?['uuid'] as String?,
      warehouseName: warehouse?['name'] as String?,
      nomenclatureGroupUuid: group?['uuid'] as String?,
      nomenclatureGroupName: group?['name'] as String?,
      quantity: parseServerDecimal(json['quantity']) ?? 0,
      minimumStock: parseServerDecimal(json['minimum_stock']),
      stockNorm: parseServerDecimal(json['stock_norm']),
      accountingAccount: json['accounting_account'] as String?,
    );
  }
}

/// Адаптер написан руками, как и все остальные в проекте: порядок чтения
/// обязан совпадать с порядком записи. Новое поле добавлять только в конец
/// [write] и читать в [read] через try/catch — иначе справочник на устройствах
/// станет нечитаемым.
class SparePartAdapter extends TypeAdapter<SparePart> {
  @override
  final int typeId = 22;

  @override
  SparePart read(BinaryReader reader) {
    // Поля читаем по одному, а не прямо в аргументах конструктора: порядок
    // вычисления именованных аргументов в Dart совпадает с порядком записи,
    // но полагаться на это в формате хранения не стоит.
    final uuid = reader.read();
    final name = reader.read();
    final supplierCode = reader.read();
    final unitCode = reader.read();
    final unitName = reader.read();
    final warehouseUuid = reader.read();
    final warehouseName = reader.read();
    final nomenclatureGroupUuid = reader.read();
    final nomenclatureGroupName = reader.read();
    final quantity = reader.read();
    final minimumStock = reader.read();
    final stockNorm = reader.read();
    return SparePart(
      uuid: uuid,
      name: name,
      supplierCode: supplierCode,
      unitCode: unitCode,
      unitName: unitName,
      warehouseUuid: warehouseUuid,
      warehouseName: warehouseName,
      nomenclatureGroupUuid: nomenclatureGroupUuid,
      nomenclatureGroupName: nomenclatureGroupName,
      quantity: quantity,
      minimumStock: minimumStock,
      stockNorm: stockNorm,
      accountingAccount: _readTrailing<String>(reader),
    );
  }

  /// Поле, добавленное после первого выпуска: в записях, сохранённых прежней
  /// версией, его в потоке нет — чтение упирается в конец буфера и бросает.
  /// Возвращаем `null`, справочник перезапишется на ближайшей синхронизации.
  static T? _readTrailing<T>(BinaryReader reader) {
    try {
      return reader.read() as T?;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(BinaryWriter writer, SparePart obj) {
    writer.write(obj.uuid);
    writer.write(obj.name);
    writer.write(obj.supplierCode);
    writer.write(obj.unitCode);
    writer.write(obj.unitName);
    writer.write(obj.warehouseUuid);
    writer.write(obj.warehouseName);
    writer.write(obj.nomenclatureGroupUuid);
    writer.write(obj.nomenclatureGroupName);
    writer.write(obj.quantity);
    writer.write(obj.minimumStock);
    writer.write(obj.stockNorm);
    writer.write(obj.accountingAccount);
  }
}

/// Разбирает строку фактического расхода в «uuid → сколько списать».
///
/// На вход — то же, что уходит на сервер в поле формы `actual_consumptions`:
/// `[{"spare_part_uuid": "...", "quantity": 2}]`. Строкой, потому что именно
/// строкой расход и хранится в осмотре (`Scan.actualConsumptions`) — разбирать
/// его обратно приходится ровно здесь.
///
/// Всё сомнительное отбрасывается молча: результат нужен для локальной
/// заплатки на остаток (см. `DataProvider.applyLocalStockWriteOff`), а не для
/// отчётности, и испортить каталог из-за кривой записи она не вправе. Нулевые
/// и отрицательные количества не проходят: сервер такие и не принял бы.
///
/// Повторы одной позиции складываются — на случай, если расход всё же придёт
/// с двумя строками на один uuid.
Map<String, double> parseConsumptionWriteOff(String? actualConsumptions) {
  if (actualConsumptions == null || actualConsumptions.isEmpty) return const {};
  final Object? parsed;
  try {
    parsed = jsonDecode(actualConsumptions);
  } catch (_) {
    return const {};
  }
  if (parsed is! List) return const {};

  final result = <String, double>{};
  for (final raw in parsed) {
    if (raw is! Map) continue;
    final uuid = raw['spare_part_uuid'];
    final quantity = raw['quantity'];
    if (uuid is! String || uuid.isEmpty) continue;
    // Число сервер и клиент пишут числом, но строка тоже разбирается: то же
    // послабление, что и в `parseServerDecimal`.
    final value = quantity is num
        ? quantity.toDouble()
        : (quantity is String ? double.tryParse(quantity) : null);
    if (value == null || value <= 0) continue;
    result[uuid] = (result[uuid] ?? 0) + value;
  }
  return result;
}

/// Состояние остатка позиции ЗИП. Значения идут от худшего к лучшему.
///
/// Только оценка, без цвета: раскрашивают её экраны, и по-разному. В строке
/// справочника благополучный остаток остаётся обычным серым — цвет там
/// означает «обрати внимание», и красить в него норму значит обесценить
/// сигнал. В карточке позиции тот же остаток зелёный: там он крупная цифра и
/// полоса запаса, и «всё хорошо» — законное сообщение.
enum SparePartStockLevel {
  /// Ноль и меньше — списывать нечего.
  out,

  /// Ниже неснижаемого запаса.
  belowMinimum,

  /// Выше минимума, но не дотягивает до нормы.
  belowNorm,

  /// Норма выполнена либо пороги не заданы и остаток есть.
  sufficient,
}
