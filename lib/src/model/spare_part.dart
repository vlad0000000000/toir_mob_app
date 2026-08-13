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

  /// Совпадение с уже приведённым к нижнему регистру запросом.
  ///
  /// Два отдельных `contains` вместо одной склеенной строки: не нужен
  /// разделитель (через него запрос мог бы ложно совпасть, зацепив конец
  /// названия и начало артикула), и проверка короткозамкнута — у большинства
  /// позиций совпадение находится или отбрасывается уже по названию.
  bool matchesQuery(String lowerQuery) =>
      _nameLower.contains(lowerQuery) || _codeLower.contains(lowerQuery);

  /// Остаток опустился до неснижаемого запаса — такие позиции экран
  /// подсвечивает. Если минимум не задан, предупреждать не о чем.
  bool get isBelowMinimum {
    final minimum = minimumStock;
    return minimum != null && quantity <= minimum;
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
