import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
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
import '../../src/model/ppr.dart';
import '../model/usage_update.dart';
import '../exceptions/app_exceptions.dart';
import '../feature_flags.dart';

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
    _loadCachedPprs();
  }

  /// Восстанавливает актуальные ППР из кэша (`stringBox`), чтобы кнопка
  /// «ППР» и группа «ППР» работали до первой синхронизации и офлайн.
  void _loadCachedPprs() {
    final completed = stringBox.get(pprCompletedByMeCacheKey);
    if (completed != null && completed.isNotEmpty) {
      try {
        final raw = jsonDecode(completed) as Map<String, dynamic>;
        Set<String> read(String key) =>
            ((raw[key] as List<dynamic>?) ?? const [])
                .map((e) => e as String)
                .toSet();
        _pprCompletedByMe = read('mine');
        _pprCompletedByMeChecked = read('checked');
      } catch (e) {
        print('Failed to read PPR progress cache: $e');
      }
    }
    final cached = stringBox.get(pprCacheKey);
    if (cached == null || cached.isEmpty) return;
    try {
      final List<dynamic> raw = jsonDecode(cached);
      setActivePprs(raw
          .map((e) => Ppr.fromJson(e as Map<String, dynamic>))
          .toList());
    } catch (e) {
      print('Failed to read PPR cache: $e');
    }
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

  /// Ключ кэша актуальных ППР в `stringBox`.
  static const String pprCacheKey = 'ppr_active';

  /// Ключ кэша осмотров ППР, закрытых текущим пользователем.
  static const String pprCompletedByMeCacheKey = 'ppr_completed_by_me';

  /// Актуальные (незакрытые) ППР. Наполняются в [syncPpr], кэшируются в
  /// `stringBox` для офлайна.
  List<Ppr> _activePprs = [];

  /// UUID периодических задач всех актуальных ППР — производное от
  /// [_activePprs], чтобы не пересобирать множество на каждую задачу списка.
  Set<String> _pprPeriodicTaskUuids = {};

  /// UUID осмотров всех актуальных ППР. Принадлежность задачи к ППР считаем
  /// именно по осмотру: у одной периодической задачи может быть и осмотр из
  /// состава ППР, и обычный периодический — второй в ППР не показываем.
  Set<String> _pprInspectionUuids = {};

  /// Осмотры выполненных задач ППР, закрытые текущим пользователем, и
  /// осмотры, по которым принадлежность уже выяснена (закрытый осмотр не
  /// меняется, перезапрашивать его незачем). Наполняются в
  /// [syncPprCompletedByMe], кэшируются в `stringBox`.
  Set<String> _pprCompletedByMe = {};
  Set<String> _pprCompletedByMeChecked = {};

  /// При выключенном [FeatureFlags.pprEnabled] раздел ППР не показывается
  /// вообще — даже при наличии старого кэша.
  List<Ppr> get activePprs =>
      FeatureFlags.pprEnabled ? _activePprs : const <Ppr>[];

  Set<String> get pprPeriodicTaskUuids => _pprPeriodicTaskUuids;

  /// Актуальные ППР, в которых текущему пользователю есть что делать, —
  /// то, что показывает экран ППР. Пустые ППР (все задачи чужие или уже
  /// выполнены) в списке не нужны.
  List<Ppr> pprsWithTasks() {
    final pprs = activePprs;
    if (pprs.isEmpty) return const <Ppr>[];
    // Один проход по задачам: собираем осмотры ППР, доступные пользователю.
    final tasksInScans = _scannedTaskUuids();
    final Set<String> available = {};
    for (final task in taskBox.values) {
      if (!_pprInspectionUuids.contains(task.uuid)) continue;
      if (!_isTaskAvailable(task, tasksInScans)) continue;
      available.add(task.uuid);
    }
    return pprs
        .where((ppr) => ppr.inspectionUuids.any(available.contains))
        .toList();
  }

  /// Признак для кнопки «ППР» на главном экране: есть ППР «В работе» (по ТЗ)
  /// и в нём есть задачи для текущего пользователя — иначе кнопка вела бы на
  /// пустой экран.
  bool get hasPprInProgressWithTasks =>
      pprsWithTasks().any((ppr) => ppr.isInProgress);

  void setActivePprs(List<Ppr> pprs) {
    _activePprs = pprs;
    _pprPeriodicTaskUuids = {
      for (final ppr in pprs) ...ppr.periodicTaskUuids,
    };
    _pprInspectionUuids = {
      for (final ppr in pprs) ...ppr.inspectionUuids,
    };
  }

  /// Входит ли периодическая задача в актуальный ППР. При выключенном
  /// [FeatureFlags.pprEnabled] всегда `false` — группа «ППР» не появляется
  /// даже при наличии старого кэша.
  bool isPeriodicTaskInPpr(String periodicTaskUuid) =>
      FeatureFlags.pprEnabled &&
      _pprPeriodicTaskUuids.contains(periodicTaskUuid);

  /// Актуальный ППР, в состав которого входит осмотр. Нужен, чтобы подписать
  /// группу именем конкретного ППР на экране задач оборудования.
  Ppr? pprForTask(Task task) {
    if (!FeatureFlags.pprEnabled) return null;
    if (!_pprInspectionUuids.contains(task.uuid)) return null;
    for (final ppr in activePprs) {
      if (ppr.inspectionUuids.contains(task.uuid)) return ppr;
    }
    return null;
  }

  /// Прогресс ППР для текущего пользователя: сколько его задач выполнено
  /// из скольких. Общий счётчик ППР обходчику бесполезен — задачи чужих
  /// ролей он не увидит никогда.
  ({int done, int total}) pprProgressForUser(Ppr ppr) {
    final done =
        ppr.completedInspectionUuids.where(_pprCompletedByMe.contains).length;
    return (done: done, total: done + getTasksForPpr(ppr.uuid).length);
  }

  /// Задача текущего пользователя: назначенная — по ответственному,
  /// периодическая — по роли. В отличие от [_isTaskAvailable] работает и для
  /// закрытых осмотров (нужно для счётчика выполненных задач ППР).
  bool isTaskMine(Task task) {
    final user = GlobalState.authUser;
    if (user == null) return false;
    final responsible = task.responsibleUser;
    if (responsible != null) return responsible.uuid == user.uuid;
    final roles = task.periodicTask?.customRoles ?? const [];
    return roles.any((role) => role.id == user.customRoleId);
  }

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
    final tasksInScans = _scannedTaskUuids();
    return taskBox.values
        .where((task) => task.equipmentUuid == machineUUID)
        .where((x) => _isTaskAvailable(x, tasksInScans))
        .toList();
  }

  /// Задачи актуального ППР, доступные текущему пользователю. Фильтр тот же,
  /// что и в [getTasksForMachine] — просто отбор идёт не по оборудованию, а
  /// по составу ППР (осмотры его периодических задач).
  List<Task> getTasksForPpr(String pprUuid) {
    final matched = activePprs.where((p) => p.uuid == pprUuid).toList();
    if (matched.isEmpty || matched.first.inspectionUuids.isEmpty) {
      return [];
    }
    final ppr = matched.first;
    final tasksInScans = _scannedTaskUuids();
    final tasks = taskBox.values
        .where((task) => ppr.inspectionUuids.contains(task.uuid))
        .where((task) => _isTaskAvailable(task, tasksInScans))
        .toList();
    tasks.sort((a, b) {
      final byEquipment = (a.periodicTask?.equipment.name ?? '')
          .toLowerCase()
          .compareTo((b.periodicTask?.equipment.name ?? '').toLowerCase());
      if (byEquipment != 0) return byEquipment;
      return (a.periodicTask?.title ?? '')
          .toLowerCase()
          .compareTo((b.periodicTask?.title ?? '').toLowerCase());
    });
    return tasks;
  }

  /// UUID осмотров, по которым уже есть скан (отправленный или в очереди) —
  /// такие задачи в списках не показываем.
  Map<String, String?> _scannedTaskUuids() {
    final Map<String, String?> tasksInScans = {};
    for (var scan in scanBox.values.toList()) {
      tasksInScans[scan.taskUuid ?? ''] = scan.taskUuid;
    }
    for (var scan in scanPendingBox.values.toList()) {
      tasksInScans[scan.taskUuid ?? ''] = scan.taskUuid;
    }
    return tasksInScans;
  }

  /// Показывать ли задачу текущему пользователю: не закрыта локально,
  /// периодическая — по его роли, назначенная — по ответственному.
  bool _isTaskAvailable(Task task, Map<String, String?> tasksInScans) {
    if (tasksInScans.containsKey(task.uuid) ||
        closedTasks.containsKey(task.uuid)) {
      return false;
    }
    if (GlobalState.authUser == null) {
      return false;
    }
    if (task.resultStatus == "scheduled") {
      // Осмотр без периодической задачи (её удалили) ролей не несёт —
      // показывать его некому. Раньше здесь падал `!`.
      final periodicTask = task.periodicTask;
      if (periodicTask == null) return false;
      return periodicTask.customRoles
              .where((role) => role.id == GlobalState.authUser!.customRoleId)
              .length >
          0;
    } else if (task.resultStatus == "open") {
      return task.responsibleUser?.uuid == GlobalState.authUser!.uuid;
    } else {
      return false;
    }
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
