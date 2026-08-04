import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../global_state.dart';
import '../../settings.dart';
import '../model/inventory_record.dart';
import '../model/notification.dart';
import '../model/task.dart';
import '../utils/go_router_ext.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../widgets/empty_state.dart';
import 'notifications_service.dart';
import 'notification_card.dart';
import 'notification_formatters.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsService _service = NotificationsService.instance;
  final ScrollController _scrollController = ScrollController();
  Timer? _tickTimer;
  bool _hideRead = false;

  @override
  void initState() {
    super.initState();
    _hideRead = Settings.notificationsHideRead;
    _service.bootstrap();
    _scrollController.addListener(_onScroll);
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _service.loadMore();
    }
  }

  Future<void> _refresh() async {
    await _service.refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/actions');
          },
        ),
        title: const Text('Уведомления'),
        actions: [
          IconButton(
            tooltip: 'Настройки уведомлений',
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/notifications_settings');
            },
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _HeaderRow(
            unreadCount: _service.unreadCount,
            hideRead: _hideRead,
            onHideReadChanged: (v) {
              setState(() => _hideRead = v);
              Settings.notificationsHideRead = v;
            },
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _service.hasLoadedOnce,
              builder: (context, loadedOnce, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isLoading,
                  builder: (context, loading, __) {
                    return ValueListenableBuilder<List<AppNotification>>(
                      valueListenable: _service.notifications,
                      builder: (context, allItems, ___) {
                        return _buildBody(
                          context,
                          allItems: allItems,
                          loading: loading,
                          loadedOnce: loadedOnce,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<AppNotification> allItems,
    required bool loading,
    required bool loadedOnce,
  }) {
    final items = _hideRead
        ? allItems.where((n) => !n.isRead).toList()
        : allItems;
    // Пока сервер не ответил хоть раз — spinner, а не EmptyState.
    // Также показываем spinner, если запрос вышел в полёт, но
    // список ещё пустой (ручной pull-to-refresh с нуля).
    if (!loadedOnce || (loading && items.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.1),
            EmptyState(
              icon: _hideRead
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none_rounded,
              title: _hideRead
                  ? 'Всё прочитано'
                  : 'Уведомлений пока нет',
              hint: _hideRead
                  ? 'Здесь будут появляться новые уведомления о задачах и осмотрах.'
                  : 'Уведомления о задачах и осмотрах появятся здесь.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ValueListenableBuilder<bool>(
        valueListenable: _service.isLoadingMore,
        builder: (context, loadingMore, ___) {
          return ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
            itemCount: items.length + (loadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i >= items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final n = items[i];
              return NotificationCard(
                notification: n,
                onTap: () => _onTap(n),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.isRead) {
      await _service.markRead(n.uuid);
    }
    if (!mounted) return;
    _showDetail(n);
  }

  void _showDetail(AppNotification n) {
    InventoryRecord? equipment;
    if (n.equipmentUuid != null) {
      final matches = GlobalState.dataProvider.inventoryRecords
          .where((r) => r.uuid == n.equipmentUuid)
          .toList();
      if (matches.isNotEmpty) equipment = matches.first;
    }
    Task? task;
    if (n.inspectionUuid != null) {
      for (final t in GlobalState.dataProvider.taskBox.values) {
        if (t.uuid == n.inspectionUuid) {
          task = t;
          break;
        }
      }
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingMD,
                  0,
                  AppConstants.spacingMD,
                  AppConstants.spacingMD),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    NotificationFormatters.typeLabel(n).toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingSM),
                  Text(
                    n.title.isEmpty ? '—' : n.title,
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingMD),
                  Builder(builder: (_) {
                    final summary = NotificationFormatters.summaryDescription(
                        n,
                        multiline: true);
                    final desc = summary ??
                        NotificationFormatters.effectiveDescription(n);
                    if (desc.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppConstants.spacingMD),
                      child: Text(desc, style: tt.bodyMedium),
                    );
                  }),
                  Wrap(
                    spacing: AppConstants.spacingSM,
                    runSpacing: AppConstants.spacingSM,
                    children: [
                      _statusChip(n),
                      if (n.priorityDisplay != null &&
                          n.priorityDisplay!.isNotEmpty)
                        _priorityChip(n),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacingMD),
                  // «Исполнитель» в сводке по задачам не имеет смысла —
                  // скрываем по просьбе заказчика.
                  if (n.notificationType != NotificationTypes.summaryTask)
                    _metaRow(Icons.person_outline,
                        NotificationFormatters.executorLabel(n)),
                  Builder(builder: (_) {
                    // Для уведомлений о назначении осмотра: показываем дату
                    // создания самого осмотра (приходит в payload), а ниже
                    // — когда нам это уведомление прислали.
                    final src = NotificationFormatters.sourceCreatedAt(n);
                    final isInspection = n.notificationType ==
                            NotificationTypes.assignedInspection ||
                        n.notificationType ==
                            NotificationTypes.inspectionHighPriority;
                    if (src != null && isInspection) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _metaRow(
                            Icons.event_available_rounded,
                            'Осмотр создан ${NotificationFormatters.formatDateTime(src)}',
                          ),
                          _metaRow(
                            Icons.schedule_rounded,
                            'Уведомление ${NotificationFormatters.formatDateTime(n.createdAt)}',
                          ),
                        ],
                      );
                    }
                    return _metaRow(
                      Icons.schedule_rounded,
                      'Создано ${NotificationFormatters.formatDateTime(n.createdAt)}',
                    );
                  }),
                  if (task != null) ...[
                    const SizedBox(height: AppConstants.spacingLG),
                    _sectionDivider('Задача'),
                    ..._buildTaskInfo(
                      task,
                      hideComment: n.notificationType ==
                              NotificationTypes.assignedInspection ||
                          n.notificationType ==
                              NotificationTypes.inspectionHighPriority,
                    ),
                  ],
                  if (equipment != null) ...[
                    const SizedBox(height: AppConstants.spacingLG),
                    _sectionDivider('Оборудование'),
                    ..._buildEquipmentInfo(equipment),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metaRow(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider(String label) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingMD),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
        ],
      ),
    );
  }

  /// Чип приоритета в детальной карточке — тот же цветной стиль, что и в
  /// общем списке (`_PriorityPill`): цвет помогает быстро сориентироваться,
  /// а раньше тут был нейтральный серый и сбивал с толку.
  Widget _priorityChip(AppNotification n) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = switch (n.priority) {
      'high' => cs.priorityHigh,
      'medium' => cs.priorityMedium,
      'low' => cs.priorityLow,
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(n.priorityDisplay ?? '',
              style: tt.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _buildTaskInfo(Task task, {bool hideComment = false}) {
    final widgets = <Widget>[];
    final pt = task.periodicTask;
    if (pt != null) {
      if (pt.title.isNotEmpty) {
        widgets.add(_kv('Название', pt.title));
      }
      if (pt.description != null && pt.description!.isNotEmpty) {
        widgets.add(_kv('Описание', pt.description!));
      }
      if (pt.periodicityRuleDisplay.isNotEmpty) {
        widgets.add(_kv('Периодичность', pt.periodicityRuleDisplay));
      }
      if (pt.nextDueAt != null) {
        widgets.add(
            _kv('Срок', NotificationFormatters.formatDateTime(pt.nextDueAt!)));
      }
      if (pt.node != null && pt.node!.isNotEmpty) {
        widgets.add(_kv('Узел', pt.node!));
      }
    }
    // Для уведомлений типа «Назначение осмотра» комментарий относится
    // к самому осмотру и уже выведен в карточке выше — здесь дублировать
    // не нужно.
    if (!hideComment && task.comment != null && task.comment!.isNotEmpty) {
      widgets.add(_kv('Комментарий', task.comment!));
    }
    if (task.roles.isNotEmpty) {
      widgets.add(_kv('Роли', task.roles.join(', ')));
    }
    if (widgets.isEmpty) {
      widgets.add(Text('—',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }
    return widgets;
  }

  List<Widget> _buildEquipmentInfo(InventoryRecord eq) {
    final widgets = <Widget>[
      _kv('Название', eq.name),
    ];
    if (eq.typeModel != null && eq.typeModel!.isNotEmpty) {
      widgets.add(_kv('Тип / модель', eq.typeModel!));
    }
    if (eq.serialNumber != null && eq.serialNumber!.isNotEmpty) {
      widgets.add(_kv('Серийный номер', eq.serialNumber!));
    }
    if (eq.location != null && eq.location!.isNotEmpty) {
      widgets.add(_kv('Местоположение', eq.location!));
    }
    if (eq.manufacturer != null && eq.manufacturer!.isNotEmpty) {
      widgets.add(_kv('Производитель', eq.manufacturer!));
    }
    if (eq.description != null && eq.description!.isNotEmpty) {
      widgets.add(_kv('Описание', eq.description!));
    }
    return widgets;
  }

  Widget _kv(String key, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: tt.bodyMedium),
        ],
      ),
    );
  }

  Widget _statusChip(AppNotification n) {
    final tt = Theme.of(context).textTheme;
    final status = NotificationFormatters.effectiveStatus(n);
    final color = NotificationFormatters.statusColor(context, status);
    final label = NotificationStatuses.displayName(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: tt.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

/// Шапка над списком: слева — chip со счётчиком непрочитанных
/// («N новых», если > 0), справа — переключатель «Скрыть прочитанные».
/// Counter вынесен из AppBar title, потому что при больших числах title
/// не помещается и тайтл обрезается на узких экранах.
class _HeaderRow extends StatelessWidget {
  final ValueNotifier<int> unreadCount;
  final bool hideRead;
  final ValueChanged<bool> onHideReadChanged;

  const _HeaderRow({
    required this.unreadCount,
    required this.hideRead,
    required this.onHideReadChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      child: Container(
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD, 6, AppConstants.spacingSM, 4),
          child: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: unreadCount,
                builder: (context, count, _) {
                  if (count <= 0) {
                    return Text(
                      'Все прочитаны',
                      style: tt.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    );
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$count новых',
                          style: tt.labelMedium?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(),
              Text(
                'Скрыть прочитанные',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Switch(
                value: hideRead,
                onChanged: onHideReadChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
