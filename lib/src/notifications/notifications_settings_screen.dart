import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    final p = _push;
    return [
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Push в фоне (Android)',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      if (p == null)
        const ListTile(
          dense: true,
          title: Text('Проверяю статус…'),
        )
      else ...[
        ListTile(
          dense: true,
          leading: Icon(
            p.serviceRunning ? Icons.check_circle : Icons.cancel,
            color: p.serviceRunning ? Colors.green : Colors.red,
          ),
          title: const Text('Фоновый сервис'),
          subtitle: Text(p.serviceRunning ? 'Запущен' : 'Остановлен'),
        ),
        ListTile(
          dense: true,
          leading: Icon(
            p.notificationPermission.contains('granted')
                ? Icons.check_circle
                : Icons.cancel,
            color: p.notificationPermission.contains('granted')
                ? Colors.green
                : Colors.red,
          ),
          title: const Text('Разрешение на уведомления'),
          subtitle: Text(p.notificationPermission),
        ),
        ListTile(
          dense: true,
          leading: Icon(
            p.batteryOptIgnored ? Icons.check_circle : Icons.warning_amber,
            color: p.batteryOptIgnored ? Colors.green : Colors.orange,
          ),
          title: const Text('Игнорировать оптимизацию батареи'),
          subtitle: Text(p.batteryOptIgnored
              ? 'Разрешено'
              : 'Не разрешено — система может убивать сервис'),
          trailing: p.batteryOptIgnored
              ? null
              : TextButton(
                  onPressed: _requestBattery,
                  child: const Text('Разрешить'),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _restartPush,
                icon: const Icon(Icons.refresh),
                label: const Text('Перезапустить сервис'),
              ),
              OutlinedButton.icon(
                onPressed: _refreshPushStatus,
                icon: const Icon(Icons.info_outline),
                label: const Text('Обновить статус'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'Подсказка: если кнопка «Разрешить» открывает выбор «Завершить '
            'действие через…» — выберите «Настройки» или системный диалог '
            'оптимизации батареи и снимите ограничение для приложения.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
