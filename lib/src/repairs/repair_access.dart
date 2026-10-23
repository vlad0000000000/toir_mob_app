import '../model/repair.dart';

/// Почему над ремонтом нельзя работать — для плашки карточки.
enum RepairWorkBlock {
  /// Роли не хватает права или ремонт вне её области.
  noAccess,

  /// Ремонт назначен на другого сотрудника.
  notMine,
}

/// Можно ли работать над ремонтом (комментарий, расход, фото) и если нет —
/// почему. `null` — можно.
///
/// Решает сервер — подсказкой `allowed_actions` ([Repair.allowedActions]):
/// он считает её теми же правилами, что проверяет при сохранении (право,
/// исполнитель, статус, направление, подразделение). Её нет — сервер прошлой
/// версии, кэш прошлой версии, черновик — тогда по-старому: право роли
/// [roleCanWork] (`repair.execute`) и свой ли ремонт.
///
/// Причину различаем и при подсказке сервера: «назначен на другого» точнее
/// общего «нет доступа», когда исполнитель известен и это не обходчик.
RepairWorkBlock? repairWorkBlock(
  Repair repair, {
  required bool roleCanWork,
  required String myUuid,
}) {
  final owner = repair.responsibleUserUuid ?? '';
  final notMine = myUuid.isNotEmpty && owner.isNotEmpty && owner != myUuid;
  final canExecute = repair.allows(RepairActions.execute);
  if (canExecute != null) {
    if (canExecute) return null;
    return notMine ? RepairWorkBlock.notMine : RepairWorkBlock.noAccess;
  }
  if (!roleCanWork) return RepairWorkBlock.noAccess;
  if (notMine) return RepairWorkBlock.notMine;
  return null;
}

/// Можно ли взять свободный ремонт в работу: по подсказке сервера, а без
/// неё — по праву роли [roleCanWork].
///
/// Сервер отказывает и по области: ремонт чужого направления или
/// подразделения роль может видеть («Ремонты всех исполнителей»), но взять
/// — нет. Повторять эти правила на телефоне не нужно — их знает подсказка.
bool canClaimRepair(Repair repair, {required bool roleCanWork}) =>
    repair.allows(RepairActions.claim) ?? roleCanWork;

/// Можно ли отправить ремонт на рассмотрение. Без подсказки сервера —
/// можно: это часть работы над своим ремонтом ([repairWorkBlock]).
bool canSubmitRepair(Repair repair) =>
    repair.allows(RepairActions.submitReview) ?? true;
