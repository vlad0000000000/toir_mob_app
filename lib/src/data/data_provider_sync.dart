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
  /// Вызывают экраны, которым каталог нужен: раздел ЗИП, список ремонтов и
  /// карточка ремонта (подбор позиций и остатки в расходе). В [mainSync]
  /// каталога больше нет, поэтому у обходчика, который ни разу не заходил в
  /// эти экраны, он пуст — и подобрать позицию в расходе было бы не из чего.
  ///
  /// Ничего не ждёт, если каталог уже загружен: это дешёвая проверка на
  /// входе в экран, а не обновление. Освежает его фоновый цикл и жест
  /// «потянуть вниз» в самом разделе ЗИП.
  Future<void> ensureSparePartsLoaded() async {
    if (spareParts.isNotEmpty) return;
    await syncSpareParts();
  }

  Future<bool> _syncSparePartsImpl() async {
    _isLoading = true;

    try {
      final spareParts = await loadAllSpareParts();
      // Сортируем один раз здесь, а не на каждый ввод символа в поиске:
      // на каталоге в десятки тысяч позиций сортировка в build была бы
      // самой дорогой операцией экрана. Порядок переживает перезапуск —
      // Hive отдаёт значения в порядке добавления.
      spareParts.sort((a, b) => a.name.compareTo(b.name));
      _spareParts = spareParts;
      _rebuildSparePartIndex();
      await sparePartBox.clear();
      await sparePartBox.addAll(_spareParts);
      await saveSparePartsSyncDate();
      return true;
    } catch (e) {
      print('Failed sync spare parts: $e');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncMyRepairs() async {
    _isLoading = true;

    try {
      _repairs = await loadAllActiveRepairs();
      await repairBox.clear();
      // Ключ — uuid, а не автоинкремент: так отдельный ремонт можно обновить
      // точечно (см. DataProvider.upsertRepair), не перекачивая весь список.
      await repairBox
          .putAll({for (final repair in _repairs) repair.uuid: repair});
      _refreshActiveRepairsCount();
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
      await taskBox.clear();
      await taskBox.putAll(tasksDict);
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
        if (!have.contains(uuid) &&
            !DataProvider.closedTasks.containsKey(uuid)) {
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
    await Future.wait([
      syncInventory(),
      syncPpr().then((_) => syncTasks()),
      syncTypicalProblems(),
      syncPeriodicityRules(),
      syncUsageUnitTypes(),
      syncEquipmentStates(),
      syncMyRepairs(),
      syncCompany(),
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

  void startScanSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 5));
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

  /// Как часто фоновый цикл обновляет каталог ЗИП — раз в 10 проходов, то
  /// есть примерно раз в 10 минут.
  ///
  /// Каждую минуту его гонять незачем: это сотни последовательных страниц и
  /// полная перезапись бокса ради справочника, который меняется куда реже
  /// задач и осмотров. Совсем не обновлять тоже нельзя — остатки на складе
  /// должны подтягиваться сами, без похода в раздел ЗИП.
  static const int _sparePartsSyncEveryTicks = 10;

  void startSyncing() {
    Future.sync(() async {
      var tick = 0;
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        if (await GlobalState.hasConnectionToServer) {
          await mainSync();
          tick++;
          if (tick % _sparePartsSyncEveryTicks == 0) {
            await syncSpareParts();
          }
        }
      }
    });
  }

  /// Ручная синхронизация (кнопка «Синхронизировать данные»): справочники +
  /// осмотры. Возвращает результат; UI-диалоги — на стороне вызывающего.
  Future<SyncResult> syncDataAndScans() async {
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
