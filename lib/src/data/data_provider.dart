import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../../global_state.dart';
import '../../src/http/api.dart';
import '../../src/model/company.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../model/usage_update.dart';
import '../exceptions/login_exceptions.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Task> taskBox;
  final Box<InventoryRecord> inventoryBox;
  final Box<Scan> scanBox;
  final Box<UsageUpdate> scanUsageBox;
  final Box<Scan> scanPendingBox;
  final Box<UsageUpdate> scanUsagePendingBox;
  final Box<PeriodicTaskRequest> periodicTaskBox;
  final Box<PeriodicTaskRequest> periodicTaskPendingBox;
  final Box<Session> sessionBox;
  final Box<TypicalProblem> typicalProblemBox;
  final Box<PeriodicityRule> periodicityRuleBox;
  final Box<UsageUnit> usageUnitBox;
  final Box<Company> companyBox;
  final Box<EquipmentState> equipmentStateBox;
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
      required this.usageUnitBox,
      required this.companyBox,
      required this.equipmentStateBox,
      required this.periodicTaskBox,
      required this.periodicTaskPendingBox}) {
    _users = userBox.values.toList();
    _inventoryRecords = inventoryBox.values.toList();
    _typicalProblems = typicalProblemBox.values.toList();
    _periodicityRules = periodicityRuleBox.values.toList();
    _usageUnits = usageUnitBox.values.toList();
    _company = companyBox.get('company');
    _currentSession = sessionBox.get('current_session');
    _equipmentState = equipmentStateBox.get('equipment_state');
  }

  List<User> _users = [];
  List<InventoryRecord> _inventoryRecords = [];
  List<TypicalProblem> _typicalProblems = [];
  List<PeriodicityRule> _periodicityRules = [];
  List<UsageUnit> _usageUnits = [];
  Company? _company;
  EquipmentState? _equipmentState;
  bool _isLoading = false;

  List<User> get users => _users;

  List<InventoryRecord> get inventoryRecords => _inventoryRecords;

  List<TypicalProblem> get typicalProblems => _typicalProblems;

  List<PeriodicityRule> get periodicityRules => _periodicityRules;

  List<UsageUnit> get usageUnits => _usageUnits;

  Company? get company => _company;

  EquipmentState? get equipmentState => _equipmentState;

  Session? get currentSession => _currentSession;
  Session? _currentSession;

  bool get isLoading => _isLoading;

  saveLastSyncDate() async {
    final dateFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
    await stringBox.put('last_sync_date', dateFormat.format(DateTime.now()));
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

  static Map<String, String> closedTasks = {};

  addScan(Scan scan) async {
    await scanBox.put(scan.key(), scan);
    if (scan.taskUuid != null) {
      final taskUuid = scan.taskUuid!;
      final task = taskBox.get(taskUuid);
      final periodicTitle = task?.periodicTask?.title ?? '';
      if (scan.periodicTaskUuid != null &&
          scan.periodicTaskUuid!.isNotEmpty &&
          periodicTitle.contains('Техническое обслуживание')) {
        await stringBox.put('maintenance_task_$taskUuid', '1');
      }
      closedTasks[taskUuid] = taskUuid;
      taskBox.delete(taskUuid);
    }
  }

  addUsageScan(UsageUpdate scan) async {
    await scanUsageBox.put(scan.key(), scan);
  }

  addPeriodicTask(PeriodicTaskRequest taskRequest) async {
    await periodicTaskBox.put(taskRequest.key(), taskRequest);
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
    bool apiLoginFailed = false;
    
    try {
      currentUser = await api.login(login, password);
      GlobalState.authUser = currentUser;
    } on InvalidCredentialsException {
      // Сервер вернул, что учетные данные неверны - не проверяем локальных пользователей
      rethrow;
    } on NoConnectionException {
      // Нет соединения с сервером - пробуем локальных пользователей
      apiLoginFailed = true;
    } on SocketException catch (_) {
      // Ошибка соединения с сервером - пробуем локальных пользователей
      apiLoginFailed = true;
    } on HttpException catch (_) {
      // Ошибка HTTP соединения - пробуем локальных пользователей
      apiLoginFailed = true;
    } on Exception catch (e) {
      // Проверяем, не является ли это ошибкой соединения
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('Timeout')) {
        // Ошибка соединения - пробуем локальных пользователей
        apiLoginFailed = true;
      } else {
        // Для других исключений пробуем локальных пользователей
        apiLoginFailed = true;
      }
    }

    // Если API логин не удался из-за отсутствия соединения, пробуем локальных пользователей
    if (apiLoginFailed && currentUser == null) {
      for (var user in users) {
        if (user.username == login && user.password == password) {
          currentUser = user;
          break;
        }
      }

      // Если не нашли локального пользователя, выбрасываем соответствующее исключение
      if (currentUser == null) {
        // Если была ошибка соединения, выбрасываем NoConnectionException
        // так как мы не можем проверить учетные данные на сервере
        throw NoConnectionException();
      }
    }

    // Проверка на роль walker должна быть после успешного логина
    if (currentUser != null) {
      // only walkers allowed
      if (currentUser.role != 'walker') {
        throw WalkerOnlyException();
      }
    }

    if (currentUser != null) {
      // Пытаемся получить дополнительную информацию о пользователе через API
      // Если это не удается из-за отсутствия соединения, это не критично
      User? currentUserMe = null;
      try {
        currentUserMe = await api.me();
        currentUser.effectiveRole = currentUserMe.effectiveRole;
        currentUser.customRoleId = currentUserMe.customRoleId;
        currentUser.uuid = currentUserMe.uuid;
        addUser(currentUser);
      } catch (e) {
        // Если не удалось получить информацию о пользователе, но логин прошел успешно
        // Это не критично, если мы используем локального пользователя
        // Но если это был API логин, возможно, это проблема соединения
        if (!apiLoginFailed && (e is SocketException || e is HttpException)) {
          // Если это был успешный API логин, но не удалось получить me(), 
          // это может быть проблема соединения, но пользователь уже авторизован
          // Поэтому просто продолжаем
        }
        // Для других ошибок просто продолжаем с текущим пользователем
      }
    }
    return currentUser;
  }

  Future<List<Task>> loadAllOpenTasks() async {
    int limit = 50;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll =
          await api.getCurrentOpenTasks(limit: limit, offset: offset);
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

  void updateInventoryRecords() async {
    _inventoryRecords = inventoryBox.values.toList();
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

  Future mainSync() async {
    if (GlobalState.isAuthorized) {
      await syncInventory();
      await syncTypicalProblems();
      await syncPeriodicityRules();
      await syncTasks();
      await syncUsageUnitTypes();
      await syncEquipmentStates();
      await saveLastSyncDate();
      await syncCompany();
    }
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
    final tasksInScans = {};
    for (var scan in scanBox.values.toList()) {
      tasksInScans[scan.taskUuid] = scan.taskUuid;
    }
    for (var scan in scanPendingBox.values.toList()) {
      tasksInScans[scan.taskUuid] = scan.taskUuid;
    }
    return taskBox.values
        .where((task) => task.equipmentUuid == machineUUID)
        .where((x) {
      if (tasksInScans.containsKey(x.uuid) || closedTasks.containsKey(x.uuid)) {
        return false;
      }
      if (GlobalState.authUser == null) {
        return false;
      }
      if (x.resultStatus == "scheduled") {
        return x.periodicTask!.customRoles.where((x) {
              return x.id == GlobalState.authUser!.customRoleId;
            }).length >
            0;
      } else if (x.resultStatus == "open") {
        return x.responsibleUser!.uuid == GlobalState.authUser!.uuid;
      } else {
        return false;
      }
    }).toList();
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

  String? getEquipmentStateName(String stateCode) {
    return _equipmentState?.getStateName(stateCode);
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
    // Проверяем pending сканы - возвращаем в scanBox те, что прождали 60 секунд
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
            // Прошло 60 секунд - возвращаем скан в scanBox для повторной попытки
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
      try {
        // Перемещаем скан в pending перед отправкой
        await scanBox.delete(scan.key());
        await scanPendingBox.put(scan.key(), scan);

        // Сохраняем timestamp текущей попытки
        final timestampKey = 'scan_pending_${scan.key()}';
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
          // Неуспешно - оставляем в pending с timestamp, вернется через 60 секунд
          // Ничего не делаем, скан уже в scanPendingBox с timestamp
        }
      } catch (e) {
        // При ошибке также оставляем в pending с timestamp
        // Убеждаемся, что скан в scanPendingBox и timestamp сохранен
        await scanPendingBox.put(scan.key(), scan);
        final timestampKey = 'scan_pending_${scan.key()}';
        await stringBox.put(timestampKey, now.toString());
        print('Error syncing data: $e');
      }
    }
  }

  Future<void> syncPeriodicTasks() async {
    // Проверяем pending задачи - возвращаем в periodicTaskBox те, что прождали 60 секунд
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
