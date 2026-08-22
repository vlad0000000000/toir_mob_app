part of 'data_provider.dart';

/// Перевод отказа «No access to this repair» — по нему очередь узнаёт, что
/// ремонт передали другому сотруднику. Сравниваем с переводом, а не с
/// английским оригиналом, чтобы источник строки был ровно один.
const String _noAccessMessage = 'Нет доступа к этому ремонту';

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
      try {
        // Ремонт создаём только если его ещё нет: на повторном проходе
        // (например, когда доехал ремонт, но не доехали снимки) черновик уже
        // помнит серверный uuid.
        if (current.serverUuid == null) {
          final repair = await api.createRepair(
            equipmentUuid: current.equipmentUuid,
            consumptionNormUuid: current.consumptionNormUuid,
            startedAt: current.startedAt,
            comment: current.comment,
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
        final finished = await api.updateRepair(
          current.serverUuid!,
          comment: current.comment,
          consumptions: current.consumptions,
          submitForReview: current.submitForReview,
        );
        await upsertRepair(finished);
        await deletePendingRepair(current.localId);
        authExpired.value = false;
        sent++;
      } catch (e) {
        if (e is AuthExpiredException) {
          // Токен протух. Черновик не виноват — оставляем как есть и поднимаем
          // пометку; после повторного входа отправка продолжится сама.
          authExpired.value = true;
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
        print('Error sending pending repair: $e');
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
      try {
        await api.uploadRepairPhotos(
          repairUuid,
          [base64Encode(bytes)],
          idempotencyKey: RepairPhotoFiles.idempotencyKey(repairUuid, bytes),
        );
        await RepairPhotoFiles.delete(path);
      } catch (e) {
        if (e is AuthExpiredException) authExpired.value = true;
        failed = true;
        left.add(path);
        print('Error uploading repair photo: $e');
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
      try {
        await api.deleteRepairPhoto(repairUuid, uuid);
      } catch (e) {
        if (repairErrorMessage(e) == _photoNotFoundMessage) continue;
        if (e is AuthExpiredException) authExpired.value = true;
        failed = true;
        left.add(uuid);
        print('Error deleting repair photo: $e');
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
        final repair = await api.updateRepair(
          current.repairUuid,
          comment: current.comment,
          consumptions: current.consumptions,
          submitForReview: current.submitForReview,
        );
        await upsertRepair(repair);
        await deletePendingRepairUpdate(current.repairUuid);
        authExpired.value = false;
        sent++;
      } catch (e) {
        if (e is AuthExpiredException) {
          authExpired.value = true;
          continue;
        }
        if (isRetryableRepairError(e)) continue;
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
        print('Error sending pending repair update: $e');
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

  Future<void> syncUsageScans() async {
    final scans = scanUsageBox.values.toList();
    for (final scan in scans) {
      try {
        await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox
            .put(scan.key(), scan);
        if (await api.updateUsageParameter(scan)) {
          await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        } else {
          await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.put(scan.key(), scan);
        }
      } catch (e) {
        await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsageBox.put(scan.key(), scan);
        print('Error syncing data: $e');
      }
    }
  }

  Future<void> syncScans() async {
    // Защита от параллельного запуска: 5-секундный цикл (startScanSyncing) и
    // ручная синхронизация ("Синхронизировать данные") могут вызвать syncScans
    // одновременно — оба прочитают scanBox и отправят один осмотр дважды.
    if (_isSyncingScans) return;
    _isSyncingScans = true;
    try {
      await _syncScansImpl();
    } finally {
      _isSyncingScans = false;
    }
  }

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
          if (elapsedSeconds >= 120) {
            // Прошло 120 секунд — возвращаем скан в scanBox для повторной попытки
            await scanPendingBox.delete(scan.key());
            await stringBox.delete(timestampKey);
            await scanBox.put(scan.key(), scan);
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
        final hasPendingUsage = scanUsageBox.values.any(
              (usage) => usage.equipmentUuid == scan.equipmentUuid,
            ) ||
            scanUsagePendingBox.values.any(
              (usage) => usage.equipmentUuid == scan.equipmentUuid,
            );
        if (hasPendingUsage) {
          continue;
        }
      }
      final timestampKey = 'scan_pending_${scan.key()}';
      try {
        // Перемещаем скан в pending перед отправкой
        await scanBox.delete(scan.key());
        await scanPendingBox.put(scan.key(), scan);

        // Сохраняем timestamp текущей попытки
        await stringBox.put(timestampKey, now.toString());

        // Пытаемся отправить
        if (await api.sendScan(scan)) {
          // Успешно - удаляем из всех хранилищ
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          if (scan.taskUuid != null) {
            await stringBox.delete('maintenance_task_${scan.taskUuid}');
          }
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 120 секунд
          // Ничего не делаем, скан уже в scanPendingBox с timestamp
        }
      } catch (e) {
        if (e is AuthExpiredException) {
          // Токен протух. Осмотр не виноват: возвращаем его в основной бокс
          // без пометки об отказе — после повторного входа уйдёт сам.
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          await scanBox.put(scan.key(), scan);
          authExpired.value = true;
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
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          await scanBox.put(scan.key(), scan);
          refreshRejectedScansCount();
          print('Scan rejected by server: ${scan.lastError}');
          continue;
        }
        // Временный сбой: оставляем в pending с timestamp, вернётся сам.
        await scanPendingBox.put(scan.key(), scan);
        await stringBox.put(timestampKey, now.toString());
        print('Error syncing data: $e');
      }
    }
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
    await scanBox.put(key, scan);
    refreshRejectedScansCount();
    invalidateScanTaskCache();
    await syncScans();
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

  Future<void> syncPeriodicTasks() async {
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
      try {
        // Перемещаем задачу в pending перед отправкой
        await periodicTaskBox.delete(task.key());
        await periodicTaskPendingBox.put(task.key(), task);

        // Сохраняем timestamp текущей попытки
        final timestampKey = 'periodic_task_pending_${task.key()}';
        await stringBox.put(timestampKey, now.toString());

        // Пытаемся отправить
        if (await api.createPeriodicTask(task)) {
          // Успешно - удаляем из всех хранилищ
          await periodicTaskPendingBox.delete(task.key());
          await stringBox.delete(timestampKey);
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 120 секунд
          // Ничего не делаем, задача уже в periodicTaskPendingBox с timestamp
        }
      } catch (e) {
        // При ошибке также оставляем в pending с timestamp
        // Убеждаемся, что задача в periodicTaskPendingBox и timestamp сохранен
        await periodicTaskPendingBox.put(task.key(), task);
        final timestampKey = 'periodic_task_pending_${task.key()}';
        await stringBox.put(timestampKey, now.toString());
        print('Error syncing periodic task: $e');
      }
    }
  }
}
