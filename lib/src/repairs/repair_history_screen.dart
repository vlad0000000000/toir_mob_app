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

/// «История ремонта №…» (макет 14i): создание, переносы даты начала и смены
/// статуса, новые сверху. Автор — «Система» (запуск по дате), «Сидоров А. И.»
/// или «Автор неизвестен».
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppConstants.spacingSM),
      itemBuilder: (context, index) => _HistoryCard(entry: rows[index]),
    );
  }
}

/// Запись истории: автор пилюлей и время, ниже — что изменилось.
class _HistoryCard extends StatelessWidget {
  final RepairHistoryEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // «Система» — серо-синим, как статус «Запланирован»: её запись — всегда
    // запуск запланированного ремонта по дате.
    final authorColor = entry.isSystem ? cs.scheduled : cs.onSurface;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrap, а не Row: с длинным ФИО дата уходит на вторую строку, а
          // пилюля ужимается до ширины карточки и обрезается многоточием.
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: AppConstants.spacingSM,
              runSpacing: AppConstants.spacingXS,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: entry.isSystem
                          ? cs.scheduled.withValues(alpha: 0.12)
                          : cs.surfaceContainerHigh,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      entry.authorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(
                        color: authorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Text(
                  RepairHistoryEntry.formatDateTime(entry.createdAt),
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final (label, value) in entry.changes) ...[
            const SizedBox(height: AppConstants.spacingSM),
            Text('$label · $value', style: tt.bodyLarge),
          ],
        ],
      ),
    );
  }
}
