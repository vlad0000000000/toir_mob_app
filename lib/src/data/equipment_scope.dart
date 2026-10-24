import '../model/access_profile.dart';
import '../model/inventory_record.dart';

/// Оборудование из области обходчика — подразделений его роли.
///
/// Обычно справочник и так приходит только своим: сервер отбирает его по
/// подразделениям. Но при «Осмотре без QR» сервер намеренно отдаёт обходчику
/// оборудование **всей компании** (осмотр и сообщение о проблеме можно
/// завести по любому), и «своё» в нём приходится отличать на телефоне —
/// для фильтра «Моё подразделение / Все подразделения».
///
/// Правило — то же, что у сервера: подразделение оборудования — это
/// подразделение его помещения (`equipment_ids` в
/// `backend/security/policies/divisions.py`). [myLocationUuids] — помещения
/// своих подразделений, их отдаёт сервер (`DataProvider.myLocationUuids`).
///
/// «Своим» считаем и то, о чём не знаем наверняка, — лучше показать лишнее,
/// чем спрятать нужное:
/// - [profile] `null` — сервер без ролей доступа: подразделений нет вовсе;
/// - у роли «все подразделения»;
/// - помещения своих подразделений ещё не загружены;
/// - у записи есть помещение, но нет его uuid — сохранена прошлой версией,
///   до ближайшей полной сверки справочника.
///
/// Оборудование без помещения — не своё: сервер такое тоже не относит ни к
/// одному подразделению.
bool isMyEquipment(
  InventoryRecord equipment, {
  required AccessProfile? profile,
  required Set<String>? myLocationUuids,
}) {
  if (profile == null || profile.allDivisions) return true;
  if (myLocationUuids == null) return true;
  final location = equipment.locationUuid;
  if (location == null) return (equipment.location ?? '').isNotEmpty;
  return myLocationUuids.contains(location);
}
