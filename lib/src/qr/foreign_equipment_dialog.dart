import 'package:flutter/material.dart';

import '../../strings.dart';
import '../model/inventory_record.dart';
import '../widgets/info_dialog.dart';

/// Предупреждение при скане QR оборудования не из подразделений обходчика
/// (`DataProvider.isOwnEquipment`). Возвращает «открыть всё равно».
///
/// Решение продукта: подразделение не запрещает — обходчик у станка должен
/// иметь возможность провести и отправить осмотр по любому оборудованию
/// компании. Окно только предупреждает, что станок не его зоны, чтобы он не
/// взялся за чужое по ошибке. Фильтр подразделений в списке оборудования на
/// скан не влияет: предупреждение есть всегда.
///
/// В общем стиле окон приложения ([InfoDialog]); цвет основной, а не
/// предупреждающий — это не запрет.
Future<bool> confirmForeignEquipment(
  BuildContext context,
  InventoryRecord machine,
) {
  return showConfirmDialog(
    context,
    icon: Icons.domain_rounded,
    tone: DialogTone.primary,
    title: ForeignEquipmentStrings.title,
    body: ForeignEquipmentStrings.body(machine.name, machine.location),
    confirmLabel: ForeignEquipmentStrings.open,
    cancelLabel: ForeignEquipmentStrings.cancel,
  );
}
