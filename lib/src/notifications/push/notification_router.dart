import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

/// Маршрутизация тапа по push-уведомлению.
///
/// Сами уведомления показываются из изолята фонового сервиса
/// (`notifications_task_handler.dart`). Для того чтобы тап обработать в
/// основном изоляте и перейти на `/notifications`, плагин нужно
/// проинициализировать ещё и в `main()` с собственным колбэком.
class PushNotificationRouter {
  PushNotificationRouter._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _pendingOpen = false;

  /// Ремонт, который надо открыть по тапу. Если задан — переходим прямо в
  /// карточку, иначе на общий экран уведомлений.
  static String? _pendingRepairUuid;

  /// Если приложение было запущено тапом по уведомлению — флаг ставится в
  /// `init()` и роутер при первом redirect консьюмит его, чтобы перейти
  /// на нужный экран после авторизации.
  static bool get hasPendingOpen => _pendingOpen;

  /// Маршрут отложенного перехода: карточка ремонта либо центр уведомлений.
  static String get pendingLocation => _pendingRepairUuid == null
      ? '/notifications'
      : '/repairs/$_pendingRepairUuid';

  static void consumePendingOpen() {
    _pendingOpen = false;
    _pendingRepairUuid = null;
  }

  static Future<void> init() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse _) {
          openNotifications();
        },
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _pendingOpen = true;
      }
      // Cold-start через launchApp() из background-изолята: contentIntent
      // самого пуша может не сработать (свернули → нажали уведомление), но
      // фоновый изолят успел сохранить флажок.
      try {
        final pending =
            await FlutterForegroundTask.getData<bool>(key: 'push_tap_pending');
        if (pending == true) {
          _pendingOpen = true;
          await FlutterForegroundTask.removeData(key: 'push_tap_pending');
          final repairUuid = await FlutterForegroundTask.getData<String>(
              key: 'push_tap_repair');
          if (repairUuid != null && repairUuid.isNotEmpty) {
            _pendingRepairUuid = repairUuid;
          }
          await FlutterForegroundTask.removeData(key: 'push_tap_repair');
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[PushRouter] init failed: $e');
    }

    // Слушаем сигналы из изолята foreground-сервиса. Подписку держим прямо
    // тут, чтобы тап по пушу обрабатывался независимо от того, был ли уже
    // позван NotificationsService.bootstrap() (он подписан отдельно для
    // refresh’а списка).
    try {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    } catch (e) {
      debugPrint('[PushRouter] addTaskDataCallback failed: $e');
    }
  }

  static void _onTaskData(Object data) {
    if (data is Map && data['type'] == 'push_tap') {
      final repairUuid = data['repair_uuid'];
      openNotifications(
        repairUuid:
            repairUuid is String && repairUuid.isNotEmpty ? repairUuid : null,
      );
    }
  }

  /// Вызывается из колбэка тапа и из foreground-сервиса (`launchApp`)
  /// при наличии живого Navigator. Если Navigator ещё не готов —
  /// откладываем переход через [_pendingOpen], его подхватит redirect
  /// в GoRouter.
  static void openNotifications({String? repairUuid}) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _pendingOpen = true;
      _pendingRepairUuid = repairUuid;
      return;
    }
    try {
      // go() безопаснее clearStackAndNavigate(): не дёргает pop() в момент
      // ребилда виджет-дерева и просто заменяет текущий location.
      GoRouter.of(ctx).go(
        repairUuid == null ? '/notifications' : '/repairs/$repairUuid',
      );
    } catch (e) {
      debugPrint('[PushRouter] navigate failed: $e');
      _pendingOpen = true;
      _pendingRepairUuid = repairUuid;
    }
  }
}
