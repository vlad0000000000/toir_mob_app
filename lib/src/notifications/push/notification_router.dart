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

  /// Если приложение было запущено тапом по уведомлению — флаг ставится в
  /// `init()` и роутер при первом redirect консьюмит его, чтобы перейти
  /// на `/notifications` после авторизации.
  static bool get hasPendingOpen => _pendingOpen;

  static void consumePendingOpen() {
    _pendingOpen = false;
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
      openNotifications();
    }
  }

  /// Вызывается из колбэка тапа и из foreground-сервиса (`launchApp`)
  /// при наличии живого Navigator. Если Navigator ещё не готов —
  /// откладываем переход через [_pendingOpen], его подхватит redirect
  /// в GoRouter.
  static void openNotifications() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _pendingOpen = true;
      return;
    }
    try {
      // go() безопаснее clearStackAndNavigate(): не дёргает pop() в момент
      // ребилда виджет-дерева и просто заменяет текущий location.
      GoRouter.of(ctx).go('/notifications');
    } catch (e) {
      debugPrint('[PushRouter] navigate failed: $e');
      _pendingOpen = true;
    }
  }
}
