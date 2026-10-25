import '../model/access_profile.dart';
import '../model/inventory_record.dart';

/// Оборудование из области обходчика — подразделений его роли.
///
/// Обходчику с `inspection.create` сервер отдаёт справочник **всей компании**
/// (бэкенд `06b145f`, независимо от флага «Осмотр без QR»): осмотр, заявку,
/// смену состояния, наработку и свой ремонт можно делать по любому
/// оборудованию. «Своё» в нём отличаем на телефоне — только для фильтра
/// «Моё подразделение / Все подразделения»; права на запись он не задаёт.
///
/// Как определяем:
/// 1. по подразделению оборудования ([InventoryRecord.divisionUuid]) — сервер
///    присылает его в `division`; сравниваем с подразделениями роли
///    ([AccessProfile.divisions]). `division: null` — не своё: оборудование
///    без подразделения сервер ни к одному не относит;
/// 2. если поля нет (сервер прошлой версии или запись до полной сверки) — как
///    раньше, через помещение: подразделение оборудования — это подразделение
///    его помещения (`equipment_ids` в `backend/security/policies/divisions.py`),
///    [myLocationUuids] — помещения своих подразделений
///    (`DataProvider.myLocationUuids`).
///
/// «Своим» считаем и то, о чём не знаем наверняка, — лучше показать лишнее,
/// чем спрятать нужное:
/// - [profile] `null` — сервер без ролей доступа: подразделений нет вовсе;
/// - у роли «все подразделения»;
/// - (по помещению) помещения своих подразделений ещё не загружены;
/// - (по помещению) у записи есть помещение, но нет его uuid — сохранена
///   прошлой версией, до ближайшей полной сверки справочника.
///
/// Оборудование без помещения — не своё: сервер такое тоже не относит ни к
/// одному подразделению.
bool isMyEquipment(
  InventoryRecord equipment, {
  required AccessProfile? profile,
  required Set<String>? myLocationUuids,
}) {
  if (profile == null || profile.allDivisions) return true;
  final division = equipment.divisionUuid;
  if (division != null) {
    if (division.isEmpty) return false;
    return profile.divisions.any((ref) => ref.uuid == division);
  }
  if (myLocationUuids == null) return true;
  final location = equipment.locationUuid;
  if (location == null) return (equipment.location ?? '').isNotEmpty;
  return myLocationUuids.contains(location);
}
