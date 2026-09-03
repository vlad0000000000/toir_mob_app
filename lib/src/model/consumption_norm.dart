import 'package:hive_ce/hive.dart';

import '../utils/quantity_format.dart';
import 'repair.dart';

/// Норма расхода ЗИП. Приходит из `GET /v1/company/consumption_norms/`.
///
/// Кэшируется в Hive: без неё форма создания ремонта офлайн не даёт выбрать
/// ничего, кроме «Не задана», — а именно без связи ремонт чаще всего и
/// заводят. Каталог маленький (десятки позиций на компанию), поэтому едет
/// целиком вместе с остальными справочниками.
///
/// Уже созданному ремонту состав нормы сервер возвращает внутри самого
/// ремонта, поэтому «Заполнить из нормы» на карточке работало офлайн и до
/// этого кэша.
class ConsumptionNorm {
  final String uuid;
  final String name;
  final String usageType;

  /// Оборудование, к которому привязана норма. В кэше по нему отбирают нормы
  /// для формы создания: серверного фильтра офлайн нет.
  final String equipmentUuid;

  /// Состав нормы. Переиспользуем [RepairNormItem] — форма ровно та же
  /// («позиция ЗИП + плановое количество»), заводить второй такой же класс
  /// незачем.
  final List<RepairNormItem> items;

  ConsumptionNorm({
    required this.uuid,
    required this.name,
    required this.usageType,
    this.equipmentUuid = '',
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
    // Оборудование приходит вложенным объектом, но у старых записей могло
    // прийти голым uuid — принимаем оба вида, лишь бы не потерять привязку.
    final equipment = json['equipment'];
    return ConsumptionNorm(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      usageType: json['usage_type']?.toString() ?? '',
      equipmentUuid: equipment is Map<String, dynamic>
          ? (equipment['uuid'] as String? ?? '')
          : (json['equipment_uuid'] as String? ?? ''),
      items: (json['items'] as List<dynamic>?)
              ?.map((item) =>
                  RepairNormItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Адаптер написан руками, как и все остальные в проекте: `build_runner`
/// здесь не запускают. Порядок чтения обязан повторять порядок записи.
class ConsumptionNormAdapter extends TypeAdapter<ConsumptionNorm> {
  @override
  final int typeId = 29;

  @override
  ConsumptionNorm read(BinaryReader reader) {
    return ConsumptionNorm(
      uuid: reader.read(),
      name: reader.read(),
      usageType: reader.read(),
      equipmentUuid: reader.read(),
      items: reader.read().cast<RepairNormItem>(),
    );
  }

  @override
  void write(BinaryWriter writer, ConsumptionNorm obj) {
    writer.write(obj.uuid);
    writer.write(obj.name);
    writer.write(obj.usageType);
    writer.write(obj.equipmentUuid);
    writer.write(obj.items);
  }
}

String _formatQuantity(double value) => formatQuantity(value);
