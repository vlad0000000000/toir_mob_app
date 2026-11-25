import '../../strings.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../model/repair_conflict.dart';

// Решения очереди правок ремонта, когда запрос уже вернулся (бэкенд
// `81f644c`/`d22727e`, ревью 23.11).
//
// Пока шёл запрос, обходчик мог поменять правку в карточке или добавить
// снимки: карточка пишет в бокс ту же запись (ключ — ремонт). Поэтому итог
// запроса применяется к записи **из бокса** ([stored]), а не к отправленной
// копии ([sent]), и только если её поля формы те же. Иначе удаление или
// пометка стёрли бы новую правку и файлы новых снимков.
//
// Функции чистые: очередь (`data_provider_outbox.dart`) читает и пишет бокс
// сама — так решения проверяются тестами без сети.

/// Запись в боксе [stored] — та же правка, что ушла в запросе [sent]: поля
/// формы не меняли. `false` — записи нет или обходчик её переписал.
bool isSameQueuedEdit(PendingRepairUpdate? stored, PendingRepairUpdate sent) =>
    stored != null &&
    stored.sameFormAs(
      comment: sent.comment,
      consumptions: sent.consumptions,
      submitForReview: sent.submitForReview,
    );

/// Что сделать с записью, когда поля правки [sent] уже на сервере (успех или
/// «уже дошло»). `null` — записи нет, делать нечего. `delete` — запись снять.
/// Иначе `keep` — чем её заменить.
typedef SentUpdateOutcome = ({bool delete, PendingRepairUpdate? keep});

SentUpdateOutcome? afterSentUpdate(
  PendingRepairUpdate? stored,
  PendingRepairUpdate sent,
) {
  if (stored == null) return null;
  final sameForm = isSameQueuedEdit(stored, sent);
  if (sameForm && !stored.hasPhotoWork) return (delete: true, keep: null);
  // Ушла отправка на проверку, а снимки добавили за время запроса: ремонт
  // «На рассмотрении», сервер их не примет — повтор бессмыслен, решает
  // обходчик (скопировать или удалить).
  if (sameForm && sent.submitForReview) {
    return (
      delete: false,
      keep: stored.withoutBase().markRejected(
            reason: RepairCardStrings.photosAfterSubmit,
            serverStatus: RepairStatuses.underReview,
            conflictKind: RepairConflictKind.photosRejected.code,
          ),
    );
  }
  // Новая правка или новые снимки уйдут следующим проходом. Прежняя основа
  // `If-Match` устарела нашей же отправкой.
  return (delete: false, keep: stored.withoutBase());
}

/// Запись [stored] после загрузки снимков правки [sent]: из неё вычеркнуто
/// то, что ушло на сервер, — снимки из [sent.photoPaths], которых нет в
/// [photosLeft], и удаления, которых нет в [deletesLeft]. Добавленное в
/// карточке за время загрузки остаётся.
PendingRepairUpdate afterPhotoUpload({
  required PendingRepairUpdate stored,
  required PendingRepairUpdate sent,
  required List<String> photosLeft,
  required List<String> deletesLeft,
}) {
  final uploaded = {
    for (final path in sent.photoPaths)
      if (!photosLeft.contains(path)) path,
  };
  final removed = {
    for (final uuid in sent.deletedPhotoUuids)
      if (!deletesLeft.contains(uuid)) uuid,
  };
  return stored.copyWith(
    photoPaths: [
      for (final path in stored.photoPaths)
        if (!uploaded.contains(path)) path,
    ],
    deletedPhotoUuids: [
      for (final uuid in stored.deletedPhotoUuids)
        if (!removed.contains(uuid)) uuid,
    ],
  );
}
