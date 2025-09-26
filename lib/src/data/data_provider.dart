import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/http/api.dart';
import 'package:qr_machine_scanner/src/model/inventory_scan.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/session.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';
import 'package:qr_machine_scanner/src/model/typical_problem.dart';
import 'package:qr_machine_scanner/src/model/periodicity_rule.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Task> taskBox;
  final Box<InventoryRecord> inventoryBox;
  final Box<Scan> scanBox;
  final Box<Scan> scanPendingBox;
  final Box<Session> sessionBox;
  final Box<TypicalProblem> typicalProblemBox;
  final Box<PeriodicityRule> periodicityRuleBox;

  DataProvider(
      {required this.api,
      required this.userBox,
      required this.inventoryBox,
      required this.scanBox,
      required this.scanPendingBox,
      required this.sessionBox,
      required this.taskBox,
      required this.typicalProblemBox,
      required this.periodicityRuleBox}) {
    _users = userBox.values.toList();
    _inventoryRecords = inventoryBox.values.toList();
    _typicalProblems = typicalProblemBox.values.toList();
    _periodicityRules = periodicityRuleBox.values.toList();
    _currentSession = sessionBox.get('current_session');
  }

  List<User> _users = [];
  List<InventoryRecord> _inventoryRecords = [];
  List<TypicalProblem> _typicalProblems = [];
  List<PeriodicityRule> _periodicityRules = [];
  bool _isLoading = false;

  List<User> get users => _users;

  List<InventoryRecord> get inventoryRecords => _inventoryRecords;

  List<TypicalProblem> get typicalProblems => _typicalProblems;

  List<PeriodicityRule> get periodicityRules => _periodicityRules;

  Session? get currentSession => _currentSession;
  Session? _currentSession;

  bool get isLoading => _isLoading;

  addUser(User user) async {
    await userBox.put(user.username, user);
    _users = userBox.values.toList();
  }

  addScan(Scan scan) async {
    await scanBox.put(scan.key(), scan);
  }

  setCurrentSession(session) async {
    await sessionBox.put('current_session', session);
    _currentSession = session;
  }

  Future<List<InventoryRecord>> loadAllInventory() async {
    int limit = 100;
    int offset = 0;
    List<InventoryRecord> all = [];
    while (true) {
      List<InventoryRecord> notAll =
          // await api.getInventoryRecords(limit: limit, offset: offset);
          await api.getEquipment(limit: limit, offset: offset);
      for (var inventoryRecord in notAll) {
        all.add(inventoryRecord);
      }
      if (notAll.isEmpty) {
        break;
      }
      offset += limit;
    }
    return all;
  }

  Future<List<TypicalProblem>> loadAllTypicalProblems() async {
    int limit = 50;
    int offset = 0;
    List<TypicalProblem> all = [];
    while (true) {
      List<TypicalProblem> notAll =
          await api.getTypicalProblems(limit: limit, offset: offset);
      for (var typicalProblem in notAll) {
        all.add(typicalProblem);
      }
      if (notAll.isEmpty) {
        break;
      }
      offset += limit;
    }
    return all;
  }

  Future<List<PeriodicityRule>> loadAllPeriodicityRules() async {
    List<PeriodicityRule> all = [];
    List<PeriodicityRule> notAll = await api.getPeriodicityRules();
    for (var periodicityRule in notAll) {
      all.add(periodicityRule);
    }
    return all;
  }

  Future<List<Task>> loadAllTasks() async {
    int limit = 50;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll =
          await api.getCurrentTasks(limit: limit, offset: offset);
      for (var typicalProblem in notAll) {
        all.add(typicalProblem);
      }
      if (notAll.isEmpty) {
        break;
      }
      offset += limit;
    }
    return all;
  }

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
      _inventoryRecords = await loadAllInventory();
      await inventoryBox.clear();
      await inventoryBox.addAll(_inventoryRecords);
    } catch (e) {
      print('Failed sync inventory: $e');
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

  void startScanSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 5));
        await syncScans();
      }
    });
  }

  void startSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        if (await GlobalState.hasConnectionToServer) {
          await syncInventory();
          await syncTypicalProblems();
          await syncPeriodicityRules();
          // await syncScans();
        }
      }
    });
  }

  // Метод синхронизации задач
  Future<void> syncTasks() async {
    _isLoading = true;
    try {
      List<Task> tasks = await loadAllTasks();
      await taskBox.clear();
      await taskBox.addAll(tasks);
    } catch (e) {
      print('Error syncing tasks: $e');
    } finally {
      _isLoading = false;
    }
  }

  String periodRealName(String periodName) {
    return periodicityRuleBox.values
        .where((x) => x.value == periodName)
        .toList()[0]
        .displayName;
  }

  List<TypicalProblem> getTypicalProblemsForMachine(String machineUUID) {
    return typicalProblemBox.values
        .where((problem) => problem.equipmentUUID == machineUUID)
        .toList();
  }

  // Получение задач для машины
  List<Task> getTasksForMachine(String machineUUID) {
    return taskBox.values
        .where((task) => task.equipmentUuid == machineUUID)
        .toList();
  }

  Future<void> syncScans() async {
    final scans = scanBox.values.toList();
    // print('sync scans ' + scanBox.values.length.toString());
    for (final scan in scans) {
      await GlobalState.dataProvider.scanBox.delete(scan.key());
      await GlobalState.dataProvider.scanPendingBox.put(scan.key(), scan);
      try {
        if (await api.sendScan(scan)) {
          await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
          // await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
        } else {
          await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
        }
      } catch (e, stack) {
        await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
        print('Error syncing data: $e');
      }
    }
  }
}
