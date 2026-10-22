import '../model/access_profile.dart';

/// Какие разделы и действия приложения доступны по роли — одно место для
/// всех экранов.
///
/// Решение продукта: недоступное **не прячется**, а показывается с замком и
/// по нажатию объясняет «нет доступа» (`widgets/no_access.dart`). Иначе
/// обходчик не понял бы, почему у коллеги плитка есть, а у него нет.
///
/// Права проверяет сервер на каждом запросе — здесь только подсказка
/// интерфейсу, чтобы не вести обходчика в заведомый отказ. Коды и их смысл —
/// каталог бэкенда (`backend/security/permissions.py`), какие ручки чего
/// требуют — `docs/backend-mobile-access-fixes.md` в корне workspace.
///
/// Профиль неизвестен ([profile] `null`: вошли прошлой версией и с тех пор
/// без сети) — открыто всё, как было до ролей: запирать по незнанию нельзя,
/// а сервер всё равно ответит сам.
class SectionAccess {
  final AccessProfile? profile;

  /// У компании включён осмотр без QR (`Company.allowRequestsWithoutQr`).
  final bool qrFreeEnabled;

  const SectionAccess({required this.profile, required this.qrFreeEnabled});

  bool can(String permission) => profile?.can(permission) ?? true;

  /// Выполнение задач: раздел «Задачи» и выбор задачи на экране скана.
  bool get tasks => can(Perm.tasksExecute);

  /// Осмотр и сообщение о проблеме без задачи. Им же открывается вход «Осмотр
  /// оборудования» без QR — сервер даёт его только с этим правом.
  bool get inspection => can(Perm.inspectionCreate);

  /// Сканер: есть что найти и есть что сделать.
  ///
  /// Найти — справочник оборудования (`equipment.view`) или осмотр без QR:
  /// при нём сервер отдаёт оборудование всей компании и без этого права.
  /// Сделать — выполнить задачу или записать осмотр; без обоих сканировать
  /// бессмысленно, экран результата был бы пустой формой.
  bool get scanner {
    final canFind = can(Perm.equipmentView) ||
        (qrFreeEnabled && can(Perm.inspectionCreate));
    return canFind && (tasks || inspection);
  }

  bool get repairs => can(Perm.repairView);

  /// Создание ремонта — пункт «В ремонте» чипа состояния.
  bool get repairCreate => can(Perm.repairCreate);

  /// Работа над своим ремонтом: взять, комментарий, расход, фото, отправка
  /// на рассмотрение.
  bool get repairWork => can(Perm.repairExecute);

  bool get spareParts => can(Perm.sparePartsView);

  bool get notifications => can(Perm.notificationsView);

  /// Смена состояния оборудования (кроме «В ремонте» — его ставит сервер при
  /// создании ремонта, см. [repairCreate]).
  bool get changeState => can(Perm.equipmentEdit);

  /// Ввод показаний наработки — и отдельно, и в составе осмотра. Без права
  /// сервер отклонит весь осмотр, вместе с закрытием задачи.
  bool get usage => can(Perm.equipmentView) && can(Perm.usageParametersEdit);
}
