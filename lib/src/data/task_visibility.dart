import '../model/access_profile.dart';
import '../model/task_access.dart';

/// Правила, по которым задача попадает в списки обходчика, — по ролям
/// доступа.
///
/// Чистые функции без Hive и `GlobalState`: так их проверяет тест, а
/// `DataProvider` только подставляет текущего пользователя и профиль.
///
/// Видимость решает сервер, приложение её не расширяет — только сужает до
/// того, что обходчик действительно может выполнить. Для основной выборки
/// задач сервер уже отобрал «мои» (`only_my_roles`), повторный отбор здесь
/// безвреден; а задачи ППР приложение догружает поштучно, мимо этого
/// фильтра, и для них отбор здесь — единственный.

/// Экземпляр входит в «мои» — зеркало серверного `only_my_roles`
/// (`my_directions_clause` в `backend/services/inspection_access.py`): общая
/// задача, взятая мной или задача моего направления.
///
/// [profile] `null` — профиль доступа ещё неизвестен (вошли прошлой версией
/// и с тех пор без сети): направление сверить не с чем, верим серверу.
bool isTaskInMyScope(
  TaskAccess access, {
  required String userUuid,
  required AccessProfile? profile,
}) {
  if (profile == null) return true;
  if (access.isShared) return true;
  if (access.inspectorUuid == userUuid) return true;
  final myDirection = profile.direction?.uuid;
  if (myDirection == null) return false;
  return access.directions.any((ref) => ref.uuid == myDirection);
}

/// Плановую задачу можно выполнить: она в моей области и сервер разрешает
/// её выполнение.
///
/// `execute` сервер не даёт, если экземпляр уже взял другой исполнитель или
/// у роли нет права выполнять задачи. Показывать такую задачу незачем:
/// закрытие получило бы отказ «уже выполнено другим исполнителем», и
/// обходчик потерял бы сделанную работу.
bool isScheduledTaskAvailable(
  TaskAccess access, {
  required String userUuid,
  required AccessProfile? profile,
}) {
  return access.can(TaskAccess.actionExecute) &&
      isTaskInMyScope(access, userUuid: userUuid, profile: profile);
}

/// Назначенную (`open`) задачу ответственный может довести до конца: у
/// экземпляра задачи — `execute`, у прямого осмотра — `edit`.
bool isOpenTaskActionable(TaskAccess access) =>
    access.can(TaskAccess.actionExecute) || access.can(TaskAccess.actionEdit);

/// Открытая задача видна обходчику, если назначена ему — любым из двух
/// способов — и выполнима.
///
/// Назначений два: **ответственный** ([responsibleUuid]) — открытые заявки;
/// **исполнитель** (`TaskAccess.inspectorUuid`) — экземпляр задачи, который
/// администратор переназначил (`reassign` пишет исполнителя и переводит
/// задачу в `open`, ответственного не трогает). Учитывать только первое
/// значило терять переназначенные задачи.
///
/// Исполнитель считается назначением **только у экземпляра задачи**. У
/// прямого осмотра в `inspector` сервер пишет автора: заявка, которую
/// обходчик сам завёл и которую назначили другому, иначе попала бы в его
/// рабочие задачи.
///
/// [access] `null` — запись прошлой версии или сервер без ролей: исполнителя
/// не знаем, решает ответственный, как раньше.
bool isOpenTaskAvailable({
  required String? responsibleUuid,
  required TaskAccess? access,
  required String userUuid,
}) {
  final executor =
      access != null && access.isTaskInstance ? access.inspectorUuid : null;
  final assignedToMe = responsibleUuid == userUuid || executor == userUuid;
  if (!assignedToMe) return false;
  return access == null || isOpenTaskActionable(access);
}

/// Задача сделана текущим пользователем — по исполнителю экземпляра.
/// `null` — исполнитель неизвестен (запись прошлой версии), решать по
/// старому правилу.
bool? isTaskDoneByMe(TaskAccess? access, String userUuid) {
  final inspector = access?.inspectorUuid;
  if (inspector == null) return null;
  return inspector == userUuid;
}

/// Подпись к задаче в списке, если она не очевидна: общая задача или чужое
/// направление (видно при праве «Все направления» или после смены
/// направления у взятой задачи). Своё направление не подписываем — это
/// каждая вторая строка, шум.
///
/// `null` — подписывать нечего.
String? taskScopeLabel(
  TaskAccess? access, {
  required AccessProfile? profile,
  required String sharedLabel,
}) {
  if (access == null || access.directionScope == null) return null;
  if (access.isShared) return sharedLabel;
  final myDirection = profile?.direction?.uuid;
  if (access.directions.any((ref) => ref.uuid == myDirection)) return null;
  final names = [
    for (final ref in access.directions)
      if (ref.name.trim().isNotEmpty) ref.name.trim(),
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// Задача, возвращённая на доработку, видна её исполнителю — тому, кто
/// записал результат, — пока сервер разрешает её выполнять.
///
/// Статус у неё `closed`: проверяющий возвращает уже сданный результат, и по
/// статусу её не отличить от выполненной. Признак возврата —
/// [TaskAccess.returned].
bool isReturnedTaskAvailable(TaskAccess access, {required String userUuid}) =>
    access.returned &&
    access.inspectorUuid == userUuid &&
    access.can(TaskAccess.actionExecute);

/// Значение отметки «закрыто на этом телефоне» — версия результата, на
/// которую ответил осмотр.
String closedMarkValue(int revision) => 'rev:$revision';

/// Версия из отметки. Отметки прошлой версии (`'1'`) версии не знают:
/// `-1` — старше любой, и возвращённую задачу такая отметка не прячет.
int parseClosedMark(String? value) {
  if (value == null || !value.startsWith('rev:')) return -1;
  return int.tryParse(value.substring(4)) ?? -1;
}

/// Отметка закрытия ещё действует: задача не возвращалась с тех пор, как её
/// закрыли на этом телефоне.
///
/// Вернули на доработку — версия результата у сервера выросла
/// ([TaskAccess.reviewRevision]), и отметка с прежней версией задачу больше
/// не прячет. Иначе обходчик, сдавший задачу на этом телефоне, так и не
/// увидел бы её возврата: отметка снимается, только когда сервер перестаёт
/// отдавать задачу, а возвращённую он отдаёт снова.
bool isClosedMarkCurrent({required int markedRevision, TaskAccess? access}) {
  if (access == null || !access.returned) return true;
  return markedRevision >= access.reviewRevision;
}
