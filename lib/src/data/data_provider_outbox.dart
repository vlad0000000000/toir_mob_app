part of 'data_provider.dart';

/// Журнал очередей отправки.
///
/// Сообщения ниже пишутся только из веток `catch`, зато именно они нужны при
/// разборе жалобы «расход не списался» или «осмотр пропал». Уровень не ниже
/// `warning` намеренно: в релизной сборке `Logger.root.level` поднят до
/// `Level.WARNING` (`main.dart`), и всё, что тише, туда не доедет.
final _outboxLog = Logger('DataProviderOutbox');

/// Перевод отказа «No access to this repair» — по нему очередь узнаёт, что
/// ремонт передали другому сотруднику. Сравниваем с переводом, а не с
/// английским оригиналом, чтобы источник строки был ровно один.
const String _noAccessMessage = repairNoAccessMessage;

/// Перевод «Repair photo not found». Снимка на сервере уже нет — для
/// отложенного удаления это успех, а не отказ.
const String _photoNotFoundMessage = 'Фотография не найдена';

/// Итог уточнения статуса после 403 по правке — см. `_checkDenied`.
enum _DeniedCheck { wait, noRights, stateChanged, unknown }

/// Офлайн-очереди отправки: осмотры (scans), наработки (usage),
/// периодические задачи, черновики ремонтов. Перекладывание pending ↔ box +
/// ретраи.
extension DataProviderOutbox on DataProvider {
  /// Правка [update] ещё в очереди — её не удалили с экрана, пока шёл запрос.
  bool _isQueued(PendingRepairUpdate update) =>
      pendingRepairUpdateBox.containsKey(updateKeyOf(update));

  /// Отправляет черновики ремонтов, накопленные без связи.
  ///
  /// Схема проще, чем у осмотров: отдельный pending-бокс с возвратом через
  /// 120 секунд здесь не нужен, потому что защита от дубля живёт на сервере —
  /// каждый черновик уходит со своим `Idempotency-Key`, и повтор возвращает
  /// уже созданный ремонт вместо второго. Поэтому черновик просто лежит в
  /// очереди, пока не будет принят или явно отклонён.
  ///
  /// Возвращает число отправленных за проход.
  Future<int> syncPendingRepairs() async {
    // Тот же замок, что у осмотров: пятисекундный цикл и кнопка
    // «Синхронизировать данные» могут войти сюда одновременно, и тогда один
    // черновик ушёл бы двумя запросами. Сервер их склеил бы по ключу, но
    // второй ответ всё равно попытался бы удалить уже удалённую запись.
    if (_isSyncingPendingRepairs) return 0;
    _isSyncingPendingRepairs = true;
    try {
      return await _syncPendingRepairsImpl();
    } finally {
      _isSyncingPendingRepairs = false;
      // Проход правит черновики прямо в боксе: записывает `serverUuid`,
      // причину отказа, оставшиеся снимки. Число ремонтов при этом не
      // меняется, поэтому счётчик молчит, — а список ремонтов обязан показать
      // и «отправляется», и «не отправлено». Двигаем ревизию в `finally`:
      // проход мог оборваться на середине, но то, что он успел записать,
      // экран всё равно должен увидеть.
      repairsRevision.value++;
    }
  }

  Future<int> _syncPendingRepairsImpl() async {
    var sent = 0;
    for (final draft in pendingRepairBox.values.toList()) {
      // Черновик другого обходчика с его токеном не уходит: ждёт, пока тот
      // снова войдёт на этом телефоне (п. 1.5 отчёта).
      if (!isMine(draft)) continue;
      // Отклонённые не долбим на каждом цикле: причина никуда не денется
      // сама («Для этого оборудования уже есть ремонт»), а обходчик увидит
      // её в списке и решит — повторить вручную или удалить черновик.
      if (draft.isRejected) continue;
      // Копится по ходу конвейера: после создания ремонта здесь уже лежит
      // serverUuid. Объявлен снаружи try, потому что именно этот объект должен
      // попасть в отказ — иначе черновик «забудет» созданный ремонт, и по
      // нему соврут сразу трое: текст подтверждения удаления, счётчик активных
      // ремонтов и удержание свежего ремонта в кэше при фоновой синхронизации.
      var current = draft;
      // Сессия — до запросов: ответ может прийти уже после нового входа.
      final session = _accessSession;
      // Поколение кэша — тоже до запросов. Конвейер — несколько запросов
      // подряд, а токен в `API` общий: выйди A посреди него и войди B,
      // следующий шаг ушёл бы с токеном B, а ответ с ремонтом A лёг бы в кэш
      // B. Поэтому после каждого сетевого шага сверяемся и при смене аккаунта
      // бросаем запись — она A, и дошлёт её A, когда войдёт.
      //
      // Сверяем и номер сессии: обычный «Выйти» поколение не трогает (оно
      // меняется только при входе другого), а токена после него нет вовсе.
      // Вышел и вошёл тот же A — проход бросит запись, следующий продолжит.
      final generation = cacheGeneration;
      bool switched() =>
          isStaleCacheGeneration(generation) || session != _accessSession;
      try {
        // Ремонт создаём только если его ещё нет: на повторном проходе
        // (например, когда доехал ремонт, но не доехали снимки) черновик уже
        // помнит серверный uuid.
        if (current.serverUuid == null) {
          // Тело создания фиксируем при первой отправке и пишем **до**
          // запроса: сервер сверяет ключ с телом, и повтор после потерянного
          // ответа обязан совпасть, даже если обходчик с тех пор поправил
          // комментарий или право на ЗИП пропало. Норма — только с правом:
          // без него сервер отклоняет создание с нормой целиком.
          if (!current.isCreateFrozen) {
            current = current.freezeCreate(
              normUuid:
                  sectionAccess.spareParts ? current.consumptionNormUuid : null,
            );
            if (!pendingRepairBox.containsKey(current.localId)) continue;
            await pendingRepairBox.put(current.localId, current);
          }
          // Фиксация тела — ожидание: сменись за него аккаунт, ремонт A
          // создался бы от имени B. Тело уже записано — повтор A совпадёт.
          if (switched()) continue;
          // Номер — до запроса: о ремонте прав ответ запроса, начатого позже
          // ([DataProvider.beginRepairRequest]).
          final createSeq = beginRepairRequest();
          final repair = await api.createRepair(
            equipmentUuid: current.equipmentUuid,
            consumptionNormUuid: current.createNormUuid,
            startedAt: current.startedAt,
            comment: current.createComment,
            idempotencyKey: current.localId,
            // Флаг — тот, с которым черновик создан, а не «сейчас ли дата в
            // будущем»: он часть тела под ключом. Если время уже прошло,
            // сервер сам откроет ремонт сразу.
            schedule: current.schedule,
          );
          await upsertRepair(
            repair,
            generation: generation,
            requestSeq: createSeq,
          );
          // Записываем uuid до загрузки снимков: если приложение убьют
          // посреди неё, следующий проход не создаст второй ремонт. И при
          // смене аккаунта тоже: черновик — запись A в общей очереди, и без
          // uuid A, войдя снова, создал бы второй ремонт.
          current = current.copyWith(serverUuid: repair.uuid);
          // Черновик мог быть удалён с экрана, пока запрос был в полёте.
          // Возвращать его в бокс нельзя: обходчик уже решил, что не хочет
          // его видеть, а ремонт на сервере всё равно создан и придёт со
          // следующей синхронизацией.
          if (!pendingRepairBox.containsKey(current.localId)) continue;
          await pendingRepairBox.put(current.localId, current);
          if (switched()) continue;
        }

        // Ремонт создан, и отправлять больше нечего — черновик выполнен.
        // Раньше ожидания начала ниже: иначе запланированный без снимков и
        // расхода висел бы с пометкой «Не отправлено» до самой даты начала,
        // хотя сервер его уже принял.
        if (!current.hasWorkAfterCreate) {
          await deletePendingRepair(current.localId);
          sent++;
          continue;
        }

        // Ремонт создан запланированным, а время ещё не пришло: снимки и
        // финальную правку сервер исполнителю не примет (409
        // `repair_not_open`, у старого сервера — 403 «нет прав»). Ждём начала:
        // тогда сервер откроет ремонт, и конвейер дойдёт до конца.
        //
        // Решает ремонт в кэше, а не дата черновика: администратор мог
        // открыть ремонт досрочно или перенести его, и синхронизация уже это
        // принесла. Запланирован, но его время прошло — пробуем: сервер,
        // скорее всего, уже открыл; нет — 409 «запланирован», и ждём дальше.
        // Кэш о ремонте не знает — по дате черновика.
        final now = DateTime.now();
        final created = repairBox.get(current.serverUuid!);
        final waitsForStart = created != null
            ? created.isScheduled && created.startedAt.isAfter(now)
            : current.isScheduledAt(now);
        if (waitsForStart) continue;
        final left = await _uploadPhotos(
          current.serverUuid!,
          current.photoPaths,
          stop: switched,
        );
        if (left.isNotEmpty) {
          // Часть снимков не ушла — черновик остаётся в очереди ровно с
          // ними. Отправленные уже вычеркнуты и повторно не полетят.
          if (!pendingRepairBox.containsKey(current.localId)) continue;
          await pendingRepairBox.put(
            current.localId,
            current.copyWith(photoPaths: left),
          );
          continue;
        }
        // Последний шаг конвейера: расход, комментарий и — если обходчик уже
        // нажал «Отправить» — перевод в «На рассмотрении». Только теперь, по
        // порядку из п. 4.5.4: создание → фото → статус.
        //
        // И только если есть что менять. Комментарий уже ушёл в создании;
        // правка ремонта требует права работы над ним, которого у роли,
        // создающей ремонты, может и не быть, — запрос «ни о чём» получил
        // бы 403, и черновик застрял бы с уже созданным ремонтом.
        // У черновика прошлой версии исходный комментарий неизвестен — он
        // уходит всегда, в том числе очищенный
        // ([PendingRepair.commentChangedSinceCreate]).
        final commentChanged = current.commentChangedSinceCreate;
        if (!commentChanged &&
            current.consumptions.isEmpty &&
            !current.submitForReview) {
          await deletePendingRepair(current.localId);
          sent++;
          continue;
        }
        // Расход есть, а права на ЗИП уже нет — урезанной не отправляем,
        // иначе расход пропал бы вместе с черновиком. Держим с причиной
        // «нет прав» (см. [SectionAccess.consumptionsBlocked]).
        if (sectionAccess.consumptionsBlocked(current.consumptions)) {
          if (!pendingRepairBox.containsKey(current.localId)) continue;
          await pendingRepairBox.put(
            current.localId,
            current.markRejected(reason: repairNoRightsMessage),
          );
          continue;
        }
        // Последний шаг — с токеном того, чей черновик.
        if (switched()) continue;
        final finishSeq = beginRepairRequest();
        final finished = await api.updateRepair(
          current.serverUuid!,
          comment: commentChanged ? current.comment : null,
          consumptions: sectionAccess.consumptionsToSend(current.consumptions),
          submitForReview: current.submitForReview,
        );
        await upsertRepair(
          finished,
          generation: generation,
          requestSeq: finishSeq,
        );
        await deletePendingRepair(current.localId);
        sent++;
      } catch (e) {
        // Аккаунт сменился, пока шёл запрос: отказ мог прийти и на токен B —
        // черновик A не помечаем, он уйдёт, когда A войдёт.
        if (switched()) continue;
        if (e is AuthExpiredException) {
          // Токен протух. Черновик не виноват — оставляем как есть и поднимаем
          // пометку; после повторного входа отправка продолжится сама.
          // Отказ на запрос прошлой сессии пометку не поднимает.
          _authExpiredFlag.raise(requestSession: session);
          continue;
        }
        if (isRetryableRepairError(e)) {
          // Связи нет или сервер ещё дожёвывает наш прошлый запрос с тем же
          // ключом — оставляем как есть, даже попытку не засчитываем.
          continue;
        }
        // Созданный ремонт ещё запланирован (часы телефона отстают от
        // сервера) — ждём начала, как и выше. На рассмотрении или закрыт —
        // обычный отказ ниже, с причиной по статусу.
        if (e is RepairNotOpenException && e.isScheduled) continue;
        // Сервер ответил и отказал. Запоминаем причину по-русски и больше не
        // повторяем автоматически.
        //
        // Занявший ремонт доискиваем только тогда, когда отказ действительно
        // про занятое оборудование: поиск при промахе перекачивает весь
        // список ремонтов, и делать это на каждом отказе — включая сбой
        // сервера и ошибку валидации — значило гонять сеть впустую ради
        // значения, которое всё равно окажется пустым.
        final reason = repairErrorMessage(e);
        var blocking = isEquipmentBusyMessage(reason)
            ? await _findBlockingRepair(current.equipmentUuid)
            : null;
        // Поиск — ещё один запрос и чтение кэша: сменись за него аккаунт, он
        // ушёл бы с токеном B и нашёл бы ремонт по кэшу B. Сама причина верна
        // (пришла на запрос A) — ставим её без ссылки на ремонт: найдёт
        // следующий разбор под A.
        if (switched()) blocking = null;
        // Удалён с экрана, пока летел запрос или шёл поиск, — пометку ставить
        // некуда.
        if (!pendingRepairBox.containsKey(current.localId)) continue;
        await pendingRepairBox.put(
          current.localId,
          current.markRejected(reason: reason, conflictRepairUuid: blocking),
        );
        _outboxLog.severe(
            'черновик ремонта ${current.localId} отклонён сервером: $e');
      }
    }
    return sent;
  }

  /// Грузит снимки по одному и возвращает те, что отправить не удалось.
  ///
  /// По одному, а не пачкой, — намеренно: сервер принимает список файлов
  /// одним запросом, но если он оборвётся на середине, узнать, какие снимки
  /// уже сохранились, будет неоткуда, и повтор их продублирует. Один файл —
  /// один запрос: успех означает ровно один принятый снимок, и путь тут же
  /// вычёркивается, а файл удаляется.
  ///
  /// Первая же неудача прекращает проход: связь пропала — остальные всё
  /// равно не уйдут, а долбить сервер незачем.
  ///
  /// Дополнительно каждый снимок уходит со своим `Idempotency-Key`. Один файл
  /// на запрос защищает от дубля только тогда, когда ответ дошёл; если же
  /// связь оборвалась *после* сохранения на сервере, путь остаётся в очереди
  /// и повтор без ключа положил бы второй такой же снимок. Ключ считается от
  /// содержимого кадра (`RepairPhotoFiles.idempotencyKey`), поэтому он один и
  /// тот же при любом числе повторов — и совпадает с тем, под которым тот же
  /// кадр уже пытались отправить из карточки.
  ///
  /// [stop] — проверка конвейера «сменился аккаунт или вышли» (`switched()`:
  /// поколение кэша и номер сессии): сработала — следующий снимок не шлём
  /// (ушёл бы с чужим токеном или без него), он остаётся в оставшихся.
  Future<List<String>> _uploadPhotos(
    String repairUuid,
    List<String> paths, {
    required bool Function() stop,
  }) async {
    final left = <String>[];
    var failed = false;
    for (final path in paths) {
      if (failed || stop()) {
        left.add(path);
        continue;
      }
      final bytes = await RepairPhotoFiles.read(path);
      if (bytes == null) {
        // Файла нет — вычёркиваем: ждать его бессмысленно.
        continue;
      }
      // Ещё раз — после чтения: оно асинхронное, и сменись сессия, пока
      // читался файл, снимок A ушёл бы с токеном B. Путь остаётся в
      // оставшихся, дальше не шлём — как при обрыве связи.
      if (stop()) {
        failed = true;
        left.add(path);
        continue;
      }
      final session = _accessSession;
      try {
        await api.uploadRepairPhotos(
          repairUuid,
          [base64Encode(bytes)],
          idempotencyKey: RepairPhotoFiles.idempotencyKey(repairUuid, bytes),
        );
        await RepairPhotoFiles.delete(path);
      } catch (e) {
        // Ремонт ушёл из «Открыт» — это не сбой связи, повтор на каждом
        // проходе ничего не дал бы: решает вызывающий (ждать начала или
        // пометить правку). Принятые снимки уже удалены с телефона, их путь
        // следующая попытка просто пропустит.
        if (e is RepairNotOpenException) rethrow;
        if (e is AuthExpiredException) {
          _authExpiredFlag.raise(requestSession: session);
        }
        failed = true;
        left.add(path);
        _outboxLog.warning(
            'снимок $path не загрузился в ремонт $repairUuid: $e');
      }
    }
    return left;
  }

  /// Удаляет снимки, убранные обходчиком без связи. Возвращает те, что
  /// удалить не удалось.
  ///
  /// Отсутствие снимка на сервере (его уже удалили с другого устройства) —
  /// это успех, а не ошибка: цель достигнута.
  Future<List<String>> _deletePhotos(
    String repairUuid,
    List<String> photoUuids, {
    required bool Function() stop,
  }) async {
    final left = <String>[];
    var failed = false;
    for (final uuid in photoUuids) {
      // Сменился аккаунт или вышли — как у загрузки: дальше не шлём.
      if (failed || stop()) {
        left.add(uuid);
        continue;
      }
      final session = _accessSession;
      try {
        await api.deleteRepairPhoto(repairUuid, uuid);
      } catch (e) {
        if (repairErrorMessage(e) == _photoNotFoundMessage) continue;
        // Ремонт ушёл из «Открыт» — не сбой связи: решает вызывающий (ждать
        // начала или пометить правку). Удалённое уже вычеркнуто им не будет:
        // повтор удаления безвреден (404 — успех).
        if (e is RepairNotOpenException) rethrow;
        if (e is AuthExpiredException) {
          _authExpiredFlag.raise(requestSession: session);
        }
        failed = true;
        left.add(uuid);
        _outboxLog.warning('снимок $uuid не удалён из ремонта $repairUuid: $e');
      }
    }
    return left;
  }

  /// Ищет ремонт, занявший оборудование: сервер отвечает «Equipment is already
  /// in repair», но какой именно ремонт мешает — не говорит.
  ///
  /// Сначала перечитываем список: ремонт мог появиться только что и в
  /// офлайн-кэше его ещё нет. Если и после этого не нашёлся — значит он
  /// назначен на другого сотрудника, обходчику такие не отдают. Экран
  /// разрешения конфликта это переживёт: перенос всё равно был бы недоступен.
  /// Пометка «нет прав» у правки устарела: ремонт в кэше открыт, и сервер
  /// разрешает по нему работу (`execute` в `allowed_actions`).
  ///
  /// Так снимается отказ, полученный, пока ремонт был запланирован (работа
  /// по нему обходчику не положена — 403), — сам по себе он ушёл бы только
  /// со сменой доступа ([retryNoRightsRejections]), а её может и не быть.
  /// Настоящий отказ не трогаем, иначе пометка снималась и ставилась бы
  /// заново на каждом проходе — PATCH и GET впустую и мигающая карточка:
  /// * расход есть, а права на ЗИП нет;
  /// * сервер на отказе подтвердил, что ремонт открыт
  ///   ([RepairConflictKind.noRights]): `execute` бэкенд даёт без проверки
  ///   подразделения, а правку подразделение не пускает, и кэш после снятия
  ///   права ещё помнит `execute`.
  bool _noRightsRejectionIsStale(PendingRepairUpdate update) {
    if (!isRepairNoRightsMessage(update.lastError)) return false;
    if (update.kind == RepairConflictKind.noRights) return false;
    if (sectionAccess.consumptionsBlocked(update.consumptions)) return false;
    final repair = repairBox.get(update.repairUuid);
    return repair != null &&
        repair.isOpen &&
        repair.allows(RepairActions.execute) == true;
  }

  /// Что делать с правкой по ремонту [uuid] после 403 «нет прав». Кэш мог не
  /// знать о переносе ремонта на будущее — перечитывает ремонт с сервера и
  /// кладёт в кэш.
  ///
  /// * [_DeniedCheck.wait] — ремонт запланирован (правка ждёт его начала)
  ///   или, пока шёл запрос, сменился аккаунт: ответ отброшен, а правка не
  ///   нового обходчика — пометку в его очередь писать нельзя;
  /// * [_DeniedCheck.noRights] — ремонт открыт и он мой: отказ по правам
  ///   настоящий;
  /// * [_DeniedCheck.stateChanged] — дело не в правах: ремонт на
  ///   рассмотрении, закрыт или передан другому. Бэкенд и на это отвечает
  ///   403 `permission_denied` («Исполнитель может изменять только открытый
  ///   ремонт»), а «нет прав» назвало бы не ту причину;
  /// * [_DeniedCheck.unknown] — статус не уточнить: обычная пометка «нет
  ///   прав», её очередь снимет сама, когда ремонт в кэше откроется.
  ///
  /// Второе значение — свежий ремонт, если его удалось прочитать.
  Future<(_DeniedCheck, Repair?)> _checkDenied(String uuid) async {
    final generation = cacheGeneration;
    final readSeq = beginRepairRequest();
    try {
      final fresh = await api.getRepair(uuid);
      await upsertRepair(fresh, generation: generation, requestSeq: readSeq);
      if (isStaleCacheGeneration(generation) || fresh.isScheduled) {
        return (_DeniedCheck.wait, fresh);
      }
      final me = GlobalState.authUser?.uuid;
      final mine =
          fresh.isOpen && me != null && fresh.responsibleUserUuid == me;
      return (
        mine ? _DeniedCheck.noRights : _DeniedCheck.stateChanged,
        fresh,
      );
    } catch (_) {
      return (
        isStaleCacheGeneration(generation)
            ? _DeniedCheck.wait
            : _DeniedCheck.unknown,
        null,
      );
    }
  }

  /// Вид конфликта по свежему ремонту [fresh]: закрыт, передан другому или
  /// прочее.
  RepairConflictKind _conflictKindOf(Repair fresh) {
    if (fresh.isClosed) return RepairConflictKind.repairClosed;
    // Ремонт жив, но ответственный уже не мы — забрал другой обходчик или
    // переназначил администратор.
    final me = GlobalState.authUser?.uuid;
    final owner = fresh.responsibleUserUuid;
    if (me != null && owner != null && owner.isNotEmpty && owner != me) {
      return RepairConflictKind.repairReassigned;
    }
    return RepairConflictKind.other;
  }

  Future<String?> _findBlockingRepair(String equipmentUuid) async {
    String? search() {
      for (final repair in _repairs) {
        if (repair.equipmentUuid == equipmentUuid && repair.isActive) {
          return repair.uuid;
        }
      }
      return null;
    }

    final known = search();
    if (known != null) return known;
    await syncMyRepairs();
    return search();
  }

  /// Снимает пометку «нет прав» со всех отклонённых записей очередей —
  /// осмотров, наработки, черновиков и правок ремонтов, — а у осмотров ещё и
  /// «оборудование не найдено», у заявок «Проблема» — любой отказ
  /// ([retryRejectedProblemReports]). Возвращает, сколько записей вернулось
  /// в отправку.
  ///
  /// Зовётся, когда у обходчика поменялся доступ (другая версия профиля):
  /// администратор мог вернуть право, и записи должны уйти сами, без похода
  /// обходчика по экранам разбора. Если права так и нет, сервер откажет тем
  /// же — запись снова встанет с пометкой и будет ждать следующей смены
  /// доступа. Остальные отказы (нехватка ЗИП, «уже выполнил другой»,
  /// занятое оборудование) не трогаем: от смены доступа они не исчезают.
  Future<int> retryNoRightsRejections() async {
    var cleared = 0;
    // Сменился доступ вошедшего обходчика — пометки снимаем только с его
    // записей: у чужих свой доступ, и отправлять их всё равно не нам.
    for (final entry in scanBox.toMap().entries) {
      final scan = entry.value;
      if (!isMine(scan)) continue;
      // «Оборудование не найдено» — тоже про доступ (на сервере до `06b145f`
      // — чужое подразделение без флага «Осмотр без QR»). Флаг, роль и
      // выкладка `06b145f` меняют версию доступа.
      if (!isNoRightsReason(scan.lastError) &&
          !isEquipmentNotFoundReason(scan.lastError)) {
        continue;
      }
      scan.lastError = null;
      scan.lastShortages = null;
      await scanBox.put(entry.key, scan);
      cleared++;
    }
    for (final entry in scanUsageBox.toMap().entries) {
      final usage = entry.value;
      if (!isMine(usage)) continue;
      if (!isNoRightsReason(usage.lastError)) continue;
      usage.lastError = null;
      await scanUsageBox.put(entry.key, usage);
      cleared++;
    }
    for (final draft in pendingRepairBox.values.toList()) {
      if (!isMine(draft)) continue;
      if (!isRepairNoRightsMessage(draft.lastError)) continue;
      await pendingRepairBox.put(draft.localId, draft.clearRejection());
      cleared++;
    }
    for (final update in pendingRepairUpdateBox.values.toList()) {
      if (!isMine(update)) continue;
      if (!isRepairNoRightsMessage(update.lastError)) continue;
      await pendingRepairUpdateBox.put(
          updateKeyOf(update), update.clearRejection());
      cleared++;
    }
    // Отказ заявки — не «нет прав», а «оборудование не видно», но от смены
    // доступа он тоже может уйти: роль с другими подразделениями.
    cleared += await retryRejectedProblemReports();
    if (cleared > 0) {
      refreshRejectedScansCount();
      refreshRejectedUsageCount();
      invalidateScanTaskCache();
      repairsRevision.value++;
      _outboxLog.warning(
          'доступ изменился — в отправку возвращено записей: $cleared');
    }
    return cleared;
  }

  /// Снимает пометку отказа со всех отклонённых заявок «Проблема» — их
  /// возьмёт следующий проход очереди. Возвращает, сколько снято.
  ///
  /// Зовётся из «Синхронизировать данные» и при смене доступа: отказ 404
  /// уйдёт сам, когда сервер начнёт пускать к оборудованию чужого
  /// подразделения или администратор поменяет роль.
  Future<int> retryRejectedProblemReports() async {
    var cleared = 0;
    for (final entry in periodicTaskBox.toMap().entries) {
      if (!entry.value.isRejected || !isMine(entry.value)) continue;
      await periodicTaskBox.put(entry.key, entry.value.withRejection(null));
      cleared++;
    }
    if (cleared > 0) refreshRejectedProblemReportsCount();
    return cleared;
  }

  /// Повторить отправку отклонённого черновика вручную — с экрана списка.
  /// Снимает пометку об отказе, чтобы очередь снова взяла его в работу.
  Future<void> retryPendingRepair(String localId) async {
    final draft = pendingRepairBox.get(localId);
    if (draft == null) return;
    await pendingRepairBox.put(localId, draft.clearRejection());
    await syncPendingRepairs();
  }

  /// Отправляет правки существующих ремонтов, сделанные без связи.
  ///
  /// В отличие от черновиков создания, здесь нет ключа идемпотентности — он и
  /// не нужен: PATCH задаёт поля целиком, повтор с тем же телом приводит к
  /// тому же результату. Опасность другая: ремонт мог измениться на сервере,
  /// пока правка лежала в очереди. Такой отказ помечается конфликтом и ждёт
  /// решения человека, автоповторы по нему прекращаются.
  Future<int> syncPendingRepairUpdates() async {
    if (_isSyncingRepairUpdates) return 0;
    _isSyncingRepairUpdates = true;
    try {
      return await _syncPendingRepairUpdatesImpl();
    } finally {
      _isSyncingRepairUpdates = false;
      // По той же причине, что и у черновиков: пометка «не отправлено» в
      // строке списка появляется и снимается прямо здесь.
      repairsRevision.value++;
    }
  }

  Future<int> _syncPendingRepairUpdatesImpl() async {
    var sent = 0;
    for (var update in pendingRepairUpdateBox.values.toList()) {
      // Правка другого обходчика с его токеном не уходит (п. 1.5 отчёта).
      if (!isMine(update)) continue;
      // Сессия и поколение кэша — сразу за проверкой владельца, до первого
      // `await` (снятие устаревшей пометки ниже — уже ожидание): запомни мы их
      // позже, за это ожидание мог бы войти B, и проверка ниже приняла бы его
      // сессию за свою. Снимки и PATCH — несколько запросов подряд, и сменись
      // аккаунт посреди, следующий ушёл бы с токеном нового обходчика, а
      // ответ лёг бы в его кэш. Номер сессии — ради обычного выхода (см.
      // черновики).
      final session = _accessSession;
      final generation = cacheGeneration;
      bool switched() =>
          isStaleCacheGeneration(generation) || session != _accessSession;
      if (update.isRejected) {
        if (!_noRightsRejectionIsStale(update)) continue;
        // «Нет прав» устарело — сервер уже разрешает работу по ремонту.
        // Снимаем пометку и отправляем этим же проходом.
        update = update.clearRejection();
        await pendingRepairUpdateBox.put(updateKeyOf(update), update);
      }
      // Ремонт, пока правка лежала в очереди, перенесли на будущее (бэкенд
      // `7be3756`): работа по запланированному обходчику не положена, сервер
      // ответил бы 403, и правка встала бы с ложной причиной «нет прав».
      // Ждём молча: когда ремонт начнётся, синхронизация принесёт его
      // открытым, и правка уйдёт сама. Данные при этом не теряются.
      if (repairBox.get(update.repairUuid)?.isScheduled ?? false) continue;
      // Снаружи try по той же причине, что и у черновиков: в отказ должен
      // попасть объект с уже вычеркнутыми снимками и удалениями, а не
      // исходный — иначе следующая попытка проделает ту же работу заново.
      var current = update;
      try {
        // Фотографии — до PATCH, а не после. PATCH может перевести ремонт в
        // «На рассмотрении», и после этого сервер снимки уже не примет.
        if (current.hasPhotoWork) {
          final photosLeft = await _uploadPhotos(
            current.repairUuid,
            current.photoPaths,
            stop: switched,
          );
          final deletesLeft = await _deletePhotos(
            current.repairUuid,
            current.deletedPhotoUuids,
            stop: switched,
          );
          current = current.copyWith(
            photoPaths: photosLeft,
            deletedPhotoUuids: deletesLeft,
          );
          if (!_isQueued(current)) continue;
          await pendingRepairUpdateBox.put(updateKeyOf(current), current);
          if (current.hasPhotoWork) {
            // Связь пропала на фотографиях — поля отправим следующим проходом,
            // вместе с оставшимися снимками.
            continue;
          }
        }
        // Расход есть, а права на ЗИП уже нет — не отправляем урезанной:
        // запись после отправки удаляется, и расход пропал бы. Держим с
        // причиной «нет прав» (см. [SectionAccess.consumptionsBlocked]).
        if (sectionAccess.consumptionsBlocked(current.consumptions)) {
          if (!_isQueued(current)) continue;
          await pendingRepairUpdateBox.put(
            updateKeyOf(current),
            current.markRejected(
              reason: repairNoRightsMessage,
              conflictKind: RepairConflictKind.other.code,
            ),
          );
          continue;
        }
        if (switched()) continue;
        final patchSeq = beginRepairRequest();
        final repair = await api.updateRepair(
          current.repairUuid,
          comment: current.comment,
          consumptions: sectionAccess.consumptionsToSend(current.consumptions),
          submitForReview: current.submitForReview,
        );
        await upsertRepair(
          repair,
          generation: generation,
          requestSeq: patchSeq,
        );
        await deletePendingRepairUpdate(
          current.repairUuid,
          key: updateKeyOf(current),
        );
        sent++;
      } catch (e) {
        // Аккаунт сменился, пока шёл запрос: отказ мог прийти на токен
        // нового обходчика — правку прежнего не помечаем и не разбираем.
        if (switched()) continue;
        if (e is AuthExpiredException) {
          _authExpiredFlag.raise(requestSession: session);
          continue;
        }
        if (isRetryableRepairError(e)) continue;
        // Ремонт ушёл из «Открыт» — 409 `repair_not_open` со статусом
        // (бэкенд `8a88247`). Причина известна из ответа, угадывать её по
        // 403 и перечитанному ремонту ([_checkDenied]) не нужно.
        if (e is RepairNotOpenException) {
          if (e.isScheduled) {
            // Перенесли на будущее — правка ждёт начала, без пометки.
            // Ремонт перечитываем один раз: кэш ещё считает его открытым, и
            // без этого каждый проход слал бы PATCH заново (см. проверку
            // `isScheduled` в начале цикла).
            await _checkDenied(current.repairUuid);
            continue;
          }
          // Снова открыт (успели вернуть на доработку) — следующий проход.
          if (e.status == RepairStatuses.open) continue;
          if (!_isQueued(current)) continue;
          await pendingRepairUpdateBox.put(
            updateKeyOf(current),
            current.markRejected(
              reason: repairNotOpenMessage(e.status),
              serverStatus: e.status,
              conflictKind: e.status == RepairStatuses.closed
                  ? RepairConflictKind.repairClosed.code
                  : RepairConflictKind.other.code,
            ),
          );
          _outboxLog.severe(
              'правка ремонта ${current.repairUuid} отклонена: ремонт '
              '«${e.status}»: $e');
          continue;
        }
        // Сервер прошлой версии заголовка `X-Repair-Conflict-Format` не знает
        // и на то же самое отвечает 403 — для него обход ниже остаётся.
        //
        // У роли нет права на это действие с ремонтом. Ремонт перечитывать
        // незачем — дело не в нём, и без права сервер его, скорее всего, и
        // не отдаст, а ответ «нет доступа к ремонту» превратился бы в
        // окончательное «передан другому». Помечаем своей причиной: по ней
        // правка уйдёт заново, когда доступ поменяется
        // ([retryNoRightsRejections]).
        if (e is AccessDeniedException && e.isNoRights) {
          // Кроме одного случая: ремонт перенесли на будущее, а кэш об этом
          // ещё не знал. Работа по запланированному обходчику не положена —
          // отсюда 403, — но право-то есть, и пометка «нет прав» правку
          // похоронила бы: снимается она только сменой доступа. Уточняем
          // статус у сервера; запланирован — кладём свежий ремонт в кэш и
          // оставляем правку ждать его начала (см. проверку в начале цикла).
          // Ремонт ушёл из «Открыт» или передан другому — это не права, а
          // конфликт состояния: помечаем так же, как прочий отказ ниже.
          final (check, fresh) = await _checkDenied(current.repairUuid);
          if (check == _DeniedCheck.wait) continue;
          // Перечитывание — ещё один запрос: вышли или сменился аккаунт за
          // него — GET упал бы без токена, а пометка легла бы на правку A.
          if (switched()) continue;
          if (!_isQueued(current)) continue;
          final changed = check == _DeniedCheck.stateChanged ? fresh : null;
          await pendingRepairUpdateBox.put(
            updateKeyOf(current),
            current.markRejected(
              reason: changed != null
                  ? repairErrorMessage(e)
                  : repairNoRightsMessage,
              serverStatus: changed?.status,
              conflictKind: changed != null
                  ? _conflictKindOf(changed).code
                  : check == _DeniedCheck.noRights
                      ? RepairConflictKind.noRights.code
                      : RepairConflictKind.other.code,
            ),
          );
          _outboxLog.severe(changed != null
              ? 'правка ремонта ${current.repairUuid} отклонена: ремонт '
                  '«${changed.status}»: $e'
              : 'правка ремонта ${current.repairUuid} отклонена: нет прав: $e');
          continue;
        }
        // Сервер отказал. Чтобы обходчику было что показать, дочитываем
        // текущее состояние ремонта — чаще всего окажется, что администратор
        // закрыл ремонт или передал его другому.
        String? serverStatus;
        var kind = RepairConflictKind.other;
        final readSeq = beginRepairRequest();
        try {
          final fresh = await api.getRepair(current.repairUuid);
          serverStatus = fresh.status;
          await upsertRepair(
            fresh,
            generation: generation,
            requestSeq: readSeq,
          );
          kind = _conflictKindOf(fresh);
        } catch (readError) {
          // Доступа к ремонту больше нет — верный признак передачи другому
          // сотруднику: обходчику отдают только свои и своей должности.
          if (repairErrorMessage(readError) == _noAccessMessage) {
            kind = RepairConflictKind.repairReassigned;
          }
          // Иначе связь пропала сразу после отказа: вид останется «прочее»,
          // экран разрешения это переживёт.
        }
        // Как в ветке 403: за перечитывание могли выйти или сменить аккаунт.
        if (switched()) continue;
        // Правку могли удалить с экрана, пока запрос был в полёте, —
        // возвращать её в бокс нельзя.
        if (!_isQueued(current)) continue;
        await pendingRepairUpdateBox.put(
          updateKeyOf(current),
          current.markRejected(
            reason: repairErrorMessage(e),
            serverStatus: serverStatus,
            conflictKind: kind.code,
          ),
        );
        _outboxLog.severe(
            'правка ремонта ${current.repairUuid} отклонена сервером: $e');
      }
    }
    return sent;
  }

  /// Переносит содержимое черновика в уже существующий ремонт и удаляет
  /// черновик. Доступно только когда ответственный по этому ремонту —
  /// текущий обходчик.
  ///
  /// Правила слияния выбраны так, чтобы ничего не пропало и ничего не
  /// удвоилось:
  /// * комментарий черновика **дописывается** к имеющемуся, а не заменяет его;
  /// * позиции расхода добавляются только те, которых в ремонте ещё нет.
  ///   Количества по совпадающим позициям не складываются: расход — это
  ///   списание со склада, и удваивать его молча нельзя. Такую позицию
  ///   обходчик поправит руками в карточке.
  Future<void> transferDraftToRepair(PendingRepair draft, Repair target) async {
    // Основой берём уже лежащую в очереди правку этого ремонта, а не только
    // серверное состояние: обходчик мог править ремонт офлайн раньше, и ключ
    // бокса — `repairUuid`, то есть запись здесь ровно одна. Без этого
    // перенос затирал прошлую правку вместе с её комментарием, расходом и
    // ещё не уехавшими снимками.
    final existing = pendingUpdateFor(target.uuid);
    final baseComment = (existing?.comment ?? target.comment ?? '').trim();
    final baseConsumptions =
        existing?.consumptions ?? target.actualConsumptions;

    final comments = <String>[
      if (baseComment.isNotEmpty) baseComment,
      if (draft.comment.trim().isNotEmpty &&
          !baseComment.contains(draft.comment.trim()))
        draft.comment.trim(),
    ];

    final merged = List<RepairConsumption>.from(baseConsumptions);
    final present = merged.map((item) => item.sparePartUuid).toSet();
    for (final item in draft.consumptions) {
      if (present.add(item.sparePartUuid)) merged.add(item);
    }

    await savePendingRepairUpdate(PendingRepairUpdate(
      repairUuid: target.uuid,
      repairId: target.id,
      equipmentName: target.equipmentName,
      // Статус, от которого правка отсчитывается, — тот же, что был у прошлой
      // правки: она уже привязана к состоянию, которое обходчик видел.
      baseStatus: existing?.baseStatus ?? target.status,
      createdAt: DateTime.now(),
      comment: comments.join('\n'),
      consumptions: merged,
      // Снимки переезжают вместе с остальным — файлы уже на устройстве, и
      // терять их при переносе нельзя. К снимкам прошлой правки добавляем
      // снимки черновика.
      photoPaths: [...?existing?.photoPaths, ...draft.photoPaths],
      // Удаления, о которых сервер ещё не знает, тоже нельзя потерять.
      deletedPhotoUuids: existing?.deletedPhotoUuids ?? const [],
      // Намерение отправить на рассмотрение сохраняем от любой из сторон.
      submitForReview:
          (existing?.submitForReview ?? false) || draft.submitForReview,
    ));
    // Черновик убираем из бокса напрямую: deletePendingRepair снёс бы и файлы
    // снимков, которые только что перешли к правке.
    await pendingRepairBox.delete(draft.localId);
    _refreshActiveRepairsCount();
    // Связь может быть прямо сейчас — тогда правка уедет, не дожидаясь цикла.
    await syncPendingRepairUpdates();
  }

  /// Повторить отправку правки после разбора конфликта.
  Future<void> retryPendingRepairUpdate(String repairUuid) async {
    final update = pendingUpdateFor(repairUuid);
    if (update == null) return;
    await pendingRepairUpdateBox.put(
      updateKeyOf(update),
      update.clearRejection(),
    );
    await syncPendingRepairUpdates();
  }

  /// Отправляет наработку, снятую обходчиком при сканировании.
  ///
  /// Отказ по существу помечается и больше не повторяется — как у осмотров и
  /// ремонтов. Раньше эта очередь была единственной без такой пометки: любая
  /// ошибка возвращала запись в бокс, и невыполнимый запрос (значение меньше
  /// предыдущего, параметр удалён, отозваны права) крутился в ней вечно.
  ///
  /// Стоило это дорого не самой наработке, а осмотрам: закрытие задачи ТО
  /// намеренно ждёт, пока уедет наработка по тому же оборудованию, — и
  /// зависало вместе с ней навсегда, вместе со списанием ЗИП и без единого
  /// слова на экране.
  ///
  /// Проход идёт один: повторный вызов (фоновый цикл и ручная синхронизация
  /// пересекаются) присоединяется к идущему и дожидается его. Отказывать
  /// нельзя — ручная синхронизация сразу за наработкой отправляет осмотры, и
  /// осмотр, ждущий наработку, проверил бы её раньше, чем она уедет.
  Future<void> syncUsageScans() =>
      _usageSync.run(DataProvider._outboxPassGeneration, _syncUsageScansImpl);

  /// Проход по наработке, начавшийся не раньше вызова — для ручной
  /// синхронизации: фоновый проход мог начаться до того, как обходчик внёс
  /// показание, и в его снимке его нет. См. [GenerationPass.runFresh].
  Future<void> syncUsageScansFresh() => _usageSync.runFresh(
      DataProvider._outboxPassGeneration, _syncUsageScansImpl);

  Future<void> _syncUsageScansImpl() async {
    for (final usage in scanUsageBox.values.toList()) {
      // Наработка другого обходчика с его токеном не уходит (п. 1.5 отчёта).
      if (!isMine(usage)) continue;
      // Отклонённые не долбим на каждом проходе: причина сама не изменится,
      // решение за обходчиком — повторить или выбросить.
      if (usage.isRejected) continue;
      final key = usage.key();
      // Снимок мог устареть, пока шёл проход: запись уже удалили.
      if (!scanUsageBox.containsKey(key)) continue;
      // Более раннее показание по тому же оборудованию — в том числе внутри
      // осмотра — уходит первым, иначе счётчик откатится назад.
      if (isUsageOrderBlocked(
        (equipmentUuid: usage.equipmentUuid, createdAt: usage.createdAt),
        exceptKey: key,
      )) {
        continue;
      }
      final session = _accessSession;
      // Поколение и сессия — до первого `await`: перекладка в «в полёте» — это
      // ожидание, и сменись за него аккаунт, наработка A ушла бы с токеном B,
      // а отказ на него пометил бы её. Сверяемся перед запросом и в `catch`.
      final generation = cacheGeneration;
      bool switched() =>
          isStaleCacheGeneration(generation) || session != _accessSession;
      try {
        // Переносим «сначала положить, потом убрать» — на всех переходах.
        // Наоборот между двумя шагами записи не было бы ни в одном боксе, и
        // осмотр, который ждёт эту наработку (`Scan.usageKeys`), в этот миг
        // решил бы, что она уже принята, и ушёл бы раньше неё — даже если
        // сервер её потом отклонит. Миг, когда запись лежит в обоих боксах,
        // безвреден: проверка ищет её в любом.
        await scanUsagePendingBox.put(key, usage);
        await scanUsageBox.delete(key);
        if (switched()) {
          // Без пометки — уйдёт, когда войдёт её владелец.
          await _returnUsageToQueue(key, usage);
          continue;
        }
        if (await api.updateUsageParameter(usage)) {
          // Принята — только теперь её нет нигде.
          await scanUsagePendingBox.delete(key);
        } else {
          await _returnUsageToQueue(key, usage);
        }
      } catch (e) {
        // Аккаунт сменился или вышли, пока шёл запрос: отказ мог прийти на
        // чужой токен — наработку не помечаем.
        if (switched()) {
          await _returnUsageToQueue(key, usage);
          continue;
        }
        if (e is AuthExpiredException) {
          // Токен протух — наработка не виновата. Возвращаем без пометки:
          // после повторного входа уйдёт сама.
          await _returnUsageToQueue(key, usage);
          _authExpiredFlag.raise(requestSession: session);
          continue;
        }
        if (isRetryableScanError(e)) {
          await _returnUsageToQueue(key, usage);
          _outboxLog
              .warning('наработка $key не отправлена, осталась в очереди: $e');
          continue;
        }
        // Сервер ответил и отказал. Запоминаем причину и перестаём повторять,
        // иначе очередь ТО по этому оборудованию не сдвинется никогда.
        usage.lastError = scanErrorMessage(e);
        await _returnUsageToQueue(key, usage);
        refreshRejectedUsageCount();
        _outboxLog
            .severe('наработка $key отклонена сервером: ${usage.lastError}');
      }
    }
  }

  /// Возвращает наработку из «в полёте» в очередь — тоже «сначала положить,
  /// потом убрать», см. [_syncUsageScansImpl].
  Future<void> _returnUsageToQueue(String key, UsageUpdate usage) async {
    await scanUsageBox.put(key, usage);
    await scanUsagePendingBox.delete(key);
  }

  /// Защита от параллельного запуска: 5-секундный цикл (startScanSyncing) и
  /// ручная синхронизация («Синхронизировать данные») могут вызвать syncScans
  /// одновременно — оба прочитали бы scanBox и отправили один осмотр дважды.
  ///
  /// Второй вызов присоединяется к идущему проходу и дожидается его, а не
  /// возвращается сразу: иначе ручная синхронизация, попав на фоновый проход,
  /// отвечала бы «не получилось» по осмотрам, которые в этот момент как раз
  /// уезжают.
  Future<void> syncScans() =>
      _scanSync.run(DataProvider._outboxPassGeneration, _syncScansImpl);

  /// Проход по осмотрам, начавшийся не раньше вызова. Нужен тем, кто только
  /// что сделал осмотр готовым к отправке: ручная синхронизация, отправившая
  /// его наработку, и повтор отклонённого. Идущий фоновый проход такой осмотр
  /// уже пропустил («ждёт наработку», «отклонён») и к нему не вернётся, а
  /// присоединившись к нему, вызывающий получил бы ложное «не получилось».
  Future<void> syncScansFresh() =>
      _scanSync.runFresh(DataProvider._outboxPassGeneration, _syncScansImpl);

  Future<void> _syncScansImpl() async {
    // Проверяем pending сканы — возвращаем в scanBox те, что прождали 120 секунд
    final pendingScans = scanPendingBox.values.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final scan in pendingScans) {
      final timestampKey = 'scan_pending_${scan.key()}';
      final timestampStr = stringBox.get(timestampKey);
      if (timestampStr != null) {
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final elapsedSeconds = (now - timestamp) ~/ 1000;
          // Удалённый, пока шёл проход («Сбросить осмотры»), не воскрешаем.
          if (elapsedSeconds >= 120 && scanPendingBox.containsKey(scan.key())) {
            // Прошло 120 секунд — возвращаем скан в scanBox для повторной попытки
            await _moveScan(scan, from: scanPendingBox, to: scanBox);
            await stringBox.delete(timestampKey);
          }
        }
      }
    }

    // Обрабатываем сканы из scanBox
    final scans = scanBox.values.toList();
    for (final scan in scans) {
      // Осмотр другого обходчика с его токеном не уходит: ждёт, пока тот
      // снова войдёт на этом телефоне (п. 1.5 отчёта).
      if (!isMine(scan)) continue;
      // Отклонённые сервером не долбим на каждом проходе: причина сама не
      // изменится («Недостаточно ЗИП на складе»), а обходчик увидит её на
      // главной и решит — повторить или сбросить. Тот же приём, что у
      // черновиков ремонта.
      if (scan.isRejected) continue;
      // Осмотр «только наработка» ждёт свои показания: его комментарий — это
      // они и есть. Уйди он раньше, а сервер наработку отклони («меньше
      // прежнего»), история показывала бы значение, которого на сервере нет.
      // Отклонённая наработка держит осмотр, пока обходчик не решит: повтор
      // отправит обоих, удаление наработки удалит и осмотр
      // ([DataProvider.deleteRejectedUsage]).
      if (_waitsForUsage(scan)) continue;
      // Осмотр с наработкой внутри — после всех более ранних показаний по
      // тому же оборудованию, в какой бы очереди они ни лежали.
      if (scan.usageUpdates != null &&
          isUsageOrderBlocked(
            (equipmentUuid: scan.equipmentUuid, createdAt: scan.createdAt),
            exceptKey: scan.key(),
          )) {
        continue;
      }
      final taskUuid = scan.taskUuid;
      final isMaintenancePeriodicTask = taskUuid != null &&
          taskUuid.isNotEmpty &&
          scan.periodicTaskUuid != null &&
          scan.periodicTaskUuid!.isNotEmpty &&
          stringBox.get('maintenance_task_$taskUuid') == '1';

      // Если есть наработка по этому оборудованию, задачи ТО ждем ее отправки
      if (isMaintenancePeriodicTask &&
          scan.equipmentUuid != null &&
          scan.equipmentUuid!.isNotEmpty) {
        // Отклонённую наработку не ждём: она уже не уедет сама, и ждать её —
        // значит не отправить осмотр ТО никогда. Пометка о ней висит на
        // главной, разбирать её обходчику; закрытие задачи и списание ЗИП это
        // держать не должно. Чужую — тоже, как и правило порядка ниже:
        // наработка другого обходчика или другого сервера (у копии базы
        // uuid оборудования совпадает) уйдёт не раньше входа её владельца
        // на её сервере, и ТО ждало бы её вечно.
        final hasPendingUsage = scanUsageBox.values.any(
              (usage) =>
                  usage.equipmentUuid == scan.equipmentUuid &&
                  !usage.isRejected &&
                  isMine(usage),
            ) ||
            scanUsagePendingBox.values.any(
              (usage) =>
                  usage.equipmentUuid == scan.equipmentUuid && isMine(usage),
            ) ||
            // Более раннее показание может лежать и в очереди осмотров —
            // внутри осмотра «только наработка» или другого ТО
            // ([Scan.usageUpdates]). Его очередь наработки не видит, а уйди
            // закрытие первым, ТО посчиталось бы от старого счётчика.
            isUsageOrderBlocked(
              (equipmentUuid: scan.equipmentUuid, createdAt: scan.createdAt),
              exceptKey: scan.key(),
            );
        if (hasPendingUsage) {
          continue;
        }
      }
      // Список снят в начале прохода, а проход долгий — пока шли предыдущие
      // осмотры, этот могли удалить: «Удалить» у отклонённой наработки вместе
      // с привязанным осмотром, «Сбросить осмотры», удаление отклонённого.
      // Без проверки проход переложил бы удалённый осмотр в pending и
      // отправил бы. Стоит последней перед переносом и без `await` между ними
      // и проверкой [_waitsForUsage]: удаление не может вклиниться.
      if (!scanBox.containsKey(scan.key())) continue;
      final timestampKey = 'scan_pending_${scan.key()}';
      final session = _accessSession;
      // Поколение и сессия — до первого `await`, как у наработки: сменись
      // аккаунт за перекладку, осмотр A ушёл бы с токеном B, а отказ на него
      // пометил бы осмотр. Сверяемся перед запросом и в `catch`.
      final generation = cacheGeneration;
      bool switched() =>
          isStaleCacheGeneration(generation) || session != _accessSession;
      // Обратно в очередь без пометки — уйдёт, когда войдёт владелец.
      // Удалённый, пока шёл запрос («Сбросить осмотры»), не воскрешаем.
      Future<void> returnToQueue() async {
        if (scanPendingBox.containsKey(scan.key())) {
          await _moveScan(scan, from: scanPendingBox, to: scanBox);
        }
        await stringBox.delete(timestampKey);
      }

      try {
        // Перемещаем скан в pending перед отправкой
        await _moveScan(scan, from: scanBox, to: scanPendingBox);

        // Сохраняем timestamp текущей попытки
        await stringBox.put(timestampKey, now.toString());

        if (switched()) {
          await returnToQueue();
          continue;
        }

        // Пытаемся отправить
        if (await api.sendScan(scan)) {
          // Успешно - удаляем из всех хранилищ
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          if (scan.taskUuid != null) {
            await stringBox.delete('maintenance_task_${scan.taskUuid}');
          }
          // Сервер списал ЗИП — уменьшаем локальные остатки, не дожидаясь
          // синхронизации каталога: до неё целую минуту предупреждение о
          // нехватке считалось бы по числу, которого на складе уже нет.
          // Кроме доработки: там сервер списывает или возвращает только
          // разницу с прежним расходом, и вычесть весь расход было бы
          // ошибкой — остатки поправит синхронизация каталога.
          //
          // И только если аккаунт не сменился, пока шёл запрос: иначе
          // списание A вычлось бы из каталога B — это уже другой кэш.
          if (!scan.isRework && !switched()) {
            await applyLocalStockWriteOff(scan.actualConsumptions);
          }
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 120 секунд
          // Ничего не делаем, скан уже в scanPendingBox с timestamp
        }
      } catch (e) {
        // Аккаунт сменился или вышли, пока шёл запрос: отказ мог прийти на
        // чужой токен — осмотр не помечаем.
        if (switched()) {
          await returnToQueue();
          continue;
        }
        if (e is AuthExpiredException) {
          // Токен протух. Осмотр не виноват: возвращаем его в основной бокс
          // без пометки об отказе — после повторного входа уйдёт сам.
          await _moveScan(scan, from: scanPendingBox, to: scanBox);
          await stringBox.delete(timestampKey);
          // Ответ на запрос прошлой сессии (выход и новый вход, пока осмотр
          // был в пути) пометку не поднимает: новый вход живой.
          _authExpiredFlag.raise(requestSession: session);
          continue;
        }
        if (isScanAlreadyDelivered(e)) {
          // Сервер отвечает «Закрытый осмотр нельзя изменить» — значит наш
          // предыдущий запрос дошёл, а ответ на него потерялся. Осмотр на
          // месте: убираем из очереди ровно так же, как при успехе, иначе
          // обходчик увидел бы ошибку по благополучно закрытой задаче.
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          if (scan.taskUuid != null) {
            await stringBox.delete('maintenance_task_${scan.taskUuid}');
          }
          // Наш прошлый запрос дошёл — значит списание сервер выполнил, а мы
          // об этом не узнали. Остатки уменьшаем так же, как при успехе — и с
          // той же проверкой смены аккаунта.
          if (!scan.isRework && !switched()) {
            await applyLocalStockWriteOff(scan.actualConsumptions);
          }
          continue;
        }
        if (!isRetryableScanError(e)) {
          // Сервер ответил и отказал — например «Недостаточно ЗИП на складе».
          // Повторять бессмысленно: до правки данных ответ будет тот же, а
          // осмотр иначе крутился бы в очереди вечно, никак этого не
          // показывая. Запоминаем причину по-русски и ждём решения обходчика.
          // 404 на закрытие задачи — задачу сняли на сервере: своя причина,
          // запись с фото остаётся и ждёт решения обходчика.
          scan.lastError = scanRejectionMessage(
            e,
            closesTask: (scan.taskUuid ?? '').isNotEmpty,
          );
          // Нехватку ЗИП сервер описывает точными числами — сохраняем их
          // вместе с осмотром: экран разрешения конфликта откроют позже и,
          // возможно, без связи.
          scan.lastShortages = e is InsufficientStockException
              ? jsonEncode([for (final item in e.shortages) item.toJson()])
              : null;
          await _moveScan(scan, from: scanPendingBox, to: scanBox);
          await stringBox.delete(timestampKey);
          refreshRejectedScansCount();
          _outboxLog.severe(
              'осмотр ${scan.key()} отклонён сервером: ${scan.lastError}');
          continue;
        }
        // Временный сбой: оставляем в pending с timestamp, вернётся сам.
        await scanPendingBox.put(scan.key(), scan);
        await stringBox.put(timestampKey, now.toString());
        _outboxLog.warning(
            'осмотр ${scan.key()} не отправлен, вернётся через 120 с: $e');
      }
    }
  }

  /// Переносит осмотр между основным боксом и «в полёте» — **сначала
  /// положить, потом убрать**, на всех переходах.
  ///
  /// Наоборот между двумя шагами осмотра не было бы ни в одном боксе. Для
  /// осмотра с наработкой внутри это значит: в этот миг очередь наработки не
  /// видит более раннего показания по оборудованию и пропускает вперёд новое
  /// — а старое потом получает отказ «меньше прежнего». Миг, когда осмотр
  /// лежит в обоих боксах, безвреден: проверки ищут его в любом и исключают
  /// по ключу.
  Future<void> _moveScan(
    Scan scan, {
    required Box<Scan> from,
    required Box<Scan> to,
  }) async {
    await to.put(scan.key(), scan);
    await from.delete(scan.key());
  }

  /// По оборудованию [entry] ещё не уехало более раннее показание — в любой
  /// из двух очередей. Правило — [hasEarlierUsage]; здесь только сбор того,
  /// что не принято сервером: отдельная наработка и осмотры с наработкой
  /// внутри, в основных боксах и «в полёте», кроме отклонённых и самой
  /// записи [exceptKey] (при переносе она на миг лежит в двух боксах).
  ///
  /// Записи другого обходчика не в счёт: они ждут его входа и могли бы
  /// держать показания вошедшего сколько угодно долго.
  bool isUsageOrderBlocked(UsageOrderEntry entry, {required String exceptKey}) {
    final others = <UsageOrderEntry>[
      for (final box in [scanUsageBox, scanUsagePendingBox])
        for (final item in box.toMap().entries)
          if (item.key != exceptKey &&
              !item.value.isRejected &&
              isMine(item.value))
            (
              equipmentUuid: item.value.equipmentUuid,
              createdAt: item.value.createdAt,
            ),
      for (final box in [scanBox, scanPendingBox])
        for (final item in box.toMap().entries)
          if (item.key != exceptKey &&
              item.value.usageUpdates != null &&
              !item.value.isRejected &&
              isMine(item.value))
            (
              equipmentUuid: item.value.equipmentUuid,
              createdAt: item.value.createdAt,
            ),
    ];
    return hasEarlierUsage(entry, others);
  }

  /// Какая-то из наработок, к которым привязан осмотр, ещё не принята
  /// сервером — лежит в очереди, в полёте или отклонена.
  bool _waitsForUsage(Scan scan) {
    final keys = scan.usageKeys;
    if (keys == null || keys.isEmpty) return false;
    return keys.any(
      (key) =>
          scanUsageBox.containsKey(key) || scanUsagePendingBox.containsKey(key),
    );
  }

  /// Снимает отметку об отказе — обходчик решил повторить отправку.
  ///
  /// Осмысленно после того, как причина устранена: администратор пополнил
  /// склад. Если нет, сервер откажет тем же текстом, и экран разрешения
  /// конфликта откроется снова.
  Future<void> retryRejectedScan(String key) async {
    final scan = scanBox.get(key);
    if (scan == null || !scan.isRejected) return;
    scan.lastError = null;
    // Числа нехватки принадлежали прошлому отказу. Не снять их — и после
    // отказа по другой причине экран показал бы позиции, к которым новый
    // отказ отношения не имеет.
    scan.lastShortages = null;
    await scanBox.put(key, scan);
    refreshRejectedScansCount();
    invalidateScanTaskCache();
    // Свежий проход: идущий снял снимок, когда осмотр ещё был отклонён.
    await syncScansFresh();
  }

  /// Отправляет отклонённый осмотр заново с исправленным расходом ЗИП.
  ///
  /// Единственный случай, когда расход уже поставленного в очередь осмотра
  /// меняется: сервер отказал по нехватке на складе, и обходчик уменьшил
  /// количества до того, что там есть. Раньше выбора не было — либо ждать,
  /// пока склад пополнят, либо удалить осмотр целиком вместе с фотографиями,
  /// комментарием и фактом закрытия задачи.
  ///
  /// Запись кладётся под тем же ключом: `Scan.key()` расход не учитывает,
  /// поэтому копия заменяет оригинал, а не появляется второй.
  ///
  /// [actualConsumptions] и [consumptionNames] — уже готовые строки JSON, в
  /// том же виде, в каком их собирает экран результата скана. `null` означает
  /// «расхода нет»: поле тогда не уйдёт на сервер вовсе, и списания не будет.
  Future<void> retryRejectedScanWithConsumption(
    String key, {
    required String? actualConsumptions,
    required String? consumptionNames,
  }) async {
    final scan = scanBox.get(key);
    if (scan == null) return;
    final updated = scan.copyWithConsumption(
      actualConsumptions: actualConsumptions,
      consumptionNames: consumptionNames,
    )
      ..lastError = null
      ..lastShortages = null;
    await scanBox.put(key, updated);
    refreshRejectedScansCount();
    invalidateScanTaskCache();
    await syncScansFresh();
  }

  /// Выбрасывает отклонённый осмотр. Отдельно от «Сбросить осмотры»:
  /// та кнопка сносит очередь целиком, включая те, что ещё уйдут сами.
  Future<void> deleteRejectedScan(String key) async {
    final scan = scanBox.get(key);
    if (scan == null) return;
    await scanBox.delete(key);
    if (scan.taskUuid != null) {
      // Пометка «ждать наработку» больше не нужна: осмотра, которого она
      // касалась, нет.
      await stringBox.delete('maintenance_task_${scan.taskUuid}');
    }
    refreshRejectedScansCount();
    // Задача снова свободна — кэш очередей о ней ещё помнит и прятал бы её
    // из списков до следующего захода в «Задачи».
    invalidateScanTaskCache();
  }

  /// Один проход за раз, повторный вызов присоединяется — как у осмотров.
  /// Ключ идемпотентности у создания заявки теперь есть
  /// ([PeriodicTaskRequest.createIdempotencyKey]), но сервер прошлой версии
  /// его не знает: там два прохода, снявшие одну запись, создали бы две
  /// задачи.
  Future<void> syncPeriodicTasks() => _periodicTaskSync.run(
      DataProvider._outboxPassGeneration, _syncPeriodicTasksImpl);

  /// Проход, начавшийся не раньше вызова, — для «Синхронизировать данные».
  /// Кнопка снимает отметку отказа ([retryRejectedProblemReports]) перед
  /// проходом, а идущий фоновый снял список раньше и такие заявки пропустил
  /// бы как отклонённые: присоединившись к нему, кнопка ответила бы «не всё
  /// отправлено» по тому, что даже не пробовала. Проход по-прежнему один —
  /// идущий дожидаемся.
  Future<void> syncPeriodicTasksFresh() => _periodicTaskSync.runFresh(
      DataProvider._outboxPassGeneration, _syncPeriodicTasksImpl);

  Future<void> _syncPeriodicTasksImpl() async {
    // Проверяем pending задачи — возвращаем в periodicTaskBox те, что прождали 120 секунд
    final pendingTasks = periodicTaskPendingBox.values.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in pendingTasks) {
      final timestampKey = 'periodic_task_pending_${task.key()}';
      final timestampStr = stringBox.get(timestampKey);
      if (timestampStr != null) {
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final elapsedSeconds = (now - timestamp) ~/ 1000;
          if (elapsedSeconds >= 120) {
            // Прошло 120 секунд - возвращаем задачу в periodicTaskBox для повторной попытки
            await periodicTaskPendingBox.delete(task.key());
            await stringBox.delete(timestampKey);
            await periodicTaskBox.put(task.key(), task);
          }
        }
      }
    }

    // Обрабатываем задачи из periodicTaskBox
    final tasks = periodicTaskBox.values.toList();
    for (final task in tasks) {
      // Заявка другого обходчика с его токеном не уходит (п. 1.5 отчёта).
      if (!isMine(task)) continue;
      // Снимок мог устареть, пока шёл проход, — как у осмотров.
      if (!periodicTaskBox.containsKey(task.key())) continue;
      // Отклонённую фон не повторяет: ответ был бы тем же. Пометку снимают
      // «Синхронизировать данные» и смена доступа
      // ([retryRejectedProblemReports]).
      if (task.isRejected) continue;
      // Копится по ходу: после создания здесь уже лежит uuid задачи. Снаружи
      // try — именно этот объект должен вернуться в очередь, иначе повтор
      // создал бы задачу заново вместо того, чтобы догрузить снимки.
      var current = task;
      final timestampKey = 'periodic_task_pending_${task.key()}';
      // Поколение кэша — до запросов, как у ремонтов: создание и снимки —
      // два запроса, токен в `API` общий, и сменись аккаунт между ними,
      // снимки A ушли бы с токеном B, а отказ на них удалил бы заявку A.
      // Номер сессии — ради обычного «Выйти»: поколение он не трогает, а
      // снимки без токена получили бы отказ, и запись была бы удалена.
      final generation = cacheGeneration;
      final session = _accessSession;
      bool switched() =>
          isStaleCacheGeneration(generation) || session != _accessSession;
      try {
        // Перемещаем задачу в pending перед отправкой
        await periodicTaskBox.delete(task.key());
        await periodicTaskPendingBox.put(task.key(), task);

        // Сохраняем timestamp текущей попытки
        await stringBox.put(timestampKey, now.toString());

        // Перекладка — три ожидания: сменись за них аккаунт, задача A
        // создалась бы от имени B. Заявка уже «в полёте» с отметкой — вернётся
        // в очередь как обычно, и отправит её A.
        if (switched()) continue;
        if (current.serverUuid == null) {
          final uuid = await api.createPeriodicTask(current);
          // Успех без uuid — оставляем в pending, вернётся через 120 секунд;
          // повтор с тем же ключом сервер узнает.
          if (uuid == null) continue;
          if ((current.photos ?? const <String>[]).isEmpty) {
            await periodicTaskPendingBox.delete(task.key());
            await stringBox.delete(timestampKey);
            continue;
          }
          // Задача есть — запоминаем до снимков: сорвись их загрузка, повтор
          // пойдёт сразу к ним, а не создаст вторую задачу.
          current = current.withServerUuid(uuid);
          await periodicTaskPendingBox.put(task.key(), current);
        }

        // Сменился аккаунт — снимки не шлём: заявка остаётся «в полёте» с
        // uuid созданной задачи и вернётся в очередь как обычно; дошлёт её
        // A, когда войдёт, — сразу к снимкам, без второй задачи.
        if (switched()) continue;
        await api.uploadPeriodicTaskPhotos(
          current.serverUuid!,
          current.photos ?? const <String>[],
          idempotencyKey: current.photosIdempotencyKey,
        );
        await periodicTaskPendingBox.delete(task.key());
        await stringBox.delete(timestampKey);
      } catch (e) {
        final created = current.serverUuid != null;
        // Аккаунт сменился, пока шёл запрос: отказ мог прийти на токен B —
        // заявку A не удаляем и не помечаем. Возвращаем «в полёт» с тем, что
        // уже сделано (uuid созданной задачи).
        if (switched()) {
          await periodicTaskPendingBox.put(task.key(), current);
          await stringBox.put(timestampKey, now.toString());
          continue;
        }
        // Заявка доставлена, а снимки сервер не примет уже никогда (задачу
        // взяли в работу, нет права) — или создание отклонено так, что
        // повтор ответит тем же (задачу по ключу удалили, такая уже есть).
        // Ждать нечего: убираем запись, причина — в журнал.
        if ((created && !isRetryableProblemPhotoError(e)) ||
            (!created && isProblemReportSettled(e))) {
          await periodicTaskPendingBox.delete(task.key());
          await stringBox.delete(timestampKey);
          _outboxLog.severe(created
              ? 'снимки заявки ${current.serverUuid} не приняты сервером, '
                  'заявка доставлена без них: $e'
              : 'заявка ${task.key()} не создана, повтор бесполезен: $e');
          continue;
        }
        // Отказ по существу (оборудования не видно, нет права, данные не
        // приняты) — повтор фоном бесполезен, а бросать нельзя: задачи
        // «Проблема» тогда не будет вовсе. Возвращаем в основной бокс с
        // причиной — до ручного повтора или смены доступа.
        if (!created && isProblemReportRejected(e)) {
          await periodicTaskPendingBox.delete(task.key());
          await stringBox.delete(timestampKey);
          await periodicTaskBox.put(task.key(),
              current.withRejection(problemReportRejectionReason(e)));
          // Полоса на главной — сразу, а не после ручной синхронизации.
          refreshRejectedProblemReportsCount();
          _outboxLog.warning(
              'заявка ${task.key()} отклонена, ждёт ручного повтора: $e');
          continue;
        }
        // Остальное — повторим: оставляем в pending с timestamp, вместе с
        // uuid созданной задачи, если он уже есть.
        await periodicTaskPendingBox.put(task.key(), current);
        await stringBox.put(timestampKey, now.toString());
        _outboxLog.warning(created
            ? 'снимки заявки ${current.serverUuid} не загрузились, '
                'повтор через 120 с: $e'
            : 'периодическая задача ${task.key()} не отправлена,'
                ' вернётся через 120 с: $e');
      }
    }
  }
}
