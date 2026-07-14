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

  /// Синхронизирует членство периодических задач в актуальных ППР.
  /// Ошибку глотаем (как и остальные sync-методы) — при сбое остаётся
  /// последний закэшированный набор из `stringBox`.
  ///
  /// При выключенном [FeatureFlags.pprEnabled] не ходит в сеть: на проде
  /// эндпоинтов ППР нет.
  Future<void> syncPpr() async {
    if (!FeatureFlags.pprEnabled) return;
    _isLoading = true;
    try {
      final uuids = await api.getActivePprPeriodicTaskUuids();
      _pprPeriodicTaskUuids = uuids;
      await stringBox.put('ppr_periodic_task_uuids', uuids.join(','));
    } catch (e) {
      print('Failed sync PPR: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future mainSync() async {
    if (GlobalState.isAuthorized) {
      await syncInventory();
      await syncTasks();
      await syncPpr();
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
