import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../app_bar/app_bar.dart';
// Импорт библиотеки целиком, а не part-файла: syncMyRepairs объявлен в
// extension DataProviderSync и виден только через data_provider.dart.
import '../data/data_provider.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../http/api.dart';
import '../login/sign_out.dart';
import '../model/pending_repair.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../utils/search_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/offline_banner.dart';
import 'repair_delete_dialog.dart';
import 'repair_status_pill.dart';
import '../utils/company_time.dart';

/// Статусы, по которым фильтруется список, — в порядке листа «Фильтры».
/// Выбор множественный.
///
/// Запланированные, открытые и «на рассмотрении» лежат в офлайн-кэше, а
/// закрытые не кэшируются вовсе: их отдаёт отдельный эндпоинт, ровно
/// последние 10 без пагинации. Поэтому выбор «Закрыт» подтягивает их с
/// сервера отдельно.
const Map<String, String> _statusLabels = {
  RepairStatuses.scheduled: RepairStrings.statusScheduled,
  RepairStatuses.open: RepairStrings.statusOpen,
  RepairStatuses.underReview: RepairStrings.statusUnderReview,
  RepairStatuses.closed: RepairStrings.statusClosed,
};

/// Что показываем при пустом выборе — по макету 14a-2: «Запланирован» и
/// «Открыт», то, что ещё ждёт работы. Тянуть закрытые без явного запроса не
/// хочется: это лишний поход в сеть на каждом входе в раздел.
const Set<String> _defaultStatuses = {
  RepairStatuses.scheduled,
  RepairStatuses.open,
};

/// Список ремонтов обходчика.
///
/// Сервер сам сужает выдачу: обходчик видит ремонты, где он ответственный
/// либо где ремонт назначен на его должность. Отдельный фильтр «мои»
/// клиенту передавать не нужно.
class RepairsListScreen extends StatefulWidget {
  const RepairsListScreen({super.key});

  /// Забывает выбранные статусы — при выходе из аккаунта: это настройка
  /// прошлого пользователя.
  static void forgetFilter() =>
      _RepairsListScreenState._lastStatuses = const {};

  @override
  State<RepairsListScreen> createState() => _RepairsListScreenState();
}

class _RepairsListScreenState extends State<RepairsListScreen> {
  /// Выбор статусов, переживающий уход с экрана.
  ///
  /// Внутри одного захода список остаётся в стеке под карточкой ремонта и
  /// свой `State` сохраняет сам. Но раздел открывается с главной заново
  /// каждый раз, и тогда `State` создаётся с нуля — обычного поля не хватило
  /// бы. Статик живёт до перезапуска приложения: на следующий день обходчик
  /// снова видит активные ремонты, а не вчерашний выбор.
  static Set<String> _lastStatuses = {};

  /// Пустое множество означает «фильтр не задан» — показываем [_defaultStatuses].
  Set<String> _statuses = _lastStatuses;
  bool _isSyncing = false;

  /// Статусы, по которым реально идёт отбор.
  Set<String> get _effectiveStatuses =>
      _statuses.isEmpty ? _defaultStatuses : _statuses;

  /// Выбор отличается от умолчания — для числа на кнопке фильтров.
  bool get _isCustomFilter =>
      _effectiveStatuses.length != _defaultStatuses.length ||
      !_effectiveStatuses.containsAll(_defaultStatuses);

  // ── Поиск ────────────────────────────────────────────────────────────
  // По названию, модели и серийному номеру оборудования — как в списке
  // оборудования. Разовый: не запоминается, при уходе с экрана сброшен.
  final _searchController = TextEditingController();

  /// Запрос, по которому отобран список, — после паузы в наборе.
  String _query = '';
  Timer? _searchDebounce;
  static const Duration _searchDelay = Duration(milliseconds: 250);

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDelay, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() => _query = '');
  }

  /// Применяет набранный текст, не дожидаясь паузы, — перед открытием
  /// листа: иначе «Показать N» считалось бы по прежнему запросу.
  void _applySearchNow() {
    _searchDebounce?.cancel();
    final text = _searchController.text;
    if (_query != text) setState(() => _query = text);
  }

  /// Подходит ли оборудование под запрос. Серийного номера в ремонте нет —
  /// берём его из справочника оборудования по uuid. [serials] собирается
  /// один раз на отбор.
  static bool _matches(
    String query, {
    required String name,
    required String? typeModel,
    required String equipmentUuid,
    required Map<String, String?> serials,
  }) {
    if (query.isEmpty) return true;
    for (final field in [name, typeModel, serials[equipmentUuid]]) {
      if (field != null && normalizeSearchText(field).contains(query)) {
        return true;
      }
    }
    return false;
  }

  /// Серийные номера оборудования — только когда есть запрос: без него
  /// проход по справочнику не нужен.
  Map<String, String?> _serialsFor(String query) => query.isEmpty
      ? const {}
      : {
          for (final item in GlobalState.dataProvider.inventoryRecords)
            item.uuid: item.serialNumber,
        };

  bool get _needsClosed => _effectiveStatuses.contains(RepairStatuses.closed);

  /// Закрытые ремонты живут только здесь, в памяти экрана: в Hive они не
  /// попадают, поэтому при уходе с экрана список забывается.
  List<Repair>? _closed;
  bool _isLoadingClosed = false;
  String? _closedError;

  @override
  void initState() {
    super.initState();
    // Как и в справочнике ЗИП: фоновый цикл синхронизирует раз в 60 секунд,
    // и сразу после установки кэш пуст. Не заставляем ждать минуту.
    if (GlobalState.dataProvider.repairs.isEmpty) {
      _isSyncing = true;
      _syncRepairs();
    }
    // Восстановленный фильтр может уже включать «Закрыт». Закрытые ремонты не
    // кэшируются и живут только в поле экрана, а оно при пересоздании снова
    // пустое — без этого вкладка осталась бы пустой до повторного нажатия
    // на чип.
    if (_needsClosed) _loadClosed();
    // Каталог ЗИП больше не едет вместе с остальными справочниками — он
    // слишком большой. Заводим его загрузку здесь, на входе в раздел: пока
    // обходчик выбирает ремонт, каталог успевает подтянуться, и подбор
    // позиции в расходе открывается уже с данными. Экран этого не ждёт.
    GlobalState.dataProvider.ensureSparePartsLoaded();
    // Пока экран открыт, кэш ремонтов меняется без его участия: фоновый цикл
    // раз в минуту, очередь отправки черновиков, сигнал `repair_changed` по
    // SSE. Раньше список этого не замечал — данные обновлялись, а на экране
    // оставалось прежнее до жеста «потянуть вниз» или ухода и возврата.
    GlobalState.dataProvider.repairsRevision.addListener(_onRepairsChanged);
  }

  @override
  void dispose() {
    GlobalState.dataProvider.repairsRevision.removeListener(_onRepairsChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Список считается в `build` (`_visibleRepairs`), поэтому достаточно
  /// перерисовки — пересчитывать тут нечего.
  void _onRepairsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _syncRepairs() async {
    await GlobalState.dataProvider.syncMyRepairs();
    if (!mounted) return;
    setState(() => _isSyncing = false);
  }

  Future<void> _refresh() async {
    // Черновики и правки отправляем первыми: иначе syncMyRepairs перекачал бы
    // список ещё без только что уехавшего.
    await GlobalState.dataProvider.syncPendingRepairs();
    await GlobalState.dataProvider.syncPendingRepairUpdates();
    // Закрытые и активные живут в разных местах, поэтому при смешанном
    // выборе обновляем и то, и другое.
    if (_needsClosed) await _loadClosed();
    await GlobalState.dataProvider.syncMyRepairs();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadClosed() async {
    setState(() {
      _isLoadingClosed = true;
      _closedError = null;
    });
    try {
      final result = await API().getRecentClosedRepairs();
      if (!mounted) return;
      setState(() {
        _closed = result;
        _isLoadingClosed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingClosed = false;
        // Закрытые не кэшируются, поэтому без сети показать нечего — в
        // отличие от активных, которые лежат в Hive.
        _closedError = RepairStrings.closedLoadFailed;
      });
    }
  }

  void _setStatuses(Set<String> statuses) {
    // Выбор, совпадающий с умолчанием, храним пустым — «фильтр не задан».
    final next = statuses.length == _defaultStatuses.length &&
            statuses.containsAll(_defaultStatuses)
        ? const <String>{}
        : statuses;
    setState(() {
      _statuses = next;
      _lastStatuses = next;
    });
    // Закрытые не кэшируются — подтягиваем их при первом же выборе.
    if (_needsClosed && _closed == null && !_isLoadingClosed) {
      _loadClosed();
    }
  }

  Future<void> _openFilter() async {
    _applySearchNow();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _StatusFilterSheet(
        initial: _effectiveStatuses,
        countFor: (statuses) {
          // Закрытые приходят с сервера только после выбора — пока их нет,
          // число заранее неизвестно, и кнопка просто «Показать».
          if (statuses.contains(RepairStatuses.closed) && _closed == null) {
            return null;
          }
          return _visibleRepairsFor(statuses, _query).length +
              _visibleDraftsFor(statuses, _query).length;
        },
      ),
    );
    if (result == null || !mounted) return;
    _setStatuses(result);
  }

  List<Repair> get _visibleRepairs =>
      _visibleRepairsFor(_effectiveStatuses, _query);

  /// Ремонты выбранных [statuses], подходящие под [query]. Одна функция и
  /// для списка, и для «Показать N» в листе — обещанное совпадает с видимым.
  List<Repair> _visibleRepairsFor(Set<String> statuses, String query) {
    final normalized = normalizeSearchText(query);
    final serials = _serialsFor(normalized);
    final result = <Repair>[
      for (final repair in [
        ...GlobalState.dataProvider.repairs
            .where((repair) => statuses.contains(repair.status)),
        if (statuses.contains(RepairStatuses.closed)) ...?_closed,
      ])
        if (_matches(
          normalized,
          name: repair.equipmentName,
          typeModel: repair.equipmentTypeModel,
          equipmentUuid: repair.equipmentUuid,
          serials: serials,
        ))
          repair,
    ];
    result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return result;
  }

  /// Свободные ремонты — назначенные на должность, но ещё не взятые никем.
  ///
  /// Сравнивать должность с ролью пользователя на клиенте не нужно: сервер
  /// и так отдаёт обходчику только его ремонты и ремонты его должности,
  /// поэтому «без ответственного» здесь уже означает «моей должности».
  ///
  /// Запланированный без исполнителя — тоже здесь, а не в «Моих ремонтах»:
  /// он не мой. Взять его до даты начала нельзя (сервер даёт `claim` только
  /// открытому), поэтому на плитке у него пилюля «Запланирован», а не
  /// «Свободен», и кнопки «Взять» в карточке нет.
  List<Repair> _unassignedOf(List<Repair> repairs) => repairs
      .where((repair) =>
          repair.isUnassigned && (repair.isOpen || repair.isScheduled))
      .toList();

  /// Черновики — созданные без связи и ещё не принятые сервером.
  ///
  /// Показываем их по статусу, каким ремонт создаст сервер: запланированный
  /// черновик — при «Запланирован», остальные — при «Открыт». Во вкладке
  /// «Закрыт» черновику делать нечего.
  ///
  /// Черновик, чей ремонт уже создан, из списка убираем: очередь отправляет
  /// его в три шага (создать → снимки → расход и статус), и после первого шага
  /// ремонт лежит в кэше, а черновик остаётся в очереди ради недоехавших
  /// снимков. Оба объекта — один и тот же ремонт, и без этой проверки на
  /// экране появлялись две карточки на одно оборудование: «Черновик · Не
  /// отправлено» и «Открыт». Расхождение было видно сразу — счётчик активных
  /// ремонтов такие черновики вычитает (`_refreshActiveRepairsCount`), и на
  /// плитке главного экрана стояло «1» против двух карточек в списке.
  ///
  /// Сверяемся со всем кэшем, а не с отобранными по фильтру: ремонт мог уже
  /// уехать «На рассмотрение», и при фильтре «Открыт» дубль вернулся бы.
  List<PendingRepair> get _visibleDrafts =>
      _visibleDraftsFor(_effectiveStatuses, _query);

  List<PendingRepair> _visibleDraftsFor(Set<String> statuses, String query) {
    final normalized = normalizeSearchText(query);
    final serials = _serialsFor(normalized);
    final known = {
      for (final repair in GlobalState.dataProvider.repairs) repair.uuid,
    };
    final now = DateTime.now();
    return [
      for (final draft in GlobalState.dataProvider.pendingRepairs)
        // Черновик — будущий ремонт того статуса, каким его создаст сервер:
        // запланированный, пока его время не наступило, иначе открытый.
        if (statuses.contains(draft.isScheduledAt(now)
                ? RepairStatuses.scheduled
                : RepairStatuses.open) &&
            !known.contains(draft.serverUuid ?? '') &&
            _matches(
              normalized,
              name: draft.equipmentName,
              typeModel: null,
              equipmentUuid: draft.equipmentUuid,
              serials: serials,
            ))
          draft,
    ];
  }

  Future<void> _deleteDraft(PendingRepair draft) async {
    // У черновика с `serverUuid` ремонт на сервере уже есть: очередь успела
    // его создать и остановилась на снимках или финальной правке. Удаление
    // в этом случае не отменяет ремонт — оно бросает его открытым, а
    // оборудование остаётся «В ремонте». Спрашивать теми же словами, что и
    // про несозданный ремонт, значит вводить обходчика в заблуждение.
    final created = (draft.serverUuid ?? '').isNotEmpty;
    final confirmed = await confirmRepairDelete(
      context,
      title: created
          ? RepairStrings.draftDeleteCreatedTitle
          : RepairStrings.draftDeleteTitle,
      body: created
          ? RepairStrings.draftDeleteCreatedBody(draft.equipmentName)
          : RepairStrings.draftDeleteBody(draft.equipmentName),
      note: created
          ? RepairStrings.draftDeleteCreatedNote
          : RepairStrings.deleteIrreversible,
    );
    if (!confirmed) return;
    await GlobalState.dataProvider.deletePendingRepair(draft.localId);
    if (!mounted) return;
    setState(() {});
  }

  /// Список строится целиком, а не через `itemBuilder`: у обходчика активных
  /// ремонтов единицы-десятки, зато так тривиально вставляются заголовки
  /// групп. Во вкладке «Закрытые» их ровно 10 — тем более не проблема.
  List<Widget> _buildListChildren(List<Repair> repairs) {
    Widget tile(Repair repair) => _RepairTile(
          repair: repair,
          // Правка ждёт отправки — помечаем прямо в списке, иначе обходчик
          // узнал бы об этом только открыв карточку.
          pendingUpdate: GlobalState.dataProvider.pendingUpdateFor(repair.uuid),
          // Отдельной карточкой такой черновик больше не показывается — она
          // была бы вторым экземпляром этого же ремонта. Пометку про очередь
          // несёт эта карточка.
          queuedDraft: GlobalState.dataProvider.draftForRepair(repair.uuid),
          // push: список остаётся под карточкой и возвращается вместе с
          // выбранным фильтром и прокруткой.
          //
          // Сам ремонт передаём с собой, чтобы карточка нарисовалась сразу, не
          // дожидаясь сервера. Для закрытых это единственный источник: в Hive
          // они не кэшируются и живут только в памяти этого списка.
          onTap: () => GoRouter.of(context)
              .push('/repairs/${repair.uuid}', extra: repair),
        );

    final drafts = _visibleDrafts;
    // Черновики всегда сверху: это единственные записи, которые чего-то ждут
    // от обходчика, — остальные уже на сервере. Заголовка над ними нет: сами
    // карточки и так помечены пилюлей «Черновик» и красным значком очереди,
    // а подпись только повторяла это третий раз.
    final draftChildren = drafts.isEmpty
        ? const <Widget>[]
        : <Widget>[
            for (var i = 0; i < drafts.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingSM),
              _DraftTile(
                draft: drafts[i],
                onDelete: () => _deleteDraft(drafts[i]),
                // По черновику можно работать так же, как по ремонту:
                // заполнить расход, приложить фото и отправить (п. 4.5.1).
                onOpen: () => GoRouter.of(context)
                    .push('/repair_draft/${drafts[i].localId}'),
              ),
            ],
            const SizedBox(height: AppConstants.spacingLG),
          ];

    final free = _unassignedOf(repairs);
    // Группируем, только когда в выдаче есть свободные ремонты: иначе
    // заголовок «Мои ремонты» висел бы над списком без пары.
    if (free.isEmpty) {
      return [
        ...draftChildren,
        for (var i = 0; i < repairs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingSM),
          tile(repairs[i]),
        ],
      ];
    }

    final mine = repairs.where((repair) => !free.contains(repair)).toList();
    return [
      ...draftChildren,
      const _GroupLabel(RepairStrings.groupFree),
      const SizedBox(height: AppConstants.spacingSM),
      for (var i = 0; i < free.length; i++) ...[
        if (i > 0) const SizedBox(height: AppConstants.spacingSM),
        tile(free[i]),
      ],
      if (mine.isNotEmpty) ...[
        const SizedBox(height: AppConstants.spacingLG),
        const _GroupLabel(RepairStrings.groupMine),
        const SizedBox(height: AppConstants.spacingSM),
        for (var i = 0; i < mine.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingSM),
          tile(mine[i]),
        ],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repairs = _visibleRepairs;
    final onlyClosed = _effectiveStatuses.length == 1 && _needsClosed;
    final busy = _isSyncing || (_needsClosed && _isLoadingClosed);
    // Пустым список считается, только когда нет и черновиков: иначе
    // единственный неотправленный ремонт спрятался бы за «Ремонтов нет».
    final isEmpty = repairs.isEmpty && _visibleDrafts.isEmpty;
    // Пусто из-за поиска, а не потому, что ремонтов нет: в выбранных
    // статусах что-то есть, но под запрос не подошло.
    final nothingFound = isEmpty &&
        _query.trim().isNotEmpty &&
        (_visibleRepairsFor(_effectiveStatuses, '').isNotEmpty ||
            _visibleDraftsFor(_effectiveStatuses, '').isNotEmpty);

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          // Поиск и шторка «Фильтры» — как в справочнике ЗИП (макет 14a).
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
              AppConstants.spacingSM,
            ),
            child: SearchFilterBar(
              controller: _searchController,
              hint: RepairStrings.searchHint,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              // Подсвечиваем, только когда выбор отличается от умолчания:
              // «Запланирован + Открыт» — обычный вид списка, не фильтр.
              activeCount: _isCustomFilter ? _effectiveStatuses.length : 0,
              onFilter: _openFilter,
            ),
          ),
          if (busy && isEmpty)
            Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: cs.primary,
                  strokeWidth: 8,
                  constraints:
                      const BoxConstraints(minHeight: 128, minWidth: 128),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMD,
                        ),
                        children: [
                          const _AuthExpiredBanner(),
                          if (nothingFound)
                            const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: FilterStrings.nothingFound,
                              hint: RepairStrings.nothingFoundHint,
                            )
                          else
                            EmptyState(
                              icon: _closedError != null
                                  ? Icons.cloud_off_rounded
                                  : Icons.handyman_outlined,
                              title: _closedError != null
                                  ? RepairStrings.noConnection
                                  : RepairStrings.listEmptyTitle,
                              hint: _closedError ??
                                  (onlyClosed
                                      ? RepairStrings.listEmptyClosedHint
                                      : RepairStrings.listEmptyHint),
                            ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.spacingMD,
                          AppConstants.spacingSM,
                          AppConstants.spacingMD,
                          AppConstants.spacingXL,
                        ),
                        children: [
                          const _AuthExpiredBanner(),
                          const OfflineBanner(
                            hint: RepairStrings.listOfflineHint,
                          ),
                          ..._buildListChildren(repairs),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Карточка ремонта в списке
// ─────────────────────────────────────────────────────────────────────────
class _RepairTile extends StatelessWidget {
  final Repair repair;
  final VoidCallback onTap;

  /// Неотправленная правка этого ремонта, если она есть.
  final PendingRepairUpdate? pendingUpdate;

  /// Черновик, из которого этот ремонт создан, если он ещё в очереди.
  ///
  /// Очередь отправляет черновик в три шага, и после первого ремонт уже есть
  /// на сервере, а черновик остаётся — ради недоехавших снимков или финальной
  /// правки. Отдельной карточкой такой черновик больше не показывается (это
  /// был бы дубль этого же ремонта), поэтому пометку «Не отправлено» несёт
  /// карточка ремонта — иначе про застрявшие снимки не сказал бы никто.
  final PendingRepair? queuedDraft;

  const _RepairTile({
    required this.repair,
    required this.onTap,
    this.pendingUpdate,
    this.queuedDraft,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final started =
        DateFormat('dd.MM HH:mm').format(CompanyTime.of(repair.startedAt));
    final isFree = repair.isUnassigned && repair.isOpen;
    // Источника у пометки два — неотправленная правка и неотправленный
    // черновик, — а выглядит она одинаково: обходчику важно, что данные ещё
    // не на сервере, а не какая именно очередь их держит.
    final unsent = pendingUpdate != null || queuedDraft != null;
    final unsentRejected = (pendingUpdate?.isRejected ?? false) ||
        (queuedDraft?.isRejected ?? false);
    final unsentColor = unsentRejected ? cs.error : cs.warning;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Значок нейтральный, как в макете: цветом в карточке говорит
              // пилюля статуса, а не подложка иконки.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: Icon(
                      Icons.precision_manufacturing_outlined,
                      size: 24,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  // Оранжевая точка на значке оборудования — признак
                  // неотправленного (п. 4.2.4 отчёта).
                  if (unsent)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: unsentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      repair.equipmentName.isEmpty
                          ? RepairStrings.equipmentUnknown
                          : repair.equipmentName,
                      style: tt.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppConstants.spacingSM),
                    // Пилюля и «№128 · 28.07 14:30» строго в одной строке:
                    // Row вместо Wrap, чтобы текст не уезжал вниз, а
                    // Flexible + ellipsis — чтобы на узком экране он
                    // подрезался, а не ломал вёрстку.
                    Row(
                      children: [
                        if (isFree)
                          const RepairFreePill(compact: true)
                        else
                          RepairStatusPill(
                            status: repair.status,
                            compact: true,
                          ),
                        const SizedBox(width: AppConstants.spacingSM),
                        // У ремонта с неотправленными изменениями вместо
                        // «№128 · дата» — пометка «Не отправлено» с
                        // перечёркнутым облаком (п. 4.2.4 отчёта): номер и
                        // дата никуда не денутся, а вот про очередь обходчик
                        // должен узнать с первого взгляда.
                        if (unsent) ...[
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 14,
                            color: unsentColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              RepairStrings.draftPill,
                              style: tt.bodySmall?.copyWith(
                                color: unsentColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else
                          Flexible(
                            // Номер и дата — у всех карточек одинаково, включая
                            // свободные. Раньше у свободного вместо них стояло
                            // название должности: строка выглядела иначе, чем
                            // соседние, а найти ремонт по номеру было нельзя.
                            // Должность видна в карточке, в «Деталях ремонта».
                            child: Text(
                              '№${repair.id}  ·  $started',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingSM),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоса «Сессия истекла».
///
/// Очередь работает в фоне и своего экрана не имеет, поэтому об истёкшем
/// токене сообщает здесь: иначе черновики копились бы молча, а обходчик
/// думал бы, что всё отправляется.
class _AuthExpiredBanner extends StatelessWidget {
  const _AuthExpiredBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.dataProvider.authExpired,
      builder: (context, expired, _) {
        if (!expired) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppConstants.spacingMD),
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_clock_rounded, size: 20, color: cs.error),
              const SizedBox(width: AppConstants.spacingSM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      RepairStrings.authExpiredTitle,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      RepairStrings.authExpiredBody,
                      style: tt.bodySmall?.copyWith(color: cs.onErrorContainer),
                    ),
                    const SizedBox(height: AppConstants.spacingSM),
                    FilledButton(
                      onPressed: () async {
                        // Сохранённого пользователя снимаем сами: пока он в
                        // хранилище, редирект в main.dart считает вход
                        // выполненным и с '/login' уводит обратно. Через общий
                        // выход: раньше здесь снимался только пользователь, а
                        // уведомления, их недошедшие отметки, push-сервис и
                        // запомненные фильтры оставались от прошлой сессии.
                        // Пользователь снимается синхронно, остановку
                        // push-сервиса ждём уже после перехода.
                        final stopping = signOut();
                        GoRouter.of(context).go('/login');
                        await stopping;
                      },
                      child: const Text(RepairStrings.authExpiredAction),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Черновик ремонта: создан без связи, ждёт отправки
// ─────────────────────────────────────────────────────────────────────────

/// Карточка черновика — ремонта, созданного без связи и ещё не принятого
/// сервером.
///
/// Ведёт себя как обычная карточка ремонта: нажатие открывает черновик, справа
/// стрелка. По нему работают так же — заполняют расход, прикладывают фото,
/// отправляют, — поэтому отдельной кнопки «Открыть карточку» тут нет.
///
/// Единственное действие на самой карточке — «Удалить»: оно необратимо, и
/// нажать его случайно вместе с переходом нельзя, поэтому оно вынесено
/// отдельной полосой внизу.
class _DraftTile extends StatelessWidget {
  final PendingRepair draft;
  final VoidCallback onDelete;

  /// Открыть карточку черновика: по нему работают так же, как по ремонту.
  final VoidCallback onOpen;

  const _DraftTile({
    required this.draft,
    required this.onDelete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = DateFormat('dd.MM HH:mm').format(CompanyTime.of(draft.startedAt));
    // Запланированный черновик ничем не отличался от обычного — что ремонт
    // начнётся позже, было видно только в карточке.
    final started = draft.isScheduledAt(DateTime.now())
        ? RepairStrings.draftStartsAt(date)
        : date;
    final rejected = draft.isRejected;

    // Рамки у карточки нет: что записи ещё нет на сервере, видно и без неё —
    // по красному значку, пилюле «Черновик» и полосе удаления внизу.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: Icon(
                      rejected
                          ? Icons.error_outline_rounded
                          : Icons.cloud_upload_outlined,
                      size: 24,
                      color: cs.error,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          draft.equipmentName.isEmpty
                              ? RepairStrings.equipmentUnknown
                              : draft.equipmentName,
                          style: tt.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppConstants.spacingSM),
                        Row(
                          children: [
                            const RepairDraftPill(),
                            const SizedBox(width: AppConstants.spacingSM),
                            Flexible(
                              child: Text(
                                started,
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        // Причину отказа в списке не печатаем. Красная строка
                        // под каждым черновиком превращала список в полосу
                        // тревоги, а разбирается отказ всё равно на карточке:
                        // там та же причина написана в блоке «Не отправлено»,
                        // и там же стоят кнопки под конкретный случай.
                        // Отличить отклонённый черновик от ждущего связи
                        // по-прежнему можно по значку слева.
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSM),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          // Во всю ширину и без скруглений: полоса упирается в края
          // карточки, а углы ей обрезает `clipBehavior` самой карточки.
          SizedBox(
            width: double.infinity,
            height: AppConstants.buttonHeight,
            child: FilledButton.icon(
              onPressed: onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                shape: const RoundedRectangleBorder(),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text(RepairStrings.delete),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок группы в списке — прописными, как секционные подписи форм.
class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Text(
      text,
      style: tt.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Лист «Фильтры»: статусы ремонта
// ─────────────────────────────────────────────────────────────────────────
/// Один раздел «Статус» — как фильтры справочника ЗИП (макет 14a-2).
/// Возвращает выбранные статусы.
class _StatusFilterSheet extends StatefulWidget {
  final Set<String> initial;

  /// Сколько покажет список при выбранных статусах — с поиском экрана.
  /// `null` — заранее неизвестно (закрытые ещё не загружены).
  final int? Function(Set<String> statuses) countFor;

  const _StatusFilterSheet({required this.initial, required this.countFor});

  @override
  State<_StatusFilterSheet> createState() => _StatusFilterSheetState();
}

class _StatusFilterSheetState extends State<_StatusFilterSheet> {
  late Set<String> _draft = widget.initial;
  late int? _count = widget.countFor(_draft);

  bool get _isDefault =>
      _draft.length == _defaultStatuses.length &&
      _draft.containsAll(_defaultStatuses);

  void _update(Set<String> next) {
    setState(() {
      _draft = next;
      _count = widget.countFor(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheet(
      // «Сбросить» возвращает умолчание, а не пустой выбор: пустой список
      // статусов ничего бы не показал.
      onReset: _isDefault ? null : () => _update(_defaultStatuses),
      // Ни одного статуса — показывать нечего.
      resultCount: _draft.isEmpty ? 0 : _count,
      resultLabel: RepairStrings.showResults,
      onApply: () => Navigator.of(context).pop(_draft),
      children: [
        FilterSection(
          label: RepairStrings.labelStatus,
          count: _draft.length,
          child: FilterChipGroup(
            // Порядок статусов — по жизни ремонта, а не по алфавиту.
            options: _statusLabels,
            selected: _draft,
            onChanged: _update,
          ),
        ),
      ],
    );
  }
}
