/// Запись очереди, несущая показание наработки: отдельная наработка
/// (`UsageUpdate`) или осмотр с наработкой внутри (`Scan.usageUpdates`).
typedef UsageOrderEntry = ({String? equipmentUuid, String? createdAt});

/// Есть ли по тому же оборудованию **более раннее** неотправленное
/// показание — тогда [entry] отправлять рано.
///
/// Показания уходят двумя очередями, и разбираются они независимо, в
/// порядке ключей бокса, а не времени. Без этого правила более старое
/// показание могло уехать позже нового и откатить счётчик: сервер с
/// запретом уменьшения отказал бы, без запрета — молча записал бы старое, и
/// следующее ТО посчиталось бы не от того значения.
///
/// [others] — всё, что ещё не принято сервером, кроме самой [entry] и
/// отклонённых: отклонённое больше никто не отправит сам, решение за
/// обходчиком, и держать из-за него свежие показания нельзя.
///
/// Время — ISO-8601 (время открытия карточки осмотра). Записи без времени —
/// из прошлой версии — считаются самыми ранними; две такие друг друга не
/// держат, как и раньше. Равное время — одна отправка с одной карточки,
/// друг друга не держат.
bool hasEarlierUsage(UsageOrderEntry entry, Iterable<UsageOrderEntry> others) {
  final equipment = entry.equipmentUuid;
  if (equipment == null || equipment.isEmpty) return false;
  final mine = _parse(entry.createdAt);
  for (final other in others) {
    if (other.equipmentUuid != equipment) continue;
    final theirs = _parse(other.createdAt);
    if (theirs == null) {
      if (mine != null) return true;
      continue;
    }
    if (mine != null && theirs.isBefore(mine)) return true;
  }
  return false;
}

DateTime? _parse(String? value) =>
    value == null || value.isEmpty ? null : DateTime.tryParse(value);
