part of 'data_provider.dart';

/// Результат ручной синхронизации (кнопка «Синхронизировать данные»).
enum SyncResult {
  noConnection,
  allSynced,
  scansSynced,
  scansFailed,

  /// Справочники обновились, но часть черновиков ремонтов сервер не принял.
  repairsFailed,
}

/// Фоновая синхронизация справочников/задач с сервером.
extension DataProviderSync on DataProvider {
  Future<void> syncCurrentSession() async {
    _isLoading = true;

    try {
      setCurrentSession(await api.getCurrentSession());
    } catch (e) {
      print('Failed sync session: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncInventory() async {
    _isLoading = true;

    try {
      var inventoryRecords = await loadAllInventory();
      await inventoryBox.clear();
      await inventoryBox.addAll(inventoryRecords);
      updateInventoryRecords();
    } catch (e, s) {
      print('Failed sync inventory: $e');
      print(s);
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncTypicalProblems() async {
    _isLoading = true;

    try {
      _typicalProblems = await loadAllTypicalProblems();
      await typicalProblemBox.clear();
      await typicalProblemBox.addAll(_typicalProblems);
    } catch (e) {
      print('Failed sync typical problems: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncPeriodicityRules() async {
    _isLoading = true;

    try {
      _periodicityRules = await loadAllPeriodicityRules();
      await periodicityRuleBox.clear();
      await periodicityRuleBox.addAll(_periodicityRules);
    } catch (e) {
      print('Failed sync periodicity rules: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncUsageUnitTypes() async {
    _isLoading = true;

    try {
      _usageUnits = await loadAllUsageUnitTypes();
      await usageUnitBox.clear();
      await usageUnitBox.addAll(_usageUnits);
    } catch (e) {
      print('Failed sync usage unit types: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Перекачивает справочник ЗИП. `true` — каталог и отметка «Остатки на …»
  /// обновились, `false` — не вышло (нет связи, отказ сервера).
  ///
  /// Результат возвращается, а не глотается молча: экран показывает по нему
  /// причину. Раньше обходчик тянул список вниз, ничего не менялось, и
  /// понять, устарели ли остатки или просто нечему меняться, было нельзя.
  Future<bool> syncSpareParts() {
    // Проход уже идёт — присоединяемся к нему, а не отказываем.
    //
    // Фоновый цикл (раз в 60 секунд) и жест «потянуть вниз» легко
    // пересекаются. Запускать второй проход нельзя: внутри `clear()` и
    // `addAll()`, и при наложении второй `addAll` ляжет поверх уже очищенного
    // бокса — справочник задвоится. Но и отвечать «не вышло» неправда:
    // синхронизация идёт, просто не наша. Тогда обходчик тянул список,
    // получал отказ, а отметка «Остатки на …» обновлялась мгновением позже
    // чужим проходом — со стороны это и выглядело как «время не то».
    final running = _sparePartsSync;
    if (running != null) return running;
    final started = _syncSparePartsImpl();
    _sparePartsSync = started;
    return started.whenComplete(() => _sparePartsSync = null);
  }

  /// Подтягивает каталог ЗИП, если его ещё нет.
  ///
  /// Вызывают экраны, которым каталог нужен прямо сейчас: раздел ЗИП, список
  /// ремонтов и карточка ремонта (подбор позиций и остатки в расходе). Нужно
  /// это ровно для первого захода — [mainSync] мог ещё не отработать, и
  /// подобрать позицию в расходе было бы не из чего.
  ///
  /// Ничего не ждёт, если каталог уже загружен: это проверка на входе в
  /// экран, а не обновление. Освежает каталог [mainSync] — он же и держит
  /// остатки свежими, — а также жест «потянуть вниз» в разделе ЗИП.
  Future<void> ensureSparePartsLoaded() async {
    // Непустого списка мало: прерванная запись оставляет в боксе половину
    // каталога, и она выглядит как готовая.
    if (spareParts.isNotEmpty && !isSparePartsWriteIncomplete) return;
    await syncSpareParts();
  }

  Future<bool> _syncSparePartsImpl() async {
    _isLoading = true;

    try {
      // Инкрементально — только когда есть от чего отсчитывать и каталог в
      // хранилище цел. Иначе полный проход: он же и переводит бокс на ключи
      // по uuid, без которых точечное обновление невозможно.
      final cursor = getSparePartsCursor();
      if (cursor != null &&
          sparePartBox.isNotEmpty &&
          !isSparePartsWriteIncomplete) {
        return await _syncSparePartsIncremental(cursor);
      }
      return await _syncSparePartsFull();
    } catch (e) {
      print('Failed sync spare parts: $e');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Полная выгрузка каталога. Нужна на первом запуске, после сброса и когда
  /// прошлая запись оборвалась на середине.
  ///
  /// Ключ в боксе — uuid позиции: только так потом можно обновить и удалить
  /// точечно. Прежде ключи были автоинкрементными, поэтому первый проход
  /// после обновления приложения обязательно полный — он и перекладывает
  /// каталог на новые ключи.
  Future<bool> _syncSparePartsFull() async {
    // Запрашиваем окно «с начала времён», а не просто список: так тем же
    // запросом приходит серверная граница `sync_until`, от которой потом
    // считается инкрементальный проход. Без неё каталог качался бы целиком
    // всегда — отметку было бы неоткуда взять.
    //
    // Если сервер инкрементальный режим не понимает, он отдаст обычный
    // список, границы не будет, и клиент останется на полных проходах.
    final since = DateTime.utc(1970);
    final first =
        await api.getSparePartsPage(limit: 100, offset: 0, updatedSince: since);
    final all = <SparePart>[...first.items];
    if (first.items.length == 100) {
      for (var offset = 100;; offset += 100) {
        final page = await api.getSparePartsPage(
          limit: 100,
          offset: offset,
          updatedSince: since,
          syncUntil: first.syncUntil,
        );
        all.addAll(page.items);
        if (page.items.length < 100) break;
        if (_pagingLimitReached(offset)) break;
      }
    }
    all.sort(SparePart.compareByName);
    _spareParts = all;
    _rebuildSparePartIndex();
    // Между clear() и putAll() бокс пуст или неполон. Флаг снаружи этой пары
    // помечает такое состояние как незавершённое — см.
    // markSparePartsWriteStarted.
    await markSparePartsWriteStarted();
    await sparePartBox.clear();
    await sparePartBox.putAll({for (final part in all) part.uuid: part});
    await markSparePartsWriteFinished();
    await _saveSparePartsCursor(first.syncUntil);
    await saveSparePartsSyncDate();
    return true;
  }

  /// Догружает только изменившееся с момента [cursor].
  ///
  /// Ради этого и затевалось: каталог рассчитан на десятки тысяч позиций, а
  /// полная перезапись шла на каждый проход — и раз в минуту фоновым циклом.
  /// Здесь запросов ровно столько, сколько страниц изменений, и почти всегда
  /// это одна пустая страница.
  ///
  /// Отметку двигаем последней: если проход оборвётся, следующий повторит то
  /// же окно. Повтор безвреден — записи кладутся по ключу, а удаление уже
  /// удалённого ничего не делает.
  Future<bool> _syncSparePartsIncremental(DateTime cursor) async {
    final changed = <SparePart>[];
    final deleted = <String>{};
    DateTime? until;

    for (var offset = 0;; offset += 100) {
      final page = await api.getSparePartsPage(
        limit: 100,
        offset: offset,
        updatedSince: cursor,
        syncUntil: until,
      );
      // Сервер не понял инкрементальный режим — откатываемся на полный
      // проход, чтобы не принять «всё подряд» за список изменений.
      if (page.syncUntil == null) return _syncSparePartsFull();
      until ??= page.syncUntil;
      changed.addAll(page.items);
      deleted.addAll(page.deletedUuids);
      if (page.items.length < 100) break;
      if (_pagingLimitReached(offset)) break;
    }

    if (changed.isNotEmpty) {
      await sparePartBox.putAll({for (final part in changed) part.uuid: part});
    }
    for (final uuid in deleted) {
      await sparePartBox.delete(uuid);
    }
    // Порядок на диске после точечных правок уже не отсортирован — сортируем
    // список в памяти. На старте приложения это делает конструктор.
    final all = sparePartBox.values.toList()
      ..sort(SparePart.compareByName);
    _spareParts = all;
    _rebuildSparePartIndex();
    await _saveSparePartsCursor(until);
    await saveSparePartsSyncDate();
    return true;
  }

  /// Перекачивает активные ремонты обходчика в офлайн-кэш.
  ///
  /// Без `clear()`: сначала кладём свежие, потом убираем лишние. Очистка
  /// с последующей заливкой оставляла окно, в котором бокс пуст, — а этот
  /// метод крутится в фоне каждую минуту параллельно с очередью отправки, и
  /// попади окно на чтение карточки, обходчик увидел бы «ремонт не найден»
  /// на ровном месте.
  ///
  /// Ремонты, только что созданные очередью, из кэша не выбрасываем, даже
  /// если их нет в ответе: список мог быть запрошен до их появления. Такой
  /// ремонт помнит свой черновик — по `serverUuid`.
  /// Перекачивает активные ремонты обходчика в офлайн-кэш.
  ///
  /// Инкрементально, если в этом запуске уже был полный проход. Курсор живёт
  /// **в памяти**, а не в Hive, и это осознанно: окно сообщает об изменениях
  /// и удалениях, но не о том, что ремонт передали другому сотруднику — тогда
  /// он просто уходит из выдачи, не попадая ни в `items`, ни в `deleted`, и
  /// завис бы в кэше. Полный проход на каждом холодном старте ограничивает
  /// такое расхождение одним сеансом. Ремонтов у обходчика единицы, так что
  /// цена этой страховки — один запрос при запуске.
  Future<void> syncMyRepairs() async {
    final cursor = _repairsCursor;
    if (cursor != null && repairBox.isNotEmpty) {
      return _syncMyRepairsIncremental(cursor);
    }
    return _syncMyRepairsFull();
  }

  Future<void> _syncMyRepairsFull() async {
    _isLoading = true;

    try {
      final (fresh, until) = await _loadActiveRepairsWithCursor();
      _repairsCursor = until;
      final keep = {for (final repair in fresh) repair.uuid};
      for (final draft in pendingRepairBox.values) {
        final uuid = draft.serverUuid;
        if (uuid == null || uuid.isEmpty) continue;
        // Только пока ремонт активен: если администратор успел его закрыть,
        // держать запись в кэше активных незачем — она попала бы во вкладку
        // «Закрыт» вторым экземпляром рядом с серверным.
        final cached = repairBox.get(uuid);
        if (cached != null && cached.isActive) keep.add(uuid);
      }
      // Ключ — uuid, а не автоинкремент: так отдельный ремонт можно обновить
      // точечно (см. DataProvider.upsertRepair), не перекачивая весь список.
      await repairBox.putAll({for (final repair in fresh) repair.uuid: repair});
      for (final key in repairBox.keys.toList()) {
        if (!keep.contains(key)) await repairBox.delete(key);
      }
      _repairs = repairBox.values.toList();
      _refreshActiveRepairsCount();
    } catch (e) {
      print('Failed sync repairs: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Активные ремонты постранично — вместе с серверной границей окна.
  ///
  /// Окно «с начала времён» вместо простого списка: тем же запросом приходит
  /// `sync_until`, от которого дальше считается инкрементальный проход. Без
  /// него отметку было бы неоткуда взять, и каждый проход оставался бы полным.
  Future<(List<Repair>, DateTime?)> _loadActiveRepairsWithCursor() async {
    const statuses = [RepairStatuses.open, RepairStatuses.underReview];
    final since = DateTime.utc(1970);
    final first = await api.getRepairsPage(
      statuses: statuses,
      limit: 100,
      offset: 0,
      updatedSince: since,
    );
    final all = <Repair>[...first.items];
    if (first.items.length == 100) {
      for (var offset = 100;; offset += 100) {
        final page = await api.getRepairsPage(
          statuses: statuses,
          limit: 100,
          offset: offset,
          updatedSince: since,
          syncUntil: first.syncUntil,
        );
        all.addAll(page.items);
        if (page.items.length < 100) break;
        if (_pagingLimitReached(offset)) break;
      }
    }
    return (all, first.syncUntil);
  }

  /// Догружает ремонты, изменившиеся с момента [cursor].
  ///
  /// **Без фильтра по статусу** — намеренно. Закрытый ремонт должен приехать
  /// в `items` со своим новым статусом, чтобы уйти из кэша активных; с
  /// фильтром он бы просто не пришёл и остался в кэше открытым.
  ///
  /// Черновики, чей ремонт сервер уже принял, не трогаем: их удерживает та же
  /// проверка, что и в полном проходе.
  Future<void> _syncMyRepairsIncremental(DateTime cursor) async {
    _isLoading = true;
    try {
      final changed = <Repair>[];
      final deleted = <String>{};
      DateTime? until;

      for (var offset = 0;; offset += 100) {
        final page = await api.getRepairsPage(
          limit: 100,
          offset: offset,
          updatedSince: cursor,
          syncUntil: until,
        );
        // Сервер не понял режим — откатываемся на полный проход, иначе
        // приняли бы «все ремонты подряд» за список изменений.
        if (page.syncUntil == null) {
          _repairsCursor = null;
          return _syncMyRepairsFull();
        }
        until ??= page.syncUntil;
        changed.addAll(page.items);
        deleted.addAll(page.deletedUuids);
        if (page.items.length < 100) break;
        if (_pagingLimitReached(offset)) break;
      }

      for (final repair in changed) {
        if (repair.isActive) {
          await repairBox.put(repair.uuid, repair);
        } else {
          // Ремонт закрыли: в кэше активных ему больше не место. Закрытые
          // приложение не кэширует вовсе — их отдаёт отдельный эндпоинт.
          await repairBox.delete(repair.uuid);
        }
      }
      for (final uuid in deleted) {
        await repairBox.delete(uuid);
      }

      _repairs = repairBox.values.toList();
      _refreshActiveRepairsCount();
      // Отметку двигаем последней: оборванный проход повторит то же окно, а
      // повтор безвреден — записи кладутся по ключу.
      _repairsCursor = until;
    } catch (e) {
      print('Failed sync repairs: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncCompany() async {
    _isLoading = true;

    try {
      _company = await api.getCompany();
      await companyBox.put('company', _company!);
    } catch (e) {
      print('Failed sync company: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncEquipmentStates() async {
    _isLoading = true;

    try {
      _equipmentState = await api.getEquipmentStates();
      await equipmentStateBox.put('equipment_state', _equipmentState!);
    } catch (e) {
      print('Failed sync equipment states: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Выгружает нормы расхода для ремонта в кэш.
  ///
  /// Целиком, а не по оборудованию: заранее неизвестно, какой станок обходчик
  /// заведёт в ремонт, а без связи спросить сервер будет уже не у кого. Норм
  /// на компанию десятки — одна-две страницы, поэтому проход дешёвый и едет
  /// вместе с остальными справочниками.
  ///
  /// Бокс переписываем целиком: норму могли удалить на сервере, и остаться в
  /// выборе она не должна.
  Future<void> syncConsumptionNorms() async {
    _isLoading = true;
    try {
      const pageSize = 100;
      final List<ConsumptionNorm> all = [];
      for (var skip = 0;; skip += pageSize) {
        final page = await api.getConsumptionNorms(limit: pageSize, skip: skip);
        all.addAll(page);
        if (page.length < pageSize) break;
        // Тот же предохранитель, что и у постраничных загрузок в
        // `data_provider_remote`: без него сервер, перестав учитывать `skip`,
        // загонял бы этот цикл в бесконечную загрузку.
        if (_pagingLimitReached(all.length)) break;
      }
      // Между clear() и putAll() бокс пуст. Флаг снаружи этой пары помечает
      // такое состояние как незавершённое — тот же приём, что у каталога ЗИП.
      await markNormsWriteStarted();
      await consumptionNormBox.clear();
      await consumptionNormBox
          .putAll({for (final norm in all) norm.uuid: norm});
      await markNormsWriteFinished();
    } catch (e) {
      // Как и остальные справочники: при сбое остаётся прошлый снимок.
      print('Failed sync consumption norms: $e');
    } finally {
      _isLoading = false;
    }
  }

  // Метод синхронизации задач
  Future<void> syncTasks() async {
    _isLoading = true;
    try {
      // Два независимых постраничных прохода — тянем их параллельно, а не
      // один за другим.
      final loaded = await Future.wait([loadAllTasks(), loadAllOpenTasks()]);
      final tasks = [...loaded[0], ...loaded[1]];
      Map<String, Task> tasksDict = {};
      for (var task in tasks) {
        tasksDict[task.uuid] = task;
      }
      // Осмотры задач ППР добираем до записи в ящик: очистка и заливка
      // должны быть одной операцией, иначе между ними раздел «ППР»
      // ненадолго пропадает из списков.
      for (final task in await loadPprInspections(tasksDict.keys.toSet())) {
        tasksDict[task.uuid] = task;
      }
      // Что сервер вообще отдал в этот раз — считаем до фильтрации: по этому
      // набору ниже снимаются отработавшие отметки.
      final returned = tasksDict.keys.toSet();
      // Закрытые обходчиком в ящик не возвращаем. Иначе полная перезапись
      // отменяла бы `taskBox.delete` из `addScan`: осмотр в этот момент ещё
      // лежит в очереди, сервер честно отдаёт задачу как `scheduled`, и она
      // всплывала обратно в списке. Сам же экран и запускал эту гонку —
      // `mainSync()` вызывается сразу после отправки.
      tasksDict.removeWhere((uuid, _) => isTaskClosedLocally(uuid));
      await taskBox.clear();
      await taskBox.putAll(tasksDict);
      // Отметка нужна ровно до тех пор, пока сервер сам не перестанет считать
      // задачу активной. Как только он её не вернул — снимаем, иначе отметки
      // копились бы в боксе без конца.
      //
      // Осмотры действующих ППР исключаем: [loadPprInspections] их и не
      // запрашивает, пока стоит отметка, — значит в `returned` их нет по
      // нашей же вине. Сняли бы отметку — на следующем проходе осмотр
      // подгрузился бы по uuid и вернулся в список. Их отметки снимутся
      // сами, когда осмотр уйдёт из состава актуального ППР.
      await pruneClosedTasks(returned.union(_pprInspectionUuids));
    } catch (e, stack) {
      print('Error syncing tasks: $e');
      print(stack);
    } finally {
      _isLoading = false;
    }
  }

  /// Синхронизирует актуальные ППР и состав их периодических задач.
  /// Ошибку глотаем (как и остальные sync-методы) — при сбое остаётся
  /// последний закэшированный набор из `stringBox`.
  ///
  /// Сами осмотры задач ППР догружает [syncTasks] (или [syncPprInspections],
  /// если задачи перечитывать не нужно), поэтому вызывать до [syncTasks].
  ///
  /// При выключенном [FeatureFlags.pprEnabled] не ходит в сеть.
  Future<void> syncPpr() async {
    if (!FeatureFlags.pprEnabled) return;
    _isLoading = true;
    try {
      final pprs = await api.getActivePprs();
      setActivePprs(pprs);
      await stringBox.put(DataProvider.pprCacheKey,
          jsonEncode(pprs.map((ppr) => ppr.toJson()).toList()));
      await syncPprCompletedByMe();
    } catch (e) {
      print('Failed sync PPR: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Определяет, какие из уже выполненных задач актуальных ППР закрывал
  /// текущий пользователь, — по ним строится счётчик «выполнено N из M»
  /// на экране ППР. Закрытые осмотры в ящик задач не кладём: они не должны
  /// попасть в списки, нужен только факт «эта задача была моей».
  ///
  /// Осмотр закрыт навсегда, поэтому проверенные uuid не перезапрашиваем.
  Future<void> syncPprCompletedByMe() async {
    final Set<String> known = {};
    for (final ppr in activePprs) {
      known.addAll(ppr.completedInspectionUuids);
    }
    // Осмотры закрытых ППР из кэша выкидываем, чтобы он не рос вечно.
    final Set<String> mine = _pprCompletedByMe.intersection(known);
    final Set<String> checked = _pprCompletedByMeChecked.intersection(known);

    for (final uuid in known.difference(checked)) {
      try {
        final task = await api.getTaskByUuid(uuid);
        checked.add(uuid);
        if (task != null && isTaskMine(task)) {
          mine.add(uuid);
        }
      } catch (e) {
        print('Failed to load completed PPR inspection $uuid: $e');
      }
    }

    _pprCompletedByMe = mine;
    _pprCompletedByMeChecked = checked;
    await stringBox.put(
        DataProvider.pprCompletedByMeCacheKey,
        jsonEncode({
          'mine': mine.toList(),
          'checked': checked.toList(),
        }));
  }

  /// Осмотры задач актуальных ППР, которых нет среди уже загруженных [have].
  ///
  /// Общая выборка ([TaskApi.getCurrentTasks]) отдаёт осмотр только пока не
  /// вышел его срок, а задача ППР актуальна, пока ППР не закрыт, — поэтому
  /// такие осмотры берём поштучно по uuid из состава ППР.
  Future<List<Task>> loadPprInspections(Set<String> have) async {
    final Set<String> missing = {};
    for (final ppr in activePprs) {
      for (final uuid in ppr.inspectionUuids) {
        if (!have.contains(uuid) && !isTaskClosedLocally(uuid)) {
          missing.add(uuid);
        }
      }
    }
    final List<Task> tasks = [];
    for (final uuid in missing) {
      try {
        final task = await api.getTaskByUuid(uuid);
        if (task != null && task.resultStatus != 'closed') {
          tasks.add(task);
        }
      } catch (e) {
        print('Failed to load PPR inspection $uuid: $e');
      }
    }
    return tasks;
  }

  /// Добавляет недостающие осмотры ППР в ящик задач, не трогая остальные.
  /// Нужен там, где перечитывать весь список задач ради ППР незачем
  /// (главный экран).
  Future<void> syncPprInspections() async {
    final have = taskBox.keys.map((key) => key.toString()).toSet();
    for (final task in await loadPprInspections(have)) {
      await taskBox.put(task.uuid, task);
    }
  }

  /// Синхронизация оперативных справочников.
  ///
  /// Загрузки идут параллельно, а не одна за другой: между собой они
  /// независимы — разные эндпоинты, разные боксы. Последовательный проход
  /// складывал время всех, и на медленной сети кнопка «Синхронизировать
  /// данные» думала минутами. Каждая из них уже глотает свою ошибку и
  /// логирует, так что `Future.wait` не оборвётся из-за одной неудачной.
  ///
  /// **Исключение — пара ППР → задачи.** [syncTasks] по составу ППР догружает
  /// его осмотры и пишет всё в ящик задач одной операцией, поэтому [syncPpr]
  /// обязан завершиться раньше. Эти двое идут последовательно, но параллельно
  /// со всем остальным.
  ///
  /// **Каталога ЗИП здесь намеренно нет.** Он на порядок больше остальных
  /// справочников (десятки тысяч позиций — это сотни последовательных
  /// страниц), а меняется реже всех. Раньше он ехал вместе со всеми, и любое
  /// действие обходчика — вход в «Задачи», нажатие «Сканер», отправка
  /// осмотра — тянуло весь каталог, хотя нужен он только в разделе ЗИП и в
  /// расходе по ремонту. Теперь его грузят те, кому он нужен:
  /// [ensureSparePartsLoaded] на входе в эти экраны и отдельный редкий проход
  /// в [startSyncing].
  Future mainSync() async {
    if (!GlobalState.isAuthorized) return;
    // Девять параллельных синхронизаций к недоступному серверу — самый
    // дорогой способ ничего не узнать: часть из них постраничные, и каждая
    // страница ждала своего таймаута. Пока стоит отметка недоступности, не
    // начинаем вовсе; снимет её пинг живости, когда связь вернётся.
    if (API.isServerKnownUnreachable) return;
    await Future.wait([
      syncInventory(),
      syncPpr().then((_) => syncTasks()),
      syncTypicalProblems(),
      syncPeriodicityRules(),
      syncUsageUnitTypes(),
      syncEquipmentStates(),
      syncConsumptionNorms(),
      syncMyRepairs(),
      syncCompany(),
      // Каталог ЗИП вернулся в общий проход — теперь он инкрементальный.
      // Исключали его, когда каждый проход перекачивал десятки тысяч позиций
      // сотнями страниц; сейчас в устоявшемся состоянии это один запрос с
      // пустым ответом. За это остатки на складе перестали ждать: раньше они
      // обновлялись раз в десять минут фоновым тиком или вручную в разделе
      // ЗИП, и в расходе по ремонту обходчик видел вчерашние числа.
      //
      // Полным проход бывает только на первом заходе и после оборванной
      // записи — то есть худший случай остался прежним, но разовым.
      syncSpareParts(),
    ]);
    // Отметку ставим после всех: она значит «справочники обновлены», а не
    // «начали обновлять».
    await saveLastSyncDate();
  }

  /// Все очереди отправки пусты — гонять по ним проход незачем.
  bool get _outboxIsEmpty =>
      scanBox.isEmpty &&
      scanPendingBox.isEmpty &&
      scanUsageBox.isEmpty &&
      scanUsagePendingBox.isEmpty &&
      periodicTaskBox.isEmpty &&
      periodicTaskPendingBox.isEmpty &&
      pendingRepairBox.isEmpty &&
      pendingRepairUpdateBox.isEmpty;

  /// Задержки цикла отправки: обычная и те, на которые он отходит, пока
  /// сервер недоступен.
  ///
  /// Без бэкоффа цикл долбился в недоступный сервер каждые пять секунд весь
  /// день: пять проходов по очередям, каждый со своим ожиданием соединения.
  /// Данные от этого не уезжают быстрее — уезжают они, когда связь вернётся,
  /// а до тех пор проверять чаще раза в минуту незачем.
  static const List<int> _outboxBackoffSeconds = [5, 15, 60];

  void startScanSyncing() {
    Future.sync(() async {
      var backoff = 0;
      while (true) {
        await Future.delayed(
          Duration(seconds: _outboxBackoffSeconds[backoff]),
        );
        // Сервер только что не отозвался — расходимся сразу, не трогая сеть,
        // и в следующий раз просыпаемся реже.
        if (API.isServerKnownUnreachable) {
          if (backoff < _outboxBackoffSeconds.length - 1) backoff++;
          continue;
        }
        backoff = 0;
        // Без авторизации не отправляем ничего.
        //
        // Цикл заводится в `main()` и крутится всё время жизни приложения —
        // в том числе до входа и после выхода. Без этой проверки методы API
        // бросали бы `Exception('Not authenticated')`, а очередь принимала
        // бы это за отказ сервера по существу: осмотр помечался отклонённым
        // и больше не отправлялся сам, хотя с ним всё в порядке. У очереди
        // ремонтов ровно та же чувствительность, поэтому проверка стоит
        // здесь, до всех пяти проходов, а не в каждом по отдельности.
        if (!GlobalState.isAuthorized) continue;
        // Ранний выход: очереди почти всегда пусты, а без этой проверки
        // каждые 5 секунд пять методов читали свои боксы вхолостую — всё
        // время работы приложения.
        if (_outboxIsEmpty) continue;
        await syncScans();
        await syncUsageScans();
        await syncPeriodicTasks();
        await syncPendingRepairs();
        await syncPendingRepairUpdates();
      }
    });
  }

  void startSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        if (await GlobalState.hasConnectionToServer) {
          // Отдельного редкого прохода по каталогу ЗИП больше нет: он внутри
          // mainSync и стоит один запрос.
          await mainSync();
        }
      }
    });
  }

  /// Ручная синхронизация (кнопка «Синхронизировать данные»): справочники +
  /// осмотры. Возвращает результат; UI-диалоги — на стороне вызывающего.
  Future<SyncResult> syncDataAndScans() async {
    // Кнопку нажали руками — отметку недоступности забываем и идём в сеть
    // честно: обходчик мог только что дойти до места, где связь есть.
    API.retryConnectionNow();
    // Второй вход в очереди, помимо вечного цикла, — и та же причина
    // проверять авторизацию: без токена отправка не отказ, а бессмыслица.
    if (!GlobalState.isAuthorized || !await GlobalState.hasConnectionToServer) {
      return SyncResult.noConnection;
    }
    // Черновики ремонтов отправляем до справочников, а не после: иначе
    // syncMyRepairs перекачал бы список ещё без только что созданного ремонта,
    // и обходчик не увидел бы его до следующего цикла.
    await syncPendingRepairs();
    await syncPendingRepairUpdates();
    // Осмотры уезжают параллельно со справочниками: очереди пишут в свои
    // боксы и на загрузку справочников не влияют, а по очереди это было
    // сложением двух самых долгих частей.
    final scansWas = scanBox.length;
    await Future.wait([
      mainSync(),
      // Каталог ЗИП обновляем только здесь и в редком фоновом проходе: это
      // единственное место, где обходчик сам попросил обновить всё и готов
      // подождать ответа. Из `mainSync` он убран, чтобы не ехать за каждым
      // нажатием «Сканер» и входом в «Задачи».
      syncSpareParts(),
      if (scansWas > 0) syncScans(),
    ]);
    if (pendingRepairBox.isNotEmpty || pendingRepairUpdateBox.isNotEmpty) {
      return SyncResult.repairsFailed;
    }
    if (scansWas == 0) {
      return SyncResult.allSynced;
    }
    return scanBox.isEmpty ? SyncResult.scansSynced : SyncResult.scansFailed;
  }
}
