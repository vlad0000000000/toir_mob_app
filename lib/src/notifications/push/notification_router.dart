import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../notifications_service.dart';
import 'notifications_task_handler.dart';

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

  /// Уведомление, по пушу которого тапнули, пока приложение ещё не было
  /// готово (холодный старт): отметим прочитанным после входа —
  /// [markPendingRead].
  static String? _pendingReadUuid;

  /// Отмечает прочитанным уведомление, открытое тапом по пушу.
  ///
  /// Раньше тап по пушу открывал экран уведомлений или карточку ремонта и
  /// ничего не отмечал: уведомление оставалось «Новым», хотя обходчик его
  /// открыл, — а из карточки ремонта он в список и не заходит.
  static void _markRead(String? notificationUuid, {required bool appReady}) {
    if (notificationUuid == null) return;
    if (!appReady) {
      _pendingReadUuid = notificationUuid;
      return;
    }
    unawaited(NotificationsService.instance.markRead(notificationUuid));
  }

  /// Досылает отметку, отложенную на холодном старте. Зовётся из redirect
  /// роутера, когда вход уже выполнен.
  static void markPendingRead() {
    final uuid = _pendingReadUuid;
    if (uuid == null) return;
    _pendingReadUuid = null;
    unawaited(NotificationsService.instance.markRead(uuid));
  }

  static Future<void> init() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          openNotifications(
            notificationUuid: pushNotificationUuidOf(response.payload),
          );
        },
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _pendingOpen = true;
        _markRead(
          pushNotificationUuidOf(launchDetails?.notificationResponse?.payload),
          appReady: false,
        );
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
        // Отдельно от флага: фоновый изолят сохраняет uuid и тогда, когда
        // основной жив и переход сделал сам, — снимаем в любом случае, чтобы
        // он не всплыл на следующем запуске.
        final notificationUuid = await FlutterForegroundTask.getData<String>(
            key: pushTapNotificationKey);
        if (notificationUuid != null && notificationUuid.isNotEmpty) {
          if (pending == true) _markRead(notificationUuid, appReady: false);
          await FlutterForegroundTask.removeData(key: pushTapNotificationKey);
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
      final notificationUuid = data['notification_uuid'];
      openNotifications(
        repairUuid:
            repairUuid is String && repairUuid.isNotEmpty ? repairUuid : null,
        notificationUuid:
            notificationUuid is String && notificationUuid.isNotEmpty
                ? notificationUuid
                : null,
      );
    }
  }

  /// Вызывается из колбэка тапа и из foreground-сервиса (`launchApp`)
  /// при наличии живого Navigator. Если Navigator ещё не готов —
  /// откладываем переход через [_pendingOpen], его подхватит redirect
  /// в GoRouter.
  /// Снимает метки тапа, сохранённые фоновым изолятом для холодного старта.
  ///
  /// Фоновый изолят ставит их на каждый тап, а снимал их только холодный
  /// старт. Если приложение было открыто и переход сделало само, метки
  /// оставались, и следующий обычный запуск прыгал на экран уведомлений или
  /// в давно открытую карточку ремонта.
  static Future<void> _clearStoredTap() async {
    try {
      await FlutterForegroundTask.removeData(key: 'push_tap_pending');
      await FlutterForegroundTask.removeData(key: 'push_tap_repair');
      await FlutterForegroundTask.removeData(key: pushTapNotificationKey);
    } catch (_) {}
  }

  static void openNotifications({
    String? repairUuid,
    String? notificationUuid,
  }) {
    final ctx = navigatorKey.currentContext;
    // Живой Navigator — приложение запущено и данные открыты: отмечаем
    // сразу. Иначе — после входа, из redirect роутера.
    _markRead(notificationUuid, appReady: ctx != null);
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
      // Переход сделан — метки холодного старта, которые фоновый изолят
      // сохранил на этот же тап, больше не нужны.
      unawaited(_clearStoredTap());
    } catch (e) {
      debugPrint('[PushRouter] navigate failed: $e');
      _pendingOpen = true;
      _pendingRepairUuid = repairUuid;
    }
  }
}
