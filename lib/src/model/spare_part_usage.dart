import 'server_decimal.dart';

/// Плановый и фактический расход ЗИП по задаче — блок `spare_part_usage`
/// из `GET /v1/company/fault_inspections/`.
///
/// Приходит только у периодических задач, которым администратор настроил
/// расход (`spare_part_usage_mode` на стороне сервера). У заявок и у задач без
/// настройки блока нет вовсе — и раздела расхода в форме осмотра тоже быть не
/// должно: `PATCH` с `actual_consumptions` по такой задаче сервер отклонит
/// («Для этого осмотра не настроен расход ЗИП»).
class SparePartUsage {
  /// `norm` — план берётся из нормы расхода, `manual` — из состава задачи.
  /// Приложение план только показывает, поэтому режим нужен лишь для того,
  /// чтобы не потерять его при сохранении в Hive.
  final String mode;

  /// Что положено по плану.
  final List<SparePartUsageItem> planned;

  /// Что уже списано. У ещё не закрытой задачи список пуст — сервер
  /// заполняет его только после отправки осмотра.
  final List<SparePartUsageItem> actual;

  const SparePartUsage({
    required this.mode,
    this.planned = const [],
    this.actual = const [],
  });

  bool get hasPlan => planned.isNotEmpty;

  factory SparePartUsage.fromJson(Map<String, dynamic> json) {
    List<SparePartUsageItem> parse(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SparePartUsageItem.fromJson)
            .toList();

    return SparePartUsage(
      mode: json['mode'] as String? ?? '',
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
