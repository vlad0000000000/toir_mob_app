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
import '../model/pending_repair.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart';
import 'repair_delete_dialog.dart';
import 'repair_status_pill.dart';

/// Статусы, по которым фильтруется список. Выбор множественный.
///
/// Открытые и «на рассмотрении» лежат в офлайн-кэше, а закрытые не
/// кэшируются вовсе: их отдаёт отдельный эндпоинт, ровно последние 10 без
/// пагинации. Поэтому выбор «Закрыт» подтягивает их с сервера отдельно.
const Map<String, String> _statusLabels = {
  RepairStatuses.open: RepairStrings.statusOpen,
  RepairStatuses.underReview: RepairStrings.statusUnderReview,
  RepairStatuses.closed: RepairStrings.statusClosed,
};

/// Что показываем при пустом выборе — те же активные, что и раньше по
/// умолчанию. Тянуть закрытые без явного запроса не хочется: это лишний
/// поход в сеть на каждом входе в раздел.
const Set<String> _defaultStatuses = {
  RepairStatuses.open,
  RepairStatuses.underReview,
};

/// Список ремонтов обходчика.
///
/// Сервер сам сужает выдачу: обходчик видит ремонты, где он ответственный
/// либо где ремонт назначен на его должность. Отдельный фильтр «мои»
/// клиенту передавать не нужно.
class RepairsListScreen extends StatefulWidget {
  const RepairsListScreen({super.key});

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

  void _toggleStatus(String status) {
    setState(() {
      final next = {..._statuses};
      if (!next.remove(status)) next.add(status);
      _statuses = next;
      _lastStatuses = next;
    });
    // Закрытые не кэшируются — подтягиваем их при первом же выборе.
    if (_needsClosed && _closed == null && !_isLoadingClosed) {
      _loadClosed();
    }
  }

  List<Repair> get _visibleRepairs {
    final statuses = _effectiveStatuses;
    final result = <Repair>[
      ...GlobalState.dataProvider.repairs
          .where((repair) => statuses.contains(repair.status)),
      if (statuses.contains(RepairStatuses.closed)) ...?_closed,
    ];
    result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return result;
  }

  /// Свободные ремонты — назначенные на должность, но ещё не взятые никем.
  ///
  /// Сравнивать должность с ролью пользователя на клиенте не нужно: сервер
  /// и так отдаёт обходчику только его ремонты и ремонты его должности,
  /// поэтому «без ответственного» здесь уже означает «моей должности».
  List<Repair> _unassignedOf(List<Repair> repairs) =>
      repairs.where((repair) => repair.isUnassigned && repair.isOpen).toList();

  /// Черновики — созданные без связи и ещё не принятые сервером.
  ///
  /// Показываем их только когда в фильтре есть «Открыт»: черновик и есть
  /// будущий открытый ремонт, а во вкладке «Закрыт» ему делать нечего.
  List<PendingRepair> get _visibleDrafts =>
      _effectiveStatuses.contains(RepairStatuses.open)
          ? GlobalState.dataProvider.pendingRepairs
          : const [];

  Future<void> _deleteDraft(PendingRepair draft) async {
    final confirmed = await confirmRepairDelete(
      context,
      title: RepairStrings.draftDeleteTitle,
      body: RepairStrings.draftDeleteBody(draft.equipmentName),
      note: RepairStrings.deleteIrreversible,
    );
    if (!confirmed) return;
    await GlobalState.dataProvider.deletePendingRepair(draft.localId);
    if (!mounted) return;
    setState(() {});
  }

  /// Отклонённый черновик разбирают на отдельном экране: там видно и что
  /// вводил обходчик, и какой ремонт помешал.
  /// Список строится целиком, а не через `itemBuilder`: у обходчика активных
  /// ремонтов единицы-десятки, зато так тривиально вставляются заголовки
  /// групп. Во вкладке «Закрытые» их ровно 10 — тем более не проблема.
  List<Widget> _buildListChildren(List<Repair> repairs) {
    Widget tile(Repair repair) => _RepairTile(
          repair: repair,
          // Правка ждёт отправки — помечаем прямо в списке, иначе обходчик
          // узнал бы об этом только открыв карточку.
          pendingUpdate: GlobalState.dataProvider.pendingUpdateFor(repair.uuid),
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
    // от обходчика, — остальные уже на сервере.
    final draftChildren = drafts.isEmpty
        ? const <Widget>[]
        : <Widget>[
            const _GroupLabel(RepairStrings.groupUnsent),
            const SizedBox(height: AppConstants.spacingSM),
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

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMD,
                vertical: AppConstants.spacingSM,
              ),
              children: [
                for (final entry in _statusLabels.entries) ...[
                  if (entry.key != _statusLabels.keys.first)
                    const SizedBox(width: AppConstants.spacingSM),
                  _FilterChip(
                    label: entry.value,
                    selected: _statuses.contains(entry.key),
                    onTap: () => _toggleStatus(entry.key),
                  ),
                ],
              ],
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

  const _RepairTile({
    required this.repair,
    required this.onTap,
    this.pendingUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final started =
        DateFormat('dd.MM HH:mm').format(repair.startedAt.toLocal());
    final isFree = repair.isUnassigned && repair.isOpen;

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
                  if (pendingUpdate != null)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color:
                              pendingUpdate!.isRejected ? cs.error : cs.warning,
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
                        if (pendingUpdate != null) ...[
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 14,
                            color: pendingUpdate!.isRejected
                                ? cs.error
                                : cs.warning,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              RepairStrings.draftPill,
                              style: tt.bodySmall?.copyWith(
                                color: pendingUpdate!.isRejected
                                    ? cs.error
                                    : cs.warning,
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
                      onPressed: () {
                        // Сохранённого пользователя снимаем сами: пока он в
                        // хранилище, редирект в main.dart считает вход
                        // выполненным и с '/login' уводит обратно.
                        GlobalState.authUser = null;
                        GoRouter.of(context).go('/login');
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
    final started = DateFormat('dd.MM HH:mm').format(draft.startedAt.toLocal());
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
                            const _DraftPill(),
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

/// Пилюля черновика — стоит на месте статуса.
class _DraftPill extends StatelessWidget {
  const _DraftPill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSM,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        // На месте статуса — «Черновик»: серверного статуса у него ещё нет
        // (п. 4.2.4 отчёта). «Не отправлено» осталось за ремонтами, которые
        // на сервере уже есть, но с неотправленными правками.
        ConflictStrings.badgeDraft,
        style: tt.labelSmall?.copyWith(
          color: cs.error,
          fontWeight: FontWeight.w600,
        ),
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
// Чип фильтра статуса (одиночный выбор)
// ─────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Тот же вид, что у чипов истории движений в карточке ЗИП: полностью
    // скруглённая пилюля, выбранная — сплошной заливкой без галочки.
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border:
                Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Text(
            label,
            style: tt.labelLarge?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
