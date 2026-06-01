import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_scan_industry/src/update_manager.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/design/app_constants.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../strings.dart';
import '../../settings.dart';
import '../widgets/app_bottom_sheet.dart';

/// Главный hub-экран: hero-карточка «Сканировать», ряд вторичных действий,
/// сворачиваемый раздел «Сервис» для редко используемых операций.
class QRActions extends StatefulWidget {
  const QRActions({super.key});

  @override
  State<QRActions> createState() => _QRActionsState();
}

class _QRActionsState extends State<QRActions> {
  bool _serviceExpanded = false;

  @override
  void initState() {
    super.initState();
    if (GlobalState.isAuthorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationsService.instance.bootstrap();
        // Страховка: после свежей установки логин мог не дотянуть до
        // запуска foreground-сервиса (диалог разрешения, race с навигацией
        // и т. п.). На /actions точно есть стабильный UI — поднимаем
        // сервис, если он не запущен.
        PushNotificationsController.instance.ensureRunning();
      });
    }
  }

  void _onScan() {
    GlobalState.dataProvider.mainSync();
    GoRouter.of(context).clearStackAndNavigate('/qr_scanner');
  }

  void _onInspection() {
    GlobalState.dataProvider.mainSync();
    GoRouter.of(context).clearStackAndNavigate('/problems');
  }

  void _onTasks() {
    GlobalState.allowSyncMainOnce = true;
    GoRouter.of(context).clearStackAndNavigate('/tasks');
  }

  void _onNotifications() {
    GoRouter.of(context).clearStackAndNavigate('/notifications');
  }

  Future<void> _onSync() async {
    final result = await GlobalState.dataProvider.syncDataAndScans();
    if (!mounted) return;
    switch (result) {
      case SyncResult.noConnection:
        Dialogs.notify(context, 'Отсутствует соединение с сервером', '');
      case SyncResult.allSynced:
        Dialogs.notify(context, 'Все данные успешно синхронизированы', '');
      case SyncResult.scansSynced:
        Dialogs.notify(
            context, 'Все данные и осмотры успешно синхронизированы', '');
      case SyncResult.scansFailed:
        Dialogs.notify(
            context, 'Не получилось синхронизировать осмотры', '');
    }
  }

  Future<void> _onResetScans() async {
    await GlobalState.dataProvider.scanBox.clear();
    await GlobalState.dataProvider.scanPendingBox.clear();
    if (!mounted) return;
    Dialogs.notify(context, 'Осмотры успешно сброшены', '');
  }

  Future<void> _onInfo() async {
    final info = await GlobalState.buildInfo();
    if (!mounted) return;
    Dialogs.notifyMD(context, 'Информация', '', info);
  }

  void _onSettings() {
    showAppModalSheet(
      context,
      child: const _SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateManager.checkForUpdate(context);
    });

    final allowRequestsWithoutQr =
        GlobalState.dataProvider.company?.allowRequestsWithoutQr ?? false;

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingXL,
        ),
        children: [
          _PrimaryActionCard(
            icon: Icons.qr_code_scanner_rounded,
            title: Strings.scanner,
            subtitle: 'Откройте камеру и наведите на QR-код оборудования',
            onTap: _onScan,
          ),
          const SizedBox(height: AppConstants.spacingMD),
          Row(
            children: [
              Expanded(
                child: _SecondaryActionCard(
                  icon: Icons.checklist_rounded,
                  label: Strings.tasks,
                  onTap: _onTasks,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: _NotificationsCard(onTap: _onNotifications),
              ),
            ],
          ),
          if (allowRequestsWithoutQr) ...[
            const SizedBox(height: AppConstants.spacingMD),
            _SecondaryActionCard(
              icon: Icons.warehouse_outlined,
              label: 'Осмотр оборудования или ТМЦ',
              onTap: _onInspection,
              fullWidth: true,
            ),
          ],
          const SizedBox(height: AppConstants.spacingXL),
          _ServiceSection(
            expanded: _serviceExpanded,
            onToggle: (v) {
              setState(() => _serviceExpanded = v);
              if (v &&
                  Settings.onboardingInProgress &&
                  Settings.onboardingStep == 5) {
                GoRouter.of(context)
                    .clearStackAndNavigate('/onboarding_video');
              }
            },
            items: [
              _ServiceItem(
                icon: Icons.sync_rounded,
                label: Strings.syncData,
                onTap: _onSync,
              ),
              _ServiceItem(
                icon: Icons.delete_outline_rounded,
                label: 'Сбросить осмотры',
                onTap: _onResetScans,
                destructive: true,
              ),
              _ServiceItem(
                icon: Icons.info_outline_rounded,
                label: 'Информация',
                onTap: _onInfo,
              ),
              _ServiceItem(
                icon: Icons.settings_outlined,
                label: 'Настройки',
                onTap: _onSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hero scan card
// ─────────────────────────────────────────────────────────────────────────
class _PrimaryActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PrimaryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLG),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: Icon(icon, color: cs.onPrimary, size: 36),
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingSM),
              Icon(Icons.arrow_forward_rounded, color: cs.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Secondary action tiles
// ─────────────────────────────────────────────────────────────────────────
class _SecondaryActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _SecondaryActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant, width: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: fullWidth
              ? Row(
                  children: [
                    _IconCircle(icon: icon),
                    const SizedBox(width: AppConstants.spacingMD),
                    Expanded(
                      child: Text(
                        label,
                        style: tt.titleMedium,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconCircle(icon: icon),
                    const SizedBox(height: AppConstants.spacingMD),
                    Text(
                      label,
                      style: tt.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Открыть',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  const _IconCircle({required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Icon(icon, color: cs.onSecondaryContainer, size: 24),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Notifications tile with badge
// ─────────────────────────────────────────────────────────────────────────
class _NotificationsCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationsService.instance.unreadCount,
      builder: (context, count, _) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        return Material(
          color: cs.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: cs.outlineVariant, width: 0.5),
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                        ),
                        child: Icon(
                          count > 0
                              ? Icons.notifications_rounded
                              : Icons.notifications_outlined,
                          color: cs.onSecondaryContainer,
                          size: 24,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.error,
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                              border:
                                  Border.all(color: cs.surface, width: 2),
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onError,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacingMD),
                  Text(
                    'Уведомления',
                    style: tt.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count > 0 ? '$count новых' : 'Нет новых',
                    style: tt.bodySmall?.copyWith(
                      color: count > 0 ? cs.error : cs.onSurfaceVariant,
                      fontWeight: count > 0
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Сервисная секция: компактные строки, по умолчанию свёрнута
// ─────────────────────────────────────────────────────────────────────────
class _ServiceItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  _ServiceItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

class _ServiceSection extends StatelessWidget {
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final List<_ServiceItem> items;

  const _ServiceSection({
    required this.expanded,
    required this.onToggle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          onTap: () => onToggle(!expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: AppConstants.spacingSM),
            child: Row(
              children: [
                Text(
                  'Сервис',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  expanded ? 'Скрыть' : 'Показать',
                  style: tt.labelMedium?.copyWith(color: cs.primary),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: expanded
              ? Container(
                  margin: const EdgeInsets.only(top: AppConstants.spacingSM),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border.all(
                        color: cs.outlineVariant, width: 0.5),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusLG),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: cs.outlineVariant,
                            indent: 60,
                          ),
                        _ServiceTile(item: items[i]),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final _ServiceItem item;
  const _ServiceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = item.destructive ? cs.error : cs.onSurface;
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: AppConstants.spacingMD),
        child: Row(
          children: [
            Icon(item.icon, color: fg, size: 22),
            const SizedBox(width: AppConstants.spacingMD),
            Expanded(
              child: Text(
                item.label,
                style: tt.bodyLarge?.copyWith(color: fg),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Settings sheet
// ─────────────────────────────────────────────────────────────────────────
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _tasksFirst;
  late bool _simplified;

  @override
  void initState() {
    super.initState();
    _tasksFirst = Settings.qrResultShowTasksFirst;
    _simplified = Settings.qrResultShowSimplifiedView;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMD, 0, AppConstants.spacingMD, AppConstants.spacingMD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Настройки',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _tasksFirst,
              onChanged: (v) {
                setState(() => _tasksFirst = v);
                Settings.qrResultShowTasksFirst = v;
              },
              title: Text(
                'Сразу показывать задачи',
                style: tt.bodyLarge,
              ),
              subtitle: Text(
                'После сканирования сначала откроется список задач',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _simplified,
              onChanged: (v) {
                setState(() => _simplified = v);
                Settings.qrResultShowSimplifiedView = v;
              },
              title: Text(
                'Упрощённый вид станка',
                style: tt.bodyLarge,
              ),
              subtitle: Text(
                'Скрыть подробный паспорт оборудования',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Settings.resetOnboarding();
                  GoRouter.of(context).clearStackAndNavigate('/onboarding');
                },
                icon: const Icon(Icons.school_outlined),
                label: const Text('Пройти обучение заново'),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSM),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
