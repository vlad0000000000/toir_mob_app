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
      await taskBox.clear();
      Map<String, Task> tasksDict = {};
      for (var task in tasks) {
        tasksDict[task.uuid] = task;
      }
      await taskBox.putAll(tasksDict);
      // await taskBox.addAll(tasks);
    } catch (e, stack) {
      print('Error syncing tasks: $e');
      print(stack);
    } finally {
      _isLoading = false;
    }
  }

  /// Полная синхронизация справочников.
  ///
  /// Все загрузки идут параллельно, а не одна за другой: между собой они
  /// независимы — разные эндпоинты, разные боксы, ни одна не использует
  /// результат другой. Последовательный проход складывал время всех десяти,
  /// и на медленной сети кнопка «Синхронизировать данные» думала минутами.
  ///
  /// Каждая из них уже глотает свою ошибку и логирует, так что `Future.wait`
  /// не оборвётся из-за одной неудачной — остальные догрузятся.
  Future mainSync() async {
    if (!GlobalState.isAuthorized) return;
    await Future.wait([
      syncInventory(),
      syncTasks(),
      syncTypicalProblems(),
      syncPeriodicityRules(),
      syncUsageUnitTypes(),
      syncEquipmentStates(),
      syncSpareParts(),
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
          await mainSync();
          // await syncScans();
        }
      }
    });
  }

  /// Ручная синхронизация (кнопка «Синхронизировать данные»): справочники +
  /// осмотры. Возвращает результат; UI-диалоги — на стороне вызывающего.
  Future<SyncResult> syncDataAndScans() async {
    if (!await GlobalState.hasConnectionToServer) {
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
