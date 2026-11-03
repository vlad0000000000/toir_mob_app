import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../http/api.dart';
import '../model/repair_history.dart';
import '../utils/go_router_ext.dart';
import '../utils/offline_error.dart';
import '../widgets/empty_state.dart';
import 'repair_status_pill.dart';

/// «История ремонта №…» (макет 14i): создание, переносы даты начала и смены
/// статуса, новые сверху. Вид — как блок «История изменений» в карточке
/// ремонта веб-админки: лента событий с кружком автора («МД», у «Системы» —
/// часы), «Морозов Д. А. закрытие ремонта», время и карточка «было → стало».
///
/// Только в сети: история не кэшируется, она нужна редко и только на этом
/// экране. Вход — пункт «История изменений» внизу карточки ремонта.
class RepairHistoryScreen extends StatefulWidget {
  final String repairUuid;

  /// Номер ремонта для заголовка. `null` — неизвестен (пришли не из
  /// карточки): тогда заголовок без номера.
  final int? repairId;

  const RepairHistoryScreen({
    super.key,
    required this.repairUuid,
    this.repairId,
  });

  @override
  State<RepairHistoryScreen> createState() => _RepairHistoryScreenState();
}

class _RepairHistoryScreenState extends State<RepairHistoryScreen> {
  List<RepairHistoryEntry>? _entries;
  bool _loading = true;

  /// Не загрузилось. `true` — нет связи, иначе отказ сервера.
  bool? _offline;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = null;
    });
    try {
      final history = await API().getRepairHistory(widget.repairUuid);
      if (!mounted) return;
      setState(() {
        // Сервер отдаёт от старых к новым, макет — новые сверху.
        _entries = history.reversed.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final offline = isOfflineError(e);
      // История уже на экране — не прячем её из-за неудачного обновления
      // («потянуть вниз» без связи): говорим снекбаром, список остаётся.
      if (_entries != null) {
        setState(() => _loading = false);
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
              offline
                  ? RepairStrings.noConnection
                  : RepairHistoryStrings.loadFailedTitle,
              style: TextStyle(color: cs.onError),
            ),
            backgroundColor: cs.error,
            behavior: SnackBarBehavior.floating,
          ));
        return;
      }
      setState(() {
        _loading = false;
        _offline = offline;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.repairId;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).backOr('/repairs/${widget.repairUuid}'),
        ),
        title: Text(id == null || id <= 0
            ? RepairHistoryStrings.titleNoId
            : RepairHistoryStrings.title(id)),
      ),
      body: _loading && _entries == null
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    final offline = _offline;
    final rows = [
      for (final entry in _entries ?? const <RepairHistoryEntry>[])
        if (entry.changes.isNotEmpty) entry,
    ];
    // EmptyState внутри ListView с AlwaysScrollableScrollPhysics — иначе на
    // пустом экране жест «потянуть вниз» не срабатывает.
    if (offline != null || rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (offline != null)
            EmptyState(
              icon: offline ? Icons.cloud_off_rounded : Icons.error_outline,
              title: offline
                  ? RepairStrings.noConnection
                  : RepairHistoryStrings.loadFailedTitle,
              hint: RepairHistoryStrings.loadFailedHint,
            )
          else
            const EmptyState(
              icon: Icons.history_rounded,
              title: RepairHistoryStrings.emptyTitle,
              hint: RepairHistoryStrings.emptyHint,
            ),
        ],
      );
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Лента событий, как блок «История изменений» в веб-админке: сверху число
    // событий, ниже — запись за записью, связанные линией.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              RepairHistoryStrings.eventsCount(rows.length),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          );
        }
        return _HistoryEvent(
          entry: rows[index - 1],
          isLast: index == rows.length,
        );
      },
    );
  }
}

/// Событие ленты: кружок автора слева, линия от него к следующему событию;
/// справа — «Морозов Д. А. закрытие ремонта», время и карточка изменений.
class _HistoryEvent extends StatelessWidget {
  final RepairHistoryEntry entry;

  /// Последнее (самое старое) событие — линии вниз нет.
  final bool isLast;

  const _HistoryEvent({required this.entry, required this.isLast});

  static const double _avatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // IntrinsicHeight — чтобы линия слева тянулась на всю высоту события,
    // вместе с отступом до следующего.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _avatarSize,
            child: Column(
              children: [
                _Avatar(entry: entry, size: _avatarSize),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.only(top: 4),
                      color: cs.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Как в вебе: время справа, а не влезает в строку — уходит
                  // на следующую. Длинное ФИО просто переносится.
                  Container(
                    constraints: const BoxConstraints(minHeight: _avatarSize),
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: entry.authorLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' '),
                              TextSpan(
                                text: entry.actionLabel,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ]),
                            style: tt.bodyMedium,
                          ),
                          Text(
                            RepairHistoryEntry.formatDateTime(entry.createdAt),
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingSM),
                  _ChangesCard(changes: entry.changes),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кружок автора: инициалы, у «Системы» — часы, без автора — «?».
class _Avatar extends StatelessWidget {
  final RepairHistoryEntry entry;
  final double size;

  const _Avatar({required this.entry, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // «Система» — серо-синим, как статус «Запланирован»: её запись — всегда
    // запуск запланированного ремонта по дате.
    final color = entry.isSystem ? cs.scheduled : cs.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: entry.isSystem
          ? Icon(Icons.schedule_rounded, size: 18, color: color)
          : Text(
              entry.initials ?? '?',
              style: tt.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Карточка изменений события: строки «подпись — было → стало».
class _ChangesCard extends StatelessWidget {
  final List<RepairHistoryChange> changes;

  const _ChangesCard({required this.changes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      // Карточка на всю ширину ленты, строки прижаты влево: у всех событий
      // карточки одного размера, подписи и значения — в один столбец.
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, change) in changes.indexed) ...[
            if (index > 0) Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              // Подпись над значением, а не слева, как в вебе: на ширине
              // телефона «было → стало» иначе не влезает в строку.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    change.label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  _ChangeValue(change: change),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «было → стало»: у статуса — пилюли (прежняя бледнее), у даты — прежняя
/// зачёркнута, новая жирным. Не влезает — переносится по стрелке.
class _ChangeValue extends StatelessWidget {
  final RepairHistoryChange change;

  const _ChangeValue({required this.change});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final from = change.from;
    final Widget to;
    Widget? was;
    if (change.isStatus) {
      to = RepairStatusPill(status: change.to, compact: true);
      if (from != null) {
        was = Opacity(
          opacity: 0.6,
          child: RepairStatusPill(status: from, compact: true),
        );
      }
    } else {
      to = Text(
        change.to,
        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
      if (from != null) {
        was = Text(
          from,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        );
      }
    }
    return Wrap(
      spacing: AppConstants.spacingSM,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (was != null) ...[
          was,
          Icon(
            Icons.arrow_forward_rounded,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
        ],
        to,
      ],
    );
  }
}
