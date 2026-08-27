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
import '../../src/model/consumption_norm.dart';
import '../../src/model/ppr.dart';
import '../model/usage_update.dart';
import '../exceptions/app_exceptions.dart';
import '../../strings.dart';
import '../feature_flags.dart';
import '../qr/scan_error_messages.dart';
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
  final Box<ConsumptionNorm> consumptionNormBox;
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
      required this.consumptionNormBox,
      required this.periodicTaskBox,
      required this.periodicTaskPendingBox}) {
    // Сортируем на старте, а не полагаемся на порядок записи в Hive: после
    // инкрементального прохода новые позиции лежат в конце бокса, и порядок
    // на диске отсортированным быть перестал. Один проход по каталогу при
    // запуске дешевле сортировки в `build` экрана.
    _spareParts = sparePartBox.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _rebuildSparePartIndex();
    _rebuildClosedTaskIndex();
    _repairs = repairBox.values.toList();
    _refreshActiveRepairsCount();
    refreshRejectedScansCount();
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
      setActivePprs(
          raw.map((e) => Ppr.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e) {
      print('Failed to read PPR cache: $e');
    }
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
    // Сбрасываем кэш очередей на входе — тот же договор, что и у списка
    // оборудования: внутри одного прохода он живёт и экономит сотни обходов,
    // между кадрами очередь могла измениться.
    //
    // Сброс стоит именно здесь, а не на экране ППР: этот метод — общая точка
    // входа и для экрана, и для кнопки «ППР» на главной
    // ([hasPprInProgressWithTasks]), а на главную попадают, минуя «Задачи»,
    // которые раньше были единственным местом сброса.
    invalidateScanTaskCache();
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

  List<SparePart> get spareParts => _spareParts;

  /// Нормы расхода для оборудования из кэша — то, что можно выбрать без сети.
  ///
  /// Отбор по оборудованию делаем здесь: серверного фильтра офлайн нет, а
  /// норм на компанию десятки, так что полный перебор бокса дешевле индекса.
  List<ConsumptionNorm> consumptionNormsFor(String equipmentUuid) => [
        for (final norm in consumptionNormBox.values)
          if (norm.equipmentUuid == equipmentUuid) norm,
      ];

  /// Кладёт в кэш нормы, только что полученные с сервера по одному
  /// оборудованию.
  ///
  /// Весь справочник наливает `syncConsumptionNorms`, но она ходит только в
  /// общей синхронизации — то есть при живой связи и не чаще раза в сеанс.
  /// Форма создания ремонта спрашивает нормы у сервера сама и раньше ответ
  /// выбрасывала: обходчик видел список онлайн, а без связи тот же список
  /// оказывался пуст, хотя «нормы уже загружались». Теперь всё, что показали
  /// онлайн, остаётся доступным офлайн.
  ///
  /// Снимок по этому оборудованию замещается целиком — норму могли удалить на
  /// сервере. Чужие записи не трогаем: про них ответ ничего не сообщает.
  Future<void> cacheConsumptionNorms(
    String equipmentUuid,
    List<ConsumptionNorm> norms,
  ) async {
    if (equipmentUuid.isEmpty) return;
    final fresh = {for (final norm in norms) norm.uuid: norm};
    final stale = [
      for (final entry in consumptionNormBox.toMap().entries)
        if (entry.value.equipmentUuid == equipmentUuid &&
            !fresh.containsKey(entry.key))
          entry.key,
    ];
    if (stale.isNotEmpty) await consumptionNormBox.deleteAll(stale);
    if (fresh.isNotEmpty) await consumptionNormBox.putAll(fresh);
  }

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

  /// Сколько осмотров сервер отклонил и повторять их сам никто не будет.
  ///
  /// [ValueNotifier] по той же причине, что и [activeRepairsCount]: очередь
  /// работает в фоне, экранам нужно узнать об отказе без своей перерисовки.
  final ValueNotifier<int> rejectedScansCount = ValueNotifier<int>(0);

  /// Отклонённые осмотры — для полосы на главной и диалога с причинами.
  List<Scan> get rejectedScans =>
      scanBox.values.where((scan) => scan.isRejected).toList();

  void refreshRejectedScansCount() {
    rejectedScansCount.value = rejectedScans.length;
  }

  void _refreshActiveRepairsCount() {
    // Черновики тоже активные ремонты — просто ещё не доехавшие. Не считать их
    // значило бы: обходчик создал ремонт в цеху, вернулся в меню, а счётчик
    // прежний, будто ничего не произошло.
    //
    // Но черновик, у которого уже есть `serverUuid`, — это тот же самый
    // ремонт, что лежит в кэше: очередь создала его на сервере и остановилась
    // на снимках или финальной правке. Складывать оба значило показывать на
    // плитке на единицу больше, чем ремонтов на самом деле.
    final active = _repairs.where((r) => r.isActive).toList();
    final known = {for (final repair in active) repair.uuid};
    final drafts = pendingRepairBox.values.where((draft) {
      final uuid = draft.serverUuid;
      return uuid == null || !known.contains(uuid);
    }).length;
    activeRepairsCount.value = active.length + drafts;
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

  /// Префикс ключа отметки «задачу закрыл этот обходчик».
  static const String _closedTaskPrefix = 'closed_task_';

  /// Задачи, по которым осмотр уже отправлен, — индекс в памяти поверх Hive.
  ///
  /// Раньше это была статическая карта, и жила она до первого события
  /// жизненного цикла: `didChangeAppLifecycleState` чистил её безусловно, на
  /// любое состояние. Хватало заблокировать экран или открыть камеру — и
  /// закрытая задача снова появлялась в списке, а обходчик выполнял её
  /// второй раз.
  ///
  /// Индекс, а не чтение бокса на каждую задачу: список задач фильтруется в
  /// цикле по всему ящику, и поход в Hive на каждой итерации был бы дороже
  /// самой фильтрации.
  Set<String> _closedTaskUuids = {};

  /// Закрыл ли обходчик эту задачу сам — осмотр отправлен либо ждёт в очереди.
  bool isTaskClosedLocally(String uuid) => _closedTaskUuids.contains(uuid);

  Future<void> markTaskClosedLocally(String uuid) async {
    if (uuid.isEmpty || _closedTaskUuids.contains(uuid)) return;
    _closedTaskUuids = {..._closedTaskUuids, uuid};
    await stringBox.put('$_closedTaskPrefix$uuid', '1');
  }

  /// Снимает отметки с задач, которых сервер больше не отдаёт.
  ///
  /// Отметка нужна ровно до того момента, как сервер сам перестанет считать
  /// задачу активной. Дальше она бесполезна и только копилась бы в боксе.
  Future<void> pruneClosedTasks(Set<String> stillReturned) async {
    final stale = _closedTaskUuids.difference(stillReturned);
    if (stale.isEmpty) return;
    for (final uuid in stale) {
      await stringBox.delete('$_closedTaskPrefix$uuid');
    }
    _closedTaskUuids = _closedTaskUuids.difference(stale);
  }

  void _rebuildClosedTaskIndex() {
    _closedTaskUuids = {
      for (final key in stringBox.keys)
        if (key is String && key.startsWith(_closedTaskPrefix))
          key.substring(_closedTaskPrefix.length),
    };
  }

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

  /// Взводится на время перезаписи каталога ЗИП и снимается после неё.
  ///
  /// Каталог пишется как `clear()` + `addAll()`, и на десятках тысяч позиций
  /// это не мгновенно. Убьют приложение между ними — в боксе останется пусто
  /// или половина, а выглядеть это будет как готовый каталог: список не пуст,
  /// дозагрузка не запустится, и офлайн выбрать позицию расхода будет не из
  /// чего. Флаг переживает перезапуск и говорит, что прочитанному верить
  /// нельзя.
  static const String _sparePartsWriteKey = 'spare_parts_write_in_progress';

  /// Прервалась ли последняя запись каталога ЗИП.
  bool get isSparePartsWriteIncomplete =>
      stringBox.get(_sparePartsWriteKey) == '1';

  Future<void> markSparePartsWriteStarted() =>
      stringBox.put(_sparePartsWriteKey, '1');

  Future<void> markSparePartsWriteFinished() =>
      stringBox.delete(_sparePartsWriteKey);

  /// Граница последнего согласованного окна для ремонтов.
  ///
  /// В памяти, а не в Hive: окно не сообщает о переназначении ремонта другому
  /// сотруднику — такой ремонт просто уходит из выдачи, не попадая ни в
  /// `items`, ни в `deleted`. Полный проход на каждом холодном старте
  /// ограничивает расхождение одним сеансом.
  DateTime? _repairsCursor;

  /// Ключ отметки инкрементальной синхронизации ЗИП.
  ///
  /// Отдельно от [_sparePartsSyncKey]: та хранит локальное время для подписи
  /// «Остатки на …», а здесь — `sync_until` **сервера**. Часы телефона с
  /// сервером расходятся, и подставить местное «сейчас» в окно запроса
  /// значило бы либо потерять изменения, либо тянуть их повторно.
  static const String _sparePartsCursorKey = 'spare_parts_cursor';

  /// Момент, до которого каталог ЗИП уже согласован с сервером. `null` — ни
  /// разу, нужен полный проход.
  DateTime? getSparePartsCursor() {
    final raw = stringBox.get(_sparePartsCursorKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _saveSparePartsCursor(DateTime? value) async {
    if (value == null) {
      // Сервер границу не назвал — забываем отметку, иначе следующий проход
      // считал бы окно от устаревшего момента.
      await stringBox.delete(_sparePartsCursorKey);
      return;
    }
    await stringBox.put(
      _sparePartsCursorKey,
      value.toUtc().toIso8601String(),
    );
  }

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
      final periodic = task?.periodicTask;
      // Признак ТО берём у сервера. Разбор по заголовку оставлен запасным: у
      // задач из кэша, записанного до появления поля `is_maintenance`, его в
      // потоке нет, и до первой синхронизации `isMaintenance` будет `false`.
      // Ошибиться здесь дорого — от этого зависит, дождётся ли задача ТО
      // отправки наработки по своему оборудованию.
      final isMaintenance = periodic != null &&
          (periodic.isMaintenance ||
              periodic.title.contains('Техническое обслуживание'));
      if (scan.periodicTaskUuid != null &&
          scan.periodicTaskUuid!.isNotEmpty &&
          isMaintenance) {
        await stringBox.put('maintenance_task_$taskUuid', '1');
      }
      await markTaskClosedLocally(taskUuid);
      await taskBox.delete(taskUuid);
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

  /// Оборудование по локальному `id`. `null` — его нет в справочнике.
  ///
  /// Отдельный метод, потому что маршрут `/details/:index` ищет именно по
  /// `id`, а найтись оборудование может не всегда: его удалили на сервере, и
  /// синхронизация перезаписала бокс, пока экран был открыт или пока
  /// пользователь шёл по ссылке из пуш-уведомления.
  InventoryRecord? equipmentById(int id) {
    for (final record in _inventoryRecords) {
      if (record.id == id) return record;
    }
    return null;
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
  Map<String, String?>? _scanTaskUuidsCache;

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
  ///
  /// Результат кэшируется: экран задач спрашивает задачи по каждой единице
  /// оборудования, а экран ППР — по каждому ППР, и пересобирать набор из
  /// двух боксов на каждый вызов значило бы проходить очереди сотни раз
  /// подряд. Кэш живёт ровно одно построение списка — экран сбрасывает его
  /// сам через [invalidateScanTaskCache] перед проходом. Ловить каждую запись
  /// в очередь было бы хрупко: мест много, и забытое дало бы задачу-призрак,
  /// которая не исчезает после снятого осмотра.
  Map<String, String?> _scannedTaskUuids() {
    final cached = _scanTaskUuidsCache;
    if (cached != null) return cached;
    final Map<String, String?> tasksInScans = {};
    for (var scan in scanBox.values.toList()) {
      tasksInScans[scan.taskUuid ?? ''] = scan.taskUuid;
    }
    for (var scan in scanPendingBox.values.toList()) {
      tasksInScans[scan.taskUuid ?? ''] = scan.taskUuid;
    }
    _scanTaskUuidsCache = tasksInScans;
    return tasksInScans;
  }

  /// Показывать ли задачу текущему пользователю: не закрыта локально,
  /// периодическая — по его роли, назначенная — по ответственному.
  bool _isTaskAvailable(Task task, Map<String, String?> tasksInScans) {
    if (tasksInScans.containsKey(task.uuid) || isTaskClosedLocally(task.uuid)) {
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
