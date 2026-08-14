part of 'data_provider.dart';

/// Результат ручной синхронизации (кнопка «Синхронизировать данные»).
enum SyncResult { noConnection, allSynced, scansSynced, scansFailed }

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
      List<Task> tasks = await loadAllTasks();
      for (var task in await loadAllOpenTasks()) {
        tasks.add(task);
      }
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

  Future mainSync() async {
    if (GlobalState.isAuthorized) {
      await syncInventory();
      // ППР — до задач: syncTasks по его составу догружает осмотры ППР
      // и пишет всё в ящик задач одной операцией.
      await syncPpr();
      await syncTasks();
      await syncTypicalProblems();
      await syncPeriodicityRules();
      await syncUsageUnitTypes();
      await syncEquipmentStates();
      await saveLastSyncDate();
      await syncCompany();
    }
  }

  void startScanSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 5));
        await syncScans();
        await syncUsageScans();
        await syncPeriodicTasks();
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
    await mainSync();
    final scansWas = scanBox.length;
    if (scansWas == 0) {
      return SyncResult.allSynced;
    }
    await syncScans();
    final scansNow = scanBox.length;
    if (scansNow == 0 && scansWas > 0) {
      return SyncResult.scansSynced;
    }
    return SyncResult.scansFailed;
  }
}
