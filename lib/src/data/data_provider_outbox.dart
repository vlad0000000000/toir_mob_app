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

/// Офлайн-очереди отправки: осмотры (scans), наработки (usage),
/// периодические задачи, черновики ремонтов. Перекладывание pending ↔ box +
/// ретраи.
extension DataProviderOutbox on DataProvider {
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
          final repair = await api.createRepair(
            equipmentUuid: current.equipmentUuid,
            consumptionNormUuid: current.createNormUuid,
            startedAt: current.startedAt,
            comment: current.createComment,
            idempotencyKey: current.localId,
          );
          await upsertRepair(repair);
          // Записываем uuid до загрузки снимков: если приложение убьют
          // посреди неё, следующий проход не создаст второй ремонт.
          current = current.copyWith(serverUuid: repair.uuid);
          // Черновик мог быть удалён с экрана, пока запрос был в полёте.
          // Возвращать его в бокс нельзя: обходчик уже решил, что не хочет
          // его видеть, а ремонт на сервере всё равно создан и придёт со
          // следующей синхронизацией.
          if (!pendingRepairBox.containsKey(current.localId)) continue;
          await pendingRepairBox.put(current.localId, current);
        }

        final left =
            await _uploadPhotos(current.serverUuid!, current.photoPaths);
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
          _authExpiredFlag.set(false, requestSession: session);
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
        final finished = await api.updateRepair(
          current.serverUuid!,
          comment: commentChanged ? current.comment : null,
          consumptions: sectionAccess.consumptionsToSend(current.consumptions),
          submitForReview: current.submitForReview,
        );
        await upsertRepair(finished);
        await deletePendingRepair(current.localId);
        _authExpiredFlag.set(false, requestSession: session);
        sent++;
      } catch (e) {
        if (e is AuthExpiredException) {
          // Токен протух. Черновик не виноват — оставляем как есть и поднимаем
          // пометку; после повторного входа отправка продолжится сама.
          // Отказ на запрос прошлой сессии пометку не поднимает.
          _authExpiredFlag.set(true, requestSession: session);
          continue;
        }
        if (isRetryableRepairError(e)) {
          // Связи нет или сервер ещё дожёвывает наш прошлый запрос с тем же
          // ключом — оставляем как есть, даже попытку не засчитываем.
          continue;
        }
        // Сервер ответил и отказал. Запоминаем причину по-русски и больше не
        // повторяем автоматически.
        //
        // Занявший ремонт доискиваем только тогда, когда отказ действительно
        // про занятое оборудование: поиск при промахе перекачивает весь
        // список ремонтов, и делать это на каждом отказе — включая сбой
        // сервера и ошибку валидации — значило гонять сеть впустую ради
        // значения, которое всё равно окажется пустым.
        final reason = repairErrorMessage(e);
        // Удалён с экрана, пока летел запрос, — пометку ставить некуда.
        if (!pendingRepairBox.containsKey(current.localId)) continue;
        await pendingRepairBox.put(
          current.localId,
          current.markRejected(
            reason: reason,
            conflictRepairUuid: isEquipmentBusyMessage(reason)
                ? await _findBlockingRepair(current.equipmentUuid)
                : null,
          ),
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
  Future<List<String>> _uploadPhotos(
      String repairUuid, List<String> paths) async {
    final left = <String>[];
    var failed = false;
    for (final path in paths) {
      if (failed) {
        left.add(path);
        continue;
      }
      final bytes = await RepairPhotoFiles.read(path);
      if (bytes == null) {
        // Файла нет — вычёркиваем: ждать его бессмысленно.
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
        if (e is AuthExpiredException) {
          _authExpiredFlag.set(true, requestSession: session);
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
    List<String> photoUuids,
  ) async {
    final left = <String>[];
    var failed = false;
    for (final uuid in photoUuids) {
      if (failed) {
        left.add(uuid);
        continue;
      }
      final session = _accessSession;
      try {
        await api.deleteRepairPhoto(repairUuid, uuid);
      } catch (e) {
        if (repairErrorMessage(e) == _photoNotFoundMessage) continue;
        if (e is AuthExpiredException) {
          _authExpiredFlag.set(true, requestSession: session);
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
    for (final entry in scanBox.toMap().entries) {
      final scan = entry.value;
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
      if (!isNoRightsReason(usage.lastError)) continue;
      usage.lastError = null;
      await scanUsageBox.put(entry.key, usage);
      cleared++;
    }
    for (final draft in pendingRepairBox.values.toList()) {
      if (!isRepairNoRightsMessage(draft.lastError)) continue;
      await pendingRepairBox.put(draft.localId, draft.clearRejection());
      cleared++;
    }
    for (final update in pendingRepairUpdateBox.values.toList()) {
      if (!isRepairNoRightsMessage(update.lastError)) continue;
      await pendingRepairUpdateBox.put(
          update.repairUuid, update.clearRejection());
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
      if (!entry.value.isRejected) continue;
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
    for (final update in pendingRepairUpdateBox.values.toList()) {
      if (update.isRejected) continue;
      // Снаружи try по той же причине, что и у черновиков: в отказ должен
      // попасть объект с уже вычеркнутыми снимками и удалениями, а не
      // исходный — иначе следующая попытка проделает ту же работу заново.
      var current = update;
      final session = _accessSession;
      try {
        // Фотографии — до PATCH, а не после. PATCH может перевести ремонт в
        // «На рассмотрении», и после этого сервер снимки уже не примет.
        if (current.hasPhotoWork) {
          final photosLeft =
              await _uploadPhotos(current.repairUuid, current.photoPaths);
          final deletesLeft = await _deletePhotos(
            current.repairUuid,
            current.deletedPhotoUuids,
          );
          current = current.copyWith(
            photoPaths: photosLeft,
            deletedPhotoUuids: deletesLeft,
          );
          if (!pendingRepairUpdateBox.containsKey(current.repairUuid)) continue;
          await pendingRepairUpdateBox.put(current.repairUuid, current);
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
          if (!pendingRepairUpdateBox.containsKey(current.repairUuid)) continue;
          await pendingRepairUpdateBox.put(
            current.repairUuid,
            current.markRejected(
              reason: repairNoRightsMessage,
              conflictKind: RepairConflictKind.other.code,
            ),
          );
          continue;
        }
        final repair = await api.updateRepair(
          current.repairUuid,
          comment: current.comment,
          consumptions: sectionAccess.consumptionsToSend(current.consumptions),
          submitForReview: current.submitForReview,
        );
        await upsertRepair(repair);
        await deletePendingRepairUpdate(current.repairUuid);
        _authExpiredFlag.set(false, requestSession: session);
        sent++;
      } catch (e) {
        if (e is AuthExpiredException) {
          _authExpiredFlag.set(true, requestSession: session);
          continue;
        }
        if (isRetryableRepairError(e)) continue;
        // У роли нет права на это действие с ремонтом. Ремонт перечитывать
        // незачем — дело не в нём, и без права сервер его, скорее всего, и
        // не отдаст, а ответ «нет доступа к ремонту» превратился бы в
        // окончательное «передан другому». Помечаем своей причиной: по ней
        // правка уйдёт заново, когда доступ поменяется
        // ([retryNoRightsRejections]).
        if (e is AccessDeniedException && e.isNoRights) {
          if (!pendingRepairUpdateBox.containsKey(current.repairUuid)) continue;
          await pendingRepairUpdateBox.put(
            current.repairUuid,
            current.markRejected(
              reason: repairNoRightsMessage,
              conflictKind: RepairConflictKind.other.code,
            ),
          );
          _outboxLog.severe(
              'правка ремонта ${current.repairUuid} отклонена: нет прав: $e');
          continue;
        }
        // Сервер отказал. Чтобы обходчику было что показать, дочитываем
        // текущее состояние ремонта — чаще всего окажется, что администратор
        // закрыл ремонт или передал его другому.
        String? serverStatus;
        var kind = RepairConflictKind.other;
        try {
          final fresh = await api.getRepair(current.repairUuid);
          serverStatus = fresh.status;
          await upsertRepair(fresh);
          if (fresh.isClosed) {
            kind = RepairConflictKind.repairClosed;
          } else {
            // Ремонт жив, но ответственный уже не мы — забрал другой обходчик
            // или переназначил администратор.
            final me = GlobalState.authUser?.uuid;
            final owner = fresh.responsibleUserUuid;
            if (me != null &&
                owner != null &&
                owner.isNotEmpty &&
                owner != me) {
              kind = RepairConflictKind.repairReassigned;
            }
          }
        } catch (readError) {
          // Доступа к ремонту больше нет — верный признак передачи другому
          // сотруднику: обходчику отдают только свои и своей должности.
          if (repairErrorMessage(readError) == _noAccessMessage) {
            kind = RepairConflictKind.repairReassigned;
          }
          // Иначе связь пропала сразу после отказа: вид останется «прочее»,
          // экран разрешения это переживёт.
        }
        // Правку могли удалить с экрана, пока запрос был в полёте, —
        // возвращать её в бокс нельзя.
        if (!pendingRepairUpdateBox.containsKey(current.repairUuid)) continue;
        await pendingRepairUpdateBox.put(
          current.repairUuid,
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
    final update = pendingRepairUpdateBox.get(repairUuid);
    if (update == null) return;
    await pendingRepairUpdateBox.put(repairUuid, update.clearRejection());
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
      try {
        // Переносим «сначала положить, потом убрать» — на всех переходах.
        // Наоборот между двумя шагами записи не было бы ни в одном боксе, и
        // осмотр, который ждёт эту наработку (`Scan.usageKeys`), в этот миг
        // решил бы, что она уже принята, и ушёл бы раньше неё — даже если
        // сервер её потом отклонит. Миг, когда запись лежит в обоих боксах,
        // безвреден: проверка ищет её в любом.
        await scanUsagePendingBox.put(key, usage);
        await scanUsageBox.delete(key);
        if (await api.updateUsageParameter(usage)) {
          // Принята — только теперь её нет нигде.
          await scanUsagePendingBox.delete(key);
          // Сервер принял запрос этой сессии — токен живой.
          _authExpiredFlag.set(false, requestSession: session);
        } else {
          await _returnUsageToQueue(key, usage);
        }
      } catch (e) {
        if (e is AuthExpiredException) {
          // Токен протух — наработка не виновата. Возвращаем без пометки:
          // после повторного входа уйдёт сама.
          await _returnUsageToQueue(key, usage);
          _authExpiredFlag.set(true, requestSession: session);
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
        // держать не должно.
        final hasPendingUsage = scanUsageBox.values.any(
              (usage) =>
                  usage.equipmentUuid == scan.equipmentUuid &&
                  !usage.isRejected,
            ) ||
            scanUsagePendingBox.values.any(
              (usage) => usage.equipmentUuid == scan.equipmentUuid,
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
      try {
        // Перемещаем скан в pending перед отправкой
        await _moveScan(scan, from: scanBox, to: scanPendingBox);

        // Сохраняем timestamp текущей попытки
        await stringBox.put(timestampKey, now.toString());

        // Пытаемся отправить
        if (await api.sendScan(scan)) {
          // Успешно - удаляем из всех хранилищ
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          // Сервер принял запрос этой сессии — токен живой, пометка «сессия
          // истекла» (если её успел поднять другой запрос) уже неправда.
          _authExpiredFlag.set(false, requestSession: session);
          if (scan.taskUuid != null) {
            await stringBox.delete('maintenance_task_${scan.taskUuid}');
          }
          // Сервер списал ЗИП — уменьшаем локальные остатки, не дожидаясь
          // синхронизации каталога: до неё целую минуту предупреждение о
          // нехватке считалось бы по числу, которого на складе уже нет.
          // Кроме доработки: там сервер списывает или возвращает только
          // разницу с прежним расходом, и вычесть весь расход было бы
          // ошибкой — остатки поправит синхронизация каталога.
          if (!scan.isRework) {
            await applyLocalStockWriteOff(scan.actualConsumptions);
          }
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 120 секунд
          // Ничего не делаем, скан уже в scanPendingBox с timestamp
        }
      } catch (e) {
        if (e is AuthExpiredException) {
          // Токен протух. Осмотр не виноват: возвращаем его в основной бокс
          // без пометки об отказе — после повторного входа уйдёт сам.
          await _moveScan(scan, from: scanPendingBox, to: scanBox);
          await stringBox.delete(timestampKey);
          // Ответ на запрос прошлой сессии (выход и новый вход, пока осмотр
          // был в пути) пометку не поднимает: новый вход живой.
          _authExpiredFlag.set(true, requestSession: session);
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
          // об этом не узнали. Остатки уменьшаем так же, как при успехе.
          if (!scan.isRework) {
            await applyLocalStockWriteOff(scan.actualConsumptions);
          }
          continue;
        }
        if (!isRetryableScanError(e)) {
          // Сервер ответил и отказал — например «Недостаточно ЗИП на складе».
          // Повторять бессмысленно: до правки данных ответ будет тот же, а
          // осмотр иначе крутился бы в очереди вечно, никак этого не
          // показывая. Запоминаем причину по-русски и ждём решения обходчика.
          scan.lastError = scanErrorMessage(e);
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
  bool isUsageOrderBlocked(UsageOrderEntry entry, {required String exceptKey}) {
    final others = <UsageOrderEntry>[
      for (final box in [scanUsageBox, scanUsagePendingBox])
        for (final item in box.toMap().entries)
          if (item.key != exceptKey && !item.value.isRejected)
            (
              equipmentUuid: item.value.equipmentUuid,
              createdAt: item.value.createdAt,
            ),
      for (final box in [scanBox, scanPendingBox])
        for (final item in box.toMap().entries)
          if (item.key != exceptKey &&
              item.value.usageUpdates != null &&
              !item.value.isRejected)
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
      try {
        // Перемещаем задачу в pending перед отправкой
        await periodicTaskBox.delete(task.key());
        await periodicTaskPendingBox.put(task.key(), task);

        // Сохраняем timestamp текущей попытки
        await stringBox.put(timestampKey, now.toString());

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

        await api.uploadPeriodicTaskPhotos(
          current.serverUuid!,
          current.photos ?? const <String>[],
          idempotencyKey: current.photosIdempotencyKey,
        );
        await periodicTaskPendingBox.delete(task.key());
        await stringBox.delete(timestampKey);
      } catch (e) {
        final created = current.serverUuid != null;
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
