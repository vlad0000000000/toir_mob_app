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

  /// Фактический расход для отправки в правке ремонта — или `null`, чтобы
  /// поля в запросе не было вовсе.
  ///
  /// Сервер принимает `actual_consumptions` (даже пустой список) только с
  /// правом на ЗИП, а без него отклоняет **всю** правку — и комментарий, и
  /// отправку на рассмотрение. Роль без права расход и не меняет: блок на
  /// карточке заперт. Непустой расход без права сюда не доходит — его
  /// держит [consumptionsBlocked].
  List<T>? consumptionsToSend<T>(List<T> consumptions) =>
      spareParts ? consumptions : null;

  /// Правку с расходом отправить нельзя: расход есть, а права на ЗИП уже
  /// нет (сняли после того, как его внесли). Выбросить расход и отправить
  /// остальное значило бы потерять его безвозвратно — запись после
  /// отправки удаляется как доставленная, — а ремонт ушёл бы на
  /// рассмотрение без расхода. Такую правку держат с причиной «нет прав»:
  /// её видно в блоке «Не отправлено», и она уйдёт сама, когда доступ
  /// вернут (`retryNoRightsRejections`).
  bool consumptionsBlocked(List<Object?> consumptions) =>
      !spareParts && consumptions.isNotEmpty;

  bool get notifications => can(Perm.notificationsView);

  /// Смена состояния оборудования (кроме «В ремонте» — его ставит сервер при
  /// создании ремонта, см. [repairCreate]).
  ///
  /// Хватает узкого `equipment.change_state`: приложение шлёт в PATCH только
  /// поле `state`, а остальное сервер требует уже по `equipment.edit`.
  /// Полное право тоже подходит — и у ролей, настроенных до появления узкого,
  /// и у сервера, который узкого ещё не знает.
  bool get changeState =>
      can(Perm.equipmentChangeState) || can(Perm.equipmentEdit);

  /// Ввод показаний наработки — и отдельно, и в составе осмотра. Без права
  /// сервер отклонит весь осмотр, вместе с закрытием задачи.
  ///
  /// Хватает узкого `usage_parameters.record`: приложение меняет только
  /// текущее показание, настройки ТО не трогает. Полное
  /// `usage_parameters.edit` подходит по той же причине, что у [changeState].
  bool get usage =>
      can(Perm.equipmentView) &&
      (can(Perm.usageParametersRecord) || can(Perm.usageParametersEdit));
}
