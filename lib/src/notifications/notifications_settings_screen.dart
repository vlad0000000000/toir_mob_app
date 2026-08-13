import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/notification.dart';
import '../model/notification_settings.dart';
import 'notifications_service.dart';
import 'push/push_notifications_controller.dart';

// Скрываем всё, кроме блока «Push в фоне (Android)». Логика обработчиков
// сохранена, чтобы при необходимости вернуть UI флагом.
// ignore: prefer_const_declarations
final bool _kShowAdvancedSettings = false;

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  final NotificationsService _service = NotificationsService.instance;
  bool _saving = false;
  PushDiagnostics? _push;

  @override
  void initState() {
    super.initState();
    _refreshPushStatus();
  }

  Future<void> _refreshPushStatus() async {
    final d = await PushNotificationsController.instance.diagnose();
    if (mounted) setState(() => _push = d);
  }

  Future<void> _patch(Map<String, dynamic> partial) async {
    setState(() => _saving = true);
    try {
      await _service.updateSettings(partial);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить настройки')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        title: const Text('Настройки уведомлений'),
      ),
      body: ValueListenableBuilder<NotificationSettings>(
        valueListenable: _service.settings,
        builder: (context, s, _) {
          return AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (_kShowAdvancedSettings) ...[
                  SwitchListTile(
                    title: const Text('Уведомления включены'),
                    value: s.notificationsEnabled,
                    onChanged: (v) => _patch({'notifications_enabled': v}),
                  ),
                  SwitchListTile(
                    title: const Text('Мгновенные уведомления (realtime)'),
                    subtitle:
                        const Text('Подключение SSE для немедленных событий'),
                    value: s.realtimeEnabled,
                    onChanged: s.notificationsEnabled
                        ? (v) => _patch({'realtime_enabled': v})
                        : null,
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Типы уведомлений',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ..._buildTypeSwitches(s),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Статусы',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ..._buildStatusSwitches(s),
                  const Divider(),
                  ListTile(
                    title: const Text('Горизонт показа задач (дней вперёд)'),
                    subtitle: Text(s.maxFutureDays == null
                        ? 'Без ограничения'
                        : '${s.maxFutureDays} дн.'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editMaxFutureDays(s),
                  ),
                ],
                if (!kIsWeb && Platform.isAndroid) ..._buildPushSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPushSection() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = _push;
    final notifGranted = p?.notificationPermission.contains('granted') ?? false;

    Widget statusRow({
      required bool ok,
      required String title,
      required String subtitle,
      bool warning = false,
      Widget? trailing,
    }) {
      final color = ok
          ? cs.success
          : warning
              ? cs.warning
              : cs.error;
      return Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSM),
        padding: const EdgeInsets.all(AppConstants.spacingMD),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border.all(color: cs.outlineVariant, width: 0.5),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
              ),
              child: Icon(
                ok
                    ? Icons.check_circle_rounded
                    : (warning
                        ? Icons.warning_amber_rounded
                        : Icons.cancel_rounded),
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: AppConstants.spacingMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            4, AppConstants.spacingMD, 4, AppConstants.spacingSM),
        child: Text(
          'PUSH В ФОНЕ (ANDROID)',
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (p == null)
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant, width: 0.5),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Text('Проверяю статус…', style: tt.bodyMedium),
            ],
          ),
        )
      else ...[
        statusRow(
          ok: p.serviceRunning,
          title: 'Фоновый сервис',
          subtitle: p.serviceRunning ? 'Запущен' : 'Остановлен',
        ),
        statusRow(
          ok: notifGranted,
          title: 'Разрешение на уведомления',
          subtitle: p.notificationPermission,
        ),
        statusRow(
          ok: p.batteryOptIgnored,
          warning: !p.batteryOptIgnored,
          title: 'Игнорировать оптимизацию батареи',
          subtitle: p.batteryOptIgnored
              ? 'Разрешено'
              : 'Система может убивать сервис',
          trailing: p.batteryOptIgnored
              ? null
              : FilledButton.tonal(
                  onPressed: _requestBattery,
                  child: const Text('Разрешить'),
                ),
        ),
        const SizedBox(height: AppConstants.spacingSM),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _restartPush,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Перезапустить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _refreshPushStatus,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Обновить'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMD),
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.infoContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 18, color: cs.onInfoContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Если «Разрешить» открывает выбор «Завершить действие '
                    'через…» — выберите «Настройки» или системный диалог '
                    'оптимизации батареи и снимите ограничение для приложения.',
                    style: tt.bodySmall?.copyWith(color: cs.onInfoContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  Future<void> _requestBattery() async {
    final ok = await PushNotificationsController.instance
        .requestBatteryOptimizationException();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          ok ? 'Разрешение получено' : 'Разрешение не выдано — попробуйте ещё'),
    ));
    _refreshPushStatus();
  }

  Future<void> _restartPush() async {
    await PushNotificationsController.instance.stop();
    final ok = await PushNotificationsController.instance.start();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Сервис перезапущен' : 'Сервис не стартовал'),
    ));
    _refreshPushStatus();
  }

  List<Widget> _buildTypeSwitches(NotificationSettings s) {
    // Полный набор типов, которые сервер шлёт в мобильное приложение
    // (`MOBILE_NOTIFICATION_TYPES`). Раньше здесь было только три из них, и
    // выключить уведомления по ремонтам или сводку было нечем — переключатели
    // просто отсутствовали, хотя сервер такие настройки принимает.
    const types = {
      NotificationTypes.assignedInspection: 'Назначение осмотра',
      NotificationTypes.newTask: 'Новая задача',
      NotificationTypes.overdueTask: 'Просроченная задача',
      NotificationTypes.summaryTask: 'Сводка по задачам',
      NotificationTypes.repairAssigned: 'Назначен ремонт',
      NotificationTypes.repairReturnedForRework: 'Ремонт на доработку',
    };
    return types.entries.map((e) {
      final value = s.typePreferences[e.key] ?? true;
      return SwitchListTile(
        title: Text(e.value),
        value: value,
        onChanged: s.notificationsEnabled
            ? (v) => _patch({
                  'type_preferences': {e.key: v},
                })
            : null,
      );
    }).toList();
  }

  List<Widget> _buildStatusSwitches(NotificationSettings s) {
    const statuses = {
      NotificationStatuses.newStatus: 'Новая',
      NotificationStatuses.viewed: 'Просмотрена',
      NotificationStatuses.completed: 'Выполнена',
      NotificationStatuses.overdue: 'Просрочена',
      NotificationStatuses.unassigned: 'Не назначена',
    };
    return statuses.entries.map((e) {
      final value = s.statusPreferences[e.key] ?? true;
      return SwitchListTile(
        title: Text(e.value),
        value: value,
        onChanged: s.notificationsEnabled
            ? (v) => _patch({
                  'status_preferences': {e.key: v},
                })
            : null,
      );
    }).toList();
  }

  Future<void> _editMaxFutureDays(NotificationSettings s) async {
    final controller =
        TextEditingController(text: s.maxFutureDays?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Горизонт показа задач'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Например, 30 (пусто = без ограничения)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(-1),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) {
                  Navigator.of(ctx).pop(null);
                } else {
                  final parsed = int.tryParse(v);
                  Navigator.of(ctx).pop(parsed);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    if (result == -1) return;
    await _patch({'max_future_days': result});
  }
}
