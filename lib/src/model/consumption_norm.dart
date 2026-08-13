import 'repair.dart';

/// Норма расхода ЗИП. Приходит из `GET /v1/company/consumption_norms/`.
///
/// В Hive не кладётся: нормы нужны только при создании ремонта, а созданному
/// ремонту сервер и так возвращает норму вместе с составом внутри самого
/// ремонта. Офлайн-выгрузка норм — задача этапа с очередью.
class ConsumptionNorm {
  final String uuid;
  final String name;
  final String usageType;

  /// Состав нормы. Переиспользуем [RepairNormItem] — форма ровно та же
  /// («позиция ЗИП + плановое количество»), заводить второй такой же класс
  /// незачем.
  final List<RepairNormItem> items;

  ConsumptionNorm({
    required this.uuid,
    required this.name,
    required this.usageType,
    this.items = const [],
  });

  /// Тип нормы «для ремонта» — `ConsumptionNormType.REPAIR` на сервере.
  static const String repairUsageType = 'repair';

  /// Состав одной строкой: «Подшипник 6205 2RS × 2 · Масло И-20А × 5».
  String get compositionSummary => items
      .map(
          (item) => '${item.sparePartName} × ${_formatQuantity(item.quantity)}')
      .join(' · ');

  factory ConsumptionNorm.fromJson(Map<String, dynamic> json) {
    return ConsumptionNorm(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      usageType: json['usage_type']?.toString() ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((item) =>
                  RepairNormItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
