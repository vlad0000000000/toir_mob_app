import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import '../../global_state.dart';
import '../../src/http/api.dart';
import '../../src/model/company.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/pending_repair.dart';
import '../../src/model/pending_repair_update.dart';
import '../../src/model/repair_conflict.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/repair.dart';
import '../../src/model/scan.dart';
import '../../src/model/session.dart';
import '../../src/model/spare_part.dart';
import '../../src/model/task.dart';
import '../../src/model/responsible_user.dart';
import '../../src/model/typical_problem.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/user.dart';
import '../../src/model/equipment_state.dart';
import '../../src/model/periodic_task_request.dart';
import '../model/usage_update.dart';
import '../exceptions/app_exceptions.dart';
import '../../strings.dart';
import '../repairs/repair_error_messages.dart';
import 'repair_photo_files.dart';

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
  final Box<SparePart> sparePartBox;
  final Box<Repair> repairBox;
  final Box<PendingRepair> pendingRepairBox;
  final Box<PendingRepairUpdate> pendingRepairUpdateBox;
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
      required this.sparePartBox,
      required this.repairBox,
      required this.pendingRepairBox,
      required this.pendingRepairUpdateBox,
      required this.periodicTaskBox,
      required this.periodicTaskPendingBox}) {
    _spareParts = sparePartBox.values.toList();
    _rebuildSparePartIndex();
    _repairs = repairBox.values.toList();
    _refreshActiveRepairsCount();
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
  List<SparePart> _spareParts = [];
  List<Repair> _repairs = [];
  Company? _company;
  EquipmentState? _equipmentState;
  bool _isLoading = false;
  bool _isSyncingScans = false;

  /// Идущий проход синхронизации справочника ЗИП. К нему присоединяются все,
  /// кто попросил синхронизацию, пока он не завершился.
  Future<bool>? _sparePartsSync;
  bool _isSyncingPendingRepairs = false;
  bool _isSyncingRepairUpdates = false;

  List<User> get users => _users;

  List<InventoryRecord> get inventoryRecords => _inventoryRecords;

  List<TypicalProblem> get typicalProblems => _typicalProblems;

  List<PeriodicityRule> get periodicityRules => _periodicityRules;

  List<UsageUnit> get usageUnits => _usageUnits;

  List<SparePart> get spareParts => _spareParts;

  /// Позиция справочника по uuid — за постоянное время.
  ///
  /// Индекс, а не перебор списка: остаток и единицу измерения спрашивают из
  /// `build` карточки ремонта, по разу на каждую строку расхода. На каталоге
  /// в десятки тысяч позиций это был полный проход на каждую строку и на
  /// каждый кадр — то есть сотни тысяч сравнений при нажатии «+».
  SparePart? sparePartByUuid(String uuid) => _sparePartsByUuid[uuid];

  Map<String, SparePart> _sparePartsByUuid = const {};

  /// Пересобирает индекс. Зовётся везде, где меняется [_spareParts].
  void _rebuildSparePartIndex() {
    _sparePartsByUuid = {for (final part in _spareParts) part.uuid: part};
  }

  /// Активные ремонты (открытые и на рассмотрении), доступные обходчику.
  /// Закрытые здесь не лежат: их тянет с сервера сам экран, в офлайн-кэш
  /// они не попадают.
  List<Repair> get repairs => _repairs;

  /// Счётчик активных ремонтов для плитки на главной.
  ///
  /// Именно [ValueNotifier], а не геттер: [DataProvider] не реактивный, и
  /// обычное число обновлялось бы на экране только при случайной
  /// перерисовке — после создания ремонта цифра появлялась бы с задержкой.
  /// Тот же приём, что у счётчика непрочитанных в `NotificationsService`.
  final ValueNotifier<int> activeRepairsCount = ValueNotifier<int>(0);

  /// Очередь упёрлась в истёкший токен.
  ///
  /// Очередь работает в фоне, вне экранов, поэтому сама показать диалог не
  /// может — вместо этого поднимает флаг, а список ремонтов и раздел
  /// «Сервис» его показывают. Данные при этом не трогаются: после повторного
  /// входа отправка продолжится с того же места.
  final ValueNotifier<bool> authExpired = ValueNotifier<bool>(false);

  void _refreshActiveRepairsCount() {
    // Черновики тоже активные ремонты — просто ещё не доехавшие. Не считать их
    // значило бы: обходчик создал ремонт в цеху, вернулся в меню, а счётчик
    // прежний, будто ничего не произошло.
    activeRepairsCount.value =
        _repairs.where((r) => r.isActive).length + pendingRepairBox.length;
  }

  /// Черновики ремонтов, ждущие отправки. Порядок — от новых к старым, как в
  /// списке ремонтов.
  List<PendingRepair> get pendingRepairs {
    final drafts = pendingRepairBox.values.toList();
    drafts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return drafts;
  }

  /// Кладёт черновик в очередь. Ключ бокса — `localId`, он же
  /// `Idempotency-Key`: повторная запись того же черновика перезаписывает
  /// запись, а не плодит вторую.
  Future<void> addPendingRepair(PendingRepair draft) async {
    await pendingRepairBox.put(draft.localId, draft);
    _refreshActiveRepairsCount();
  }

  /// Удаляет черновик **вместе с файлами** его снимков: иначе они остались бы
  /// в каталоге приложения навсегда, без владельца (п. 4.5.8 отчёта).
  Future<void> deletePendingRepair(String localId) async {
    final draft = pendingRepairBox.get(localId);
    await pendingRepairBox.delete(localId);
    if (draft != null) await RepairPhotoFiles.deleteAll(draft.photoPaths);
    _refreshActiveRepairsCount();
  }

  /// Правка конкретного ремонта, если она есть в очереди.
  PendingRepairUpdate? pendingUpdateFor(String repairUuid) =>
      pendingRepairUpdateBox.get(repairUuid);

  /// Кладёт правку в очередь. Ключ — uuid ремонта: одному ремонту
  /// соответствует одна правка, повторное сохранение накрывает предыдущую.
  Future<void> savePendingRepairUpdate(PendingRepairUpdate update) async {
    await pendingRepairUpdateBox.put(update.repairUuid, update);
  }

  Future<void> deletePendingRepairUpdate(String repairUuid) async {
    final update = pendingRepairUpdateBox.get(repairUuid);
    await pendingRepairUpdateBox.delete(repairUuid);
    if (update != null) await RepairPhotoFiles.deleteAll(update.photoPaths);
  }

  /// Все пути к файлам снимков, на которые ссылаются очереди. По этому набору
  /// уборка отличает нужные файлы от осиротевших.
  Set<String> get referencedPhotoPaths => {
        for (final draft in pendingRepairBox.values) ...draft.photoPaths,
        for (final update in pendingRepairUpdateBox.values)
          ...update.photoPaths,
      };

  /// Склады, встречающиеся в справочнике ЗИП, — «uuid → название».
  ///
  /// Отдельного запроса за складами нет намеренно: `GET /company/locations/`
  /// закрыт для роли «обходчик», а склад приезжает вложенным в каждую позицию
  /// справочника. Побочно это и правильнее — в фильтр попадают только склады,
  /// на которых что-то лежит.
  Map<String, String> sparePartWarehouses({
    bool Function(SparePart part)? where,
  }) =>
      _distinctSparePartRefs(
        (part) => part.warehouseUuid,
        (part) => part.warehouseName,
        where: where,
      );

  /// Группы номенклатуры из справочника ЗИП — «uuid → название».
  Map<String, String> sparePartNomenclatureGroups({
    bool Function(SparePart part)? where,
  }) =>
      _distinctSparePartRefs(
        (part) => part.nomenclatureGroupUuid,
        (part) => part.nomenclatureGroupName,
        where: where,
      );

  /// Уникальные пары «uuid → название» из справочника ЗИП, отсортированные по
  /// названию. Позиции без ссылки пропускаются — в фильтре им не место.
  ///
  /// [where] сужает выборку: экран передаёт сюда остальные условия фильтра,
  /// чтобы в списке не оказалось вариантов, которые заведомо дадут пустой
  /// результат.
  Map<String, String> _distinctSparePartRefs(
    String? Function(SparePart part) uuidOf,
    String? Function(SparePart part) nameOf, {
    bool Function(SparePart part)? where,
  }) {
    final result = <String, String>{};
    for (final part in _spareParts) {
      if (where != null && !where(part)) continue;
      final uuid = uuidOf(part);
      final name = nameOf(part);
      if (uuid == null || uuid.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      result[uuid] = name;
    }
    final sorted = result.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Map.fromEntries(sorted);
  }

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

  /// Отдельная отметка времени для справочника ЗИП. Нужна, чтобы экран мог
  /// обновлять только каталог остатков (это быстро), а подпись «Остатки на …»
  /// при этом оставалась правдой: общая `last_sync_date` относится ко всем
  /// справочникам сразу и после одиночной синхронизации ЗИП врала бы.
  /// Ключ отметки времени последней выгрузки справочника ЗИП.
  ///
  /// Хранится **момент в миллисекундах**, а не готовая строка «10.08 13:11».
  /// Строка врала бы при смене часового пояса устройства: записанная в одном
  /// поясе, она осталась бы прежней в другом. Момент же переводится в местное
  /// время в тот миг, когда его показывают.
  static const String _sparePartsSyncKey = 'spare_parts_last_sync_ms';

  /// Прежний ключ с отформатированной строкой. Читается только ради
  /// устройств, обновившихся со старой версии, и больше не пишется.
  static const String _legacySparePartsSyncKey = 'spare_parts_last_sync';

  saveSparePartsSyncDate() async {
    await stringBox.put(
      _sparePartsSyncKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Когда справочник ЗИП выгружали в последний раз. `null` — ни разу.
  DateTime? getSparePartsSyncAt() {
    final raw = stringBox.get(_sparePartsSyncKey);
    final ms = raw == null ? null : int.tryParse(raw);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);

    final legacy = stringBox.get(_legacySparePartsSyncKey);
    if (legacy == null || legacy.isEmpty) return null;
    try {
      return DateFormat('dd-MM-yyyy HH:mm:ss').parse(legacy);
    } catch (_) {
      return null;
    }
  }

  /// Свежесть остатков человеческим языком: «только что», «12 мин назад»,
  /// «сегодня в 13:11», «10.08 в 13:11».
  ///
  /// Относительное время для свежих данных — не украшение: обходчику важно
  /// «насколько эти числа устарели», а не точный момент. К тому же оно не
  /// зависит от часового пояса устройства, из-за которого абсолютное время
  /// на эмуляторе и на телефоне могло расходиться на несколько часов.
  ///
  /// `null` — справочник ни разу не выгружали.
  String? sparePartsFreshness() {
    final at = getSparePartsSyncAt()?.toLocal();
    if (at == null) return null;
    final now = DateTime.now();
    final minutes = now.difference(at).inMinutes;
    if (minutes < 1) return SparePartStrings.freshnessJustNow;
    if (minutes < 60) return SparePartStrings.freshnessMinutes(minutes);

    final time = DateFormat('HH:mm').format(at);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return SparePartStrings.freshnessToday(time);
    return SparePartStrings.freshnessOn(DateFormat('dd.MM').format(at), time);
  }

  addUser(User user) async {
    await userBox.put(user.username, user);
    _users = userBox.values.toList();
  }

  addScan(Scan scan) async {
    await scanBox.put(scan.key(), scan);
    invalidateScanTaskCache();
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

  /// Кладёт обновлённый ремонт в бокс и освежает кэш в памяти. Нужен после
  /// операций над одним ремонтом (взять в работу, сохранить расход), чтобы не
  /// перекачивать весь список ради одной записи.
  ///
  /// Закрытый ремонт из кэша убираем: в нём живут только активные.
  Future<void> upsertRepair(Repair repair) async {
    if (repair.isActive) {
      await repairBox.put(repair.uuid, repair);
    } else {
      await repairBox.delete(repair.uuid);
    }
    _repairs = repairBox.values.toList();
    _refreshActiveRepairsCount();
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

  /// Задачи, по которым осмотр уже снят и лежит в очереди отправки, — их не
  /// показываем как активные.
  ///
  /// Набор кэшируется: экран задач спрашивает задачи по каждой единице
  /// оборудования, и пересобирать его из двух боксов на каждый вызов значило
  /// бы проходить очереди сотни раз подряд.
  ///
  /// Кэш живёт ровно одно построение списка — экран сбрасывает его сам через
  /// [invalidateScanTaskCache] перед проходом. Ловить каждую запись в очередь
  /// было бы хрупко: мест много, и забытое дало бы задачу-призрак, которая не
  /// исчезает после снятого осмотра.
  Set<String?>? _scanTaskUuidsCache;

  Set<String?> _taskUuidsInScans() {
    final cached = _scanTaskUuidsCache;
    if (cached != null) return cached;
    final result = <String?>{
      for (final scan in scanBox.values) scan.taskUuid,
      for (final scan in scanPendingBox.values) scan.taskUuid,
    };
    _scanTaskUuidsCache = result;
    return result;
  }

  void invalidateScanTaskCache() => _scanTaskUuidsCache = null;

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
    final tasksInScans = _taskUuidsInScans();
    return taskBox.values
        .where((task) => task.equipmentUuid == machineUUID)
        .where((x) {
      if (tasksInScans.contains(x.uuid) || closedTasks.containsKey(x.uuid)) {
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
