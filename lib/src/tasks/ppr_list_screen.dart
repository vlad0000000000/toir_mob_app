import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/model/ppr.dart';
import '../../src/model/task.dart';
import '../design/app_constants.dart';
import '../widgets/empty_state.dart';
import 'equipment_detail_screen.dart' show pprGroupColor;
import 'periodic_task_card.dart';

/// Список актуальных ППР: каждый ППР — сворачиваемый блок (по аналогии с
/// группами задач оборудования), внутри — задачи именно этого ППР.
/// У ППР может не быть названия — тогда в заголовке просто «ППР».
class PprListScreen extends StatefulWidget {
  const PprListScreen({super.key});

  @override
  State<PprListScreen> createState() => _PprListScreenState();
}

class _PprListScreenState extends State<PprListScreen> {
  /// UUID развёрнутых блоков. Единственный ППР раскрываем сразу — иначе
  /// экран выглядит как список из одной строки.
  final Set<String> _expanded = {};
  bool _autoExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: FutureBuilder<void>(
        future: GlobalState.syncMainOnce(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 8,
                constraints:
                    const BoxConstraints(minHeight: 128, minWidth: 128),
              ),
            );
          }

          final provider = GlobalState.dataProvider;
          // Тот же источник, что и у кнопки «ППР» на главном экране, —
          // кнопка не должна вести на пустой список.
          final entries = provider
              .pprsWithTasks()
              .map((ppr) => _PprEntry(ppr, provider.getTasksForPpr(ppr.uuid)))
              .where((entry) => entry.tasks.isNotEmpty)
              .toList();

          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.event_repeat_rounded,
              title: 'Нет задач ППР',
              hint: 'В активных ППР нет задач, назначенных на вас.',
            );
          }

          if (!_autoExpanded && entries.length == 1) {
            _autoExpanded = true;
            _expanded.add(entries.first.ppr.uuid);
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spacingMD,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) => _PprCard(
              entry: entries[index],
              expanded: _expanded.contains(entries[index].ppr.uuid),
              onExpansionChanged: (value) {
                setState(() {
                  final uuid = entries[index].ppr.uuid;
                  if (value) {
                    _expanded.add(uuid);
                  } else {
                    _expanded.remove(uuid);
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }
}

class _PprEntry {
  final Ppr ppr;
  final List<Task> tasks;

  _PprEntry(this.ppr, this.tasks);
}

/// Блок одного ППР. Раскладка повторяет карточки групп на экране задач
/// оборудования: цветная полоса слева, заголовок, счётчик, ExpansionTile.
class _PprCard extends StatelessWidget {
  final _PprEntry entry;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;

  const _PprCard({
    required this.entry,
    required this.expanded,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ppr = entry.ppr;

    // Считаем задачи пользователя, а не весь ППР: задачи чужих ролей
    // обходчик не увидит никогда, и общий счётчик выглядел бы недостижимым.
    final progress = GlobalState.dataProvider.pprProgressForUser(ppr);
    final subtitleParts = <String>[
      if (ppr.statusLabel.isNotEmpty) ppr.statusLabel,
      if (progress.total > 0)
        'выполнено ${progress.done} из ${progress.total}',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
          vertical: AppConstants.spacingSM / 2 + 2),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: pprGroupColor),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ExpansionTile(
              key: PageStorageKey<String>(ppr.uuid),
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: expanded,
              tilePadding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMD),
              title: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ppr.displayTitle,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitleParts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitleParts.join(' · '),
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      '${entry.tasks.length}',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more_rounded),
              ),
              childrenPadding: const EdgeInsets.only(
                left: AppConstants.spacingMD,
                right: AppConstants.spacingMD,
                bottom: AppConstants.spacingMD,
              ),
              onExpansionChanged: onExpansionChanged,
              children:
                  entry.tasks.map((task) => _PprTaskItem(task: task)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Задача ППР: название периодической задачи и оборудование, по тапу —
/// переход к задачам этого оборудования, где осмотр и выполняется.
class _PprTaskItem extends StatelessWidget {
  final Task task;

  const _PprTaskItem({required this.task});

  void _openEquipment(BuildContext context) {
    final equipmentUuid = task.equipmentUuid;
    final records = GlobalState.dataProvider.inventoryRecords
        .where((record) => record.uuid == equipmentUuid)
        .toList();
    if (records.isEmpty) return;
    // `from=ppr` — чтобы кнопка «назад» вернула на список ППР, а не на задачи.
    GoRouter.of(context).go('/details/${records.first.id}?from=ppr');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final periodicTask = task.periodicTask;

    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingSM),
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openEquipment(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                AppConstants.spacingMD - 2,
                AppConstants.spacingSM,
                AppConstants.spacingMD - 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        periodicTask?.title ?? 'Назначенная задача',
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (periodicTask != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          periodicTask.equipment.name,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (periodicTask != null)
                  IconButton(
                    icon: const Icon(Icons.info_outline_rounded),
                    visualDensity: VisualDensity.compact,
                    color: cs.onSurfaceVariant,
                    onPressed: () => showPeriodicTaskCard(context, periodicTask),
                    tooltip: 'Карточка периодической задачи',
                  ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
