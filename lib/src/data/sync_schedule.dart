/// Когда справочник нужно перечитать целиком, а не дельтой.
///
/// Вынесено из `DataProvider` отдельной функцией: правило простое, но от него
/// зависит, зарастут ли расхождения дельта-синхронизации, — а проверить его
/// внутри провайдера нельзя, там Hive и сеть.
///
/// [lastFullSyncAt] `null` — полного прохода ещё не было, значит он и нужен.
bool isFullResyncDue({
  required DateTime? lastFullSyncAt,
  required DateTime now,
  required Duration interval,
}) {
  if (lastFullSyncAt == null) return true;
  // Отметка из будущего — часы телефона перевели назад. Считаем, что пора:
  // ждать до неё можно было бы сутками.
  if (lastFullSyncAt.isAfter(now)) return true;
  return now.difference(lastFullSyncAt) >= interval;
}
