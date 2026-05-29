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
import '../../src/model/responsible_user.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../model/usage_update.dart';
import '../exceptions/app_exceptions.dart';

part 'data_provider_remote.dart';
part 'data_provider_sync.dart';
part 'data_provider_outbox.dart';

/// Хранилище приложения (Hive-боксы + in-memory кэш). Сетевые загрузки,
/// фоновая синхронизация и офлайн-очереди вынесены в part-файлы
/// (`*_remote`, `*_sync`, `*_outbox`) как extension на [DataProvider].
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
  bool _isSyncingScans = false;

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

  static Map<String, String> closedTasks = {};

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

  void updateInventoryRecords() async {
    _inventoryRecords = inventoryBox.values.toList();
  }

  /// Отправляет смену состояния оборудования на сервер и обновляет
  /// локальную запись в Hive. Обработку ошибок (UI/снекбары) оставляем
  /// вызывающему — он ловит исключения этого метода.
  Future<void> updateEquipmentState(String equipmentUuid, String state) async {
    await api.updateEquipmentState(equipmentUuid, state);
    for (var key in inventoryBox.keys) {
      final record = inventoryBox.get(key);
      if (record != null && record.uuid == equipmentUuid) {
        await inventoryBox.put(key, record.copyWith(state: state));
        updateInventoryRecords();
        break;
      }
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
    // Demo mode: return predefined tasks without real data access
    if (machineUUID == 'demo-onboarding-conveyor') {
      final userUuid = GlobalState.authUser?.uuid ?? 'demo-user';
      return [
        Task(
          uuid: 'demo-task-inspection',
          resultStatus: 'open',
          targetType: 'check',
          periodicTask: null,
          equipmentUuid: machineUUID,
          roles: [],
          comment: 'Плановый технический осмотр конвейерной ленты',
          responsibleUser: ResponsibleUser(id: 0, uuid: userUuid),
          photos: [],
        ),
        Task(
          uuid: 'demo-task-lubrication',
          resultStatus: 'open',
          targetType: 'check',
          periodicTask: null,
          equipmentUuid: machineUUID,
          roles: [],
          comment: 'Смазка подшипников и направляющих роликов',
          responsibleUser: ResponsibleUser(id: 0, uuid: userUuid),
          photos: [],
        ),
      ];
    }
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
}
