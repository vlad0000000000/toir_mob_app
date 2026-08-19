import 'server_decimal.dart';

/// Плановый и фактический расход ЗИП по задаче — блок `spare_part_usage`
/// из `GET /v1/company/fault_inspections/`.
///
/// Приходит у **любой** периодической задачи. У заявки без задачи блока нет —
/// расход указывать некуда.
///
/// Раньше сервер отдавал блок только тем задачам, которым администратор
/// настроил расход, а `PATCH` с `actual_consumptions` по остальным отклонял
/// («Для этой задачи не настроен расход ЗИП»). С коммита `1d99a25` оба запрета
/// сняты: фактический расход можно указать и по задаче, для которой норму в
/// админке не выбирали. У такой задачи [mode] пуст, а [planned] — пустой
/// список: списывать есть что, сравнивать не с чем.
class SparePartUsage {
  /// `norm` — план берётся из нормы расхода, `manual` — из состава задачи,
  /// `null` — расход по задаче не настраивали.
  ///
  /// Приложение план только показывает, поэтому режим нужен ему двумя
  /// вещами: не потерять его при сохранении в Hive и отличить «расход забыли
  /// заполнить» от «расход по этой задаче и не планировался» — см.
  /// [isConfigured].
  final String? mode;

  /// Что положено по плану.
  final List<SparePartUsageItem> planned;

  /// Что уже списано. У ещё не закрытой задачи список пуст — сервер
  /// заполняет его только после отправки осмотра.
  final List<SparePartUsageItem> actual;

  const SparePartUsage({
    this.mode,
    this.planned = const [],
    this.actual = const [],
  });

  bool get hasPlan => planned.isNotEmpty;

  /// Администратор настроил по этой задаче расход ЗИП — норму или ручной
  /// состав. Отличается от [hasPlan]: режим может быть задан, а состав пуст.
  ///
  /// От этого зависит, переспрашивать ли перед отправкой осмотра без единой
  /// позиции. По настроенной задаче пустой расход — скорее всего забывчивость,
  /// по ненастроенной — обычное дело.
  bool get isConfigured => (mode ?? '').isNotEmpty;

  factory SparePartUsage.fromJson(Map<String, dynamic> json) {
    List<SparePartUsageItem> parse(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SparePartUsageItem.fromJson)
            .toList();

    return SparePartUsage(
      // Именно `null`, а не пустая строка: у ненастроенной задачи сервер
      // присылает `mode: null`, и это осмысленное значение, а не «не пришло».
      mode: json['mode'] as String?,
      planned: parse('planned_consumptions'),
      actual: parse('actual_consumptions'),
    );
  }

  /// Обратно в JSON — только чтобы положить блок в Hive одной строкой.
  /// Формат намеренно совпадает с серверным: разбор один и тот же.
  Map<String, dynamic> toJson() => {
        'mode': mode,
        'planned_consumptions': [for (final item in planned) item.toJson()],
        'actual_consumptions': [for (final item in actual) item.toJson()],
      };
}

/// Позиция плана или факта.
class SparePartUsageItem {
  final String sparePartUuid;
  final String sparePartName;
  final double quantity;

  /// Плановое количество этой же позиции. Сервер присылает его только в
  /// фактическом расходе; в плане поля нет.
  final double? normQuantity;

  const SparePartUsageItem({
    required this.sparePartUuid,
    required this.sparePartName,
    this.quantity = 0,
    this.normQuantity,
  });

  factory SparePartUsageItem.fromJson(Map<String, dynamic> json) {
    final sparePart = json['spare_part'] as Map<String, dynamic>?;
    return SparePartUsageItem(
      sparePartUuid: sparePart?['uuid'] as String? ?? '',
      sparePartName: sparePart?['name'] as String? ?? '',
      quantity: parseServerDecimal(json['quantity']) ?? 0,
      normQuantity: parseServerDecimal(json['norm_quantity']),
    );
  }

  Map<String, dynamic> toJson() => {
        'spare_part': {'uuid': sparePartUuid, 'name': sparePartName},
        'quantity': quantity,
        if (normQuantity != null) 'norm_quantity': normQuantity,
      };
}
