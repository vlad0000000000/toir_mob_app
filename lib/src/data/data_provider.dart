import 'package:hive_ce/hive.dart';
import '../../global_state.dart';
import '../../src/http/api.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Task> taskBox;
  final Box<InventoryRecord> inventoryBox;
  final Box<Scan> scanBox;
  final Box<Scan> scanUsageBox;
  final Box<Scan> scanPendingBox;
  final Box<Scan> scanUsagePendingBox;
  final Box<Session> sessionBox;
  final Box<TypicalProblem> typicalProblemBox;
  final Box<PeriodicityRule> periodicityRuleBox;
  final Box<UsageUnit> usageUnitBox;
  final Box<String> stringBox;

  DataProvider(
      {required this.api,
      required this.userBox,
      required this.inventoryBox,
      required this.scanBox,
      required this.scanUsageBox,
      required this.scanPendingBox,
      required this.scanUsagePendingBox,
      required this.sessionBox,
      required this.taskBox,
      required this.typicalProblemBox,
      required this.periodicityRuleBox,
      required this.stringBox,
      required this.usageUnitBox}) {
    _users = userBox.values.toList();
    _inventoryRecords = inventoryBox.values.toList();
    _typicalProblems = typicalProblemBox.values.toList();
    _periodicityRules = periodicityRuleBox.values.toList();
    _usageUnits = usageUnitBox.values.toList();
    _currentSession = sessionBox.get('current_session');
  }

  List<User> _users = [];
  List<InventoryRecord> _inventoryRecords = [];
  List<TypicalProblem> _typicalProblems = [];
  List<PeriodicityRule> _periodicityRules = [];
  List<UsageUnit> _usageUnits = [];
  bool _isLoading = false;

  List<User> get users => _users;

  List<InventoryRecord> get inventoryRecords => _inventoryRecords;

  List<TypicalProblem> get typicalProblems => _typicalProblems;

  List<PeriodicityRule> get periodicityRules => _periodicityRules;

  List<UsageUnit> get usageUnits => _usageUnits;

  Session? get currentSession => _currentSession;
  Session? _currentSession;

  bool get isLoading => _isLoading;

  saveLastSyncDate() async {
    await stringBox.put('last_sync_date', DateTime.now().toString());
  }

  String getLastSyncDate() {
    var date = stringBox.get('last_sync_date');
    if (date == null) {
      return '';
    }
    return date;
  }

  addUser(User user) async {
    await userBox.put(user.username, user);
    _users = userBox.values.toList();
  }

  addScan(Scan scan) async {
    await scanBox.put(scan.key(), scan);
  }

  addUsageScan(Scan scan) async {
    await scanUsageBox.put(scan.key(), scan);
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

  Future<List<UsageUnit>> loadAllUsageUnitTypes() async {
    List<UsageUnit> all = [];
    List<UsageUnit> notAll = await api.getUsageUnitTypes();
    for (var usageUnit in notAll) {
      all.add(usageUnit);
    }
    return all;
  }

  Future<User?> login(login, password) async {
    User? currentUser = null;
    try {
      currentUser = await api.login(login, password);
      GlobalState.authUser = currentUser;
    } on Exception catch (_) {}

    if (currentUser == null) {
      for (var user in users) {
        if (user.username == login && user.password == password) {
          currentUser = user;
        }
      }
    }

    // only walkers allowed
    if (currentUser != null) {
      if (currentUser.role != 'walker') {
        currentUser = null;
      }
    }

    if (currentUser != null) {
      var currentUserMe = await api.me();
      currentUser.effectiveRole = currentUserMe.effectiveRole;
      currentUser.customRoleId = currentUserMe.customRoleId;
      addUser(currentUser);
    }
    return currentUser;
  }

  Future<List<Task>> loadAllTasks() async {
    int limit = 50;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll =
          await api.getCurrentTasks(limit: limit, offset: offset);
      for (var task in notAll) {
        all.add(task);
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

  void startScanSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 5));
        await syncScans();
        await syncUsageScans();
      }
    });
  }

  Future mainSync() async {
    await syncInventory();
    await syncTypicalProblems();
    await syncPeriodicityRules();
    await syncUsageUnitTypes();
    await saveLastSyncDate();
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

  String getUsageUnitDisplayName(String value) {
    return _usageUnits
        .where((unit) => unit.value == value)
        .toList()[0]
        .displayName;
  }

  String getUsageUnitShortName(String value) {
    return _usageUnits
        .where((unit) => unit.value == value)
        .toList()[0]
        .shortName;
  }

  Future<void> syncUsageScans() async {
    final scans = scanUsageBox.values.toList();
    // print('sync scans ' + scanBox.values.length.toString());
    for (final scan in scans) {
      try {
        await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox
            .put(scan.key(), scan);
        if (await api.updateUsageParameter(scan.equipmentUuid!,
            scan.usageParameterUuid!, scan.usageParameterValue!)) {
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
    final scans = scanBox.values.toList();
    // print('sync scans ' + scanBox.values.length.toString());
    for (final scan in scans) {
      try {
        await GlobalState.dataProvider.scanBox.delete(scan.key());
        await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanPendingBox.put(scan.key(), scan);
        if (await api.sendScan(scan)) {
          await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanBox.delete(scan.key());
        } else {
          await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanBox.delete(scan.key());
          await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
        }
      } catch (e) {
        await GlobalState.dataProvider.scanBox.delete(scan.key());
        await GlobalState.dataProvider.scanPendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanBox.put(scan.key(), scan);
        print('Error syncing data: $e');
      }
    }
  }
}
