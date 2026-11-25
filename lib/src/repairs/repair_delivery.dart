import '../model/repair.dart';

/// Отправка на проверку уже дошла: обходчик нажал «Отправить на проверку»,
/// а на сервере ремонт [server] — «На рассмотрении», и в нём ровно его
/// комментарий и расход.
///
/// Так бывает, когда ответ на `PATCH` потерялся (слабая связь): сервер
/// принял комментарий, расход и перевод одним запросом, а повтор получил 409
/// `repair_not_open` (сервер прошлой версии — 403). Раньше такая запись
/// помечалась отклонённой, пряталась из списка (ремонт «На рассмотрении» в
/// обычный фильтр не входит) и навсегда давала «Не все ремонты отправлены».
/// Теперь она снимается как отправленная — тот же приём, что у осмотров с
/// «Закрытый осмотр нельзя изменить».
///
/// Содержимое сверяется, а не только статус: на рассмотрение ремонт мог
/// перевести и кто-то другой, тогда правка обходчика на сервер не попала, и
/// снимать её молча нельзя. [comment] `null` — комментарий в запросе не
/// уходил (черновик, у которого он не менялся после создания), сверять нечего.
/// [consumptions] `null` — расход в запросе не уходил (нет права на ЗИП), тоже
/// не сверяется. Позиции с нулевым количеством на сервер не уходят — не
/// сверяются.
bool isSubmissionDelivered({
  required bool submitForReview,
  required Repair? server,
  required String? comment,
  required List<RepairConsumption>? consumptions,
}) {
  if (!submitForReview || server == null) return false;
  if (server.status != 'under_review') return false;
  if (comment != null && comment.trim() != (server.comment ?? '').trim()) {
    return false;
  }
  if (consumptions == null) return true;
  Map<String, double> quantities(Iterable<RepairConsumption> items) => {
        for (final item in items)
          if (item.quantity > 0) item.sparePartUuid: item.quantity,
      };
  final sent = quantities(consumptions);
  final stored = quantities(server.actualConsumptions);
  if (sent.length != stored.length) return false;
  for (final entry in sent.entries) {
    if (stored[entry.key] != entry.value) return false;
  }
  return true;
}
