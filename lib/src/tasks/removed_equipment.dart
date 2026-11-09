import '../model/inventory_record.dart';
import '../model/task.dart';
import '../../strings.dart';

/// Новый набор подтверждённо удалённого оборудования: к [current] добавляются
/// [deleted] из ответа сервера и убираются [restored] — то, что снова пришло
/// записью (восстановили в вебе или импорт создал заново).
Set<String> updateRemovedEquipment(
  Set<String> current, {
  required Iterable<String> deleted,
  required Iterable<String> restored,
}) =>
    {...current, ...deleted}..removeAll(restored);

/// Записи для «Задач» — по одной на удалённое оборудование среди [tasks]
/// (оборудования нет в [knownEquipment]). [tasks] — уже видимые обходчику
/// (`isTaskEquipmentShown`): взятые им задачи по оборудованию, удаление
/// которого подтвердил сервер.
///
/// Название, модель и `id` — из ответа сервера (`periodic_task.equipment`).
/// У задачи без шаблона их нет: тогда общее название и отрицательный `id`.
List<InventoryRecord> removedEquipmentRecords(
  Iterable<Task> tasks, {
  required Set<String> knownEquipment,
}) {
  final byUuid = <String, InventoryRecord>{};
  for (final task in tasks) {
    final uuid = task.equipmentUuid;
    if (uuid.isEmpty || knownEquipment.contains(uuid)) continue;
    byUuid.putIfAbsent(uuid, () {
      final equipment = task.periodicTask?.equipment;
      return InventoryRecord(
        id: equipment?.id ?? -(byUuid.length + 1),
        uuid: uuid,
        name: equipment?.name ??
            task.equipmentName ??
            RemovedEquipmentStrings.unknownName,
        typeModel: equipment?.typeModel,
        serialNumber: null,
        location: null,
      );
    });
  }
  return byUuid.values.toList();
}
