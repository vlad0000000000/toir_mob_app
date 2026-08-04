import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../settings.dart';
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

  /// Компактный стиль для пары кнопок «Перезапустить»/«Обновить»: ужатые
  /// горизонтальные отступы, чтобы длинное «Перезапустить» помещалось в
  /// половину ширины и не переносилось на вторую строку.
  static final ButtonStyle _compactButtonStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    visualDensity: VisualDensity.compact,
  );

  bool _saving = false;
  PushDiagnostics? _push;
  bool _pushEnabled = true;
  bool _togglingPush = false;

  @override
  void initState() {
    super.initState();
    _pushEnabled = Settings.pushEnabled;
    _refreshPushStatus();
  }

  Future<void> _togglePush(bool value) async {
    setState(() {
      _pushEnabled = value;
      _togglingPush = true;
    });
    Settings.pushEnabled = value;
    try {
      if (value) {
        await PushNotificationsController.instance.start();
      } else {
        await PushNotificationsController.instance.stop();
      }
    } finally {
      if (mounted) setState(() => _togglingPush = false);
      await _refreshPushStatus();
    }
  }

  /// Технический `NotificationPermission.granted` → человеческий текст.
  String _permissionLabel(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('permanently')) {
      return 'Запрещены — включите вручную в настройках системы';
    }
    if (v.contains('granted')) return 'Разрешены';
    if (v.contains('denied')) return 'Не разрешены';
    return 'Статус неизвестен';
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
                    onChanged: (v) =>
                        _patch({'notifications_enabled': v}),
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
      Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border.all(color: cs.outlineVariant, width: 0.5),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD, vertical: 4),
          title: const Text('Push-уведомления'),
          subtitle: Text(
            _pushEnabled
                ? 'Приложение получает уведомления в фоне'
                : 'Уведомления в фоне отключены',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          value: _pushEnabled,
          onChanged: _togglingPush ? null : _togglePush,
        ),
      ),
      const SizedBox(height: AppConstants.spacingSM),
      // Диагностику и кнопки показываем только когда пуши включены.
      if (!_pushEnabled)
        const SizedBox.shrink()
      else if (p == null)
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
          subtitle: _permissionLabel(p.notificationPermission),
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
                style: _compactButtonStyle,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'Перезапустить',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _refreshPushStatus,
                style: _compactButtonStyle,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text(
                  'Обновить',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        size: 18, color: cs.onInfoContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Уведомления не приходят, хотя разрешение выдано?',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onInfoContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Чаще всего причина — включённая оптимизация батареи: система '
                  '«усыпляет» приложение и обрывает фоновый сервис. Кнопка '
                  '«Разрешить» сама это не чинит. Отключите оптимизацию вручную:',
                  style: tt.bodySmall?.copyWith(color: cs.onInfoContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Откройте Настройки телефона → Приложения → найдите это '
                  'приложение.\n'
                  '2. Перейдите в «Батарея» (или «Использование батареи»).\n'
                  '3. Выберите «Без ограничений» / «Не оптимизировать» '
                  'для этого приложения.\n'
                  '4. На Xiaomi/Huawei/Oppo дополнительно включите «Автозапуск».',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onInfoContainer,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Если кнопка «Разрешить» открывает выбор «Завершить действие '
                  'через…» — выберите системный диалог оптимизации батареи '
                  'и снимите ограничение для приложения.',
                  style: tt.bodySmall?.copyWith(color: cs.onInfoContainer),
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
    const types = {
      NotificationTypes.assignedInspection: 'Назначение осмотра',
      NotificationTypes.newTask: 'Новая задача',
      NotificationTypes.overdueTask: 'Просроченная задача',
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
