import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../global_state.dart';
import 'notifications_task_handler.dart';

class PushNotificationsController {
  PushNotificationsController._();

  static final PushNotificationsController instance =
      PushNotificationsController._();

  static const String _channelId = 'notifications_sse_service';
  static const String _channelName = 'Уведомления (фоновый канал)';

  /// Интервал watchdog'а — раз в полторы минуты проверяем, что сервис жив.
  static const Duration _watchdogInterval = Duration(seconds: 90);

  bool _initialized = false;
  Timer? _watchdog;

  /// Конфигурируем foreground task на старте приложения.
  /// Безопасно вызывать многократно.
  void init() {
    if (_initialized) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription:
            'Поддерживает соединение для получения уведомлений',
        // MIN — нотификация уходит в «Тихие» (без иконки в статус-баре,
        // без peek, без звука). Полностью скрыть нельзя: foreground service
        // обязан показывать notification (Android API 26+).
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // Поднимаем сервис обратно после ребута устройства и после
        // обновления приложения — иначе пуши приходят только пока юзер
        // не выключил телефон.
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Стартует foreground-сервис с актуальным JWT и base URL.
  /// Без авторизации не запускается.
  /// **НЕ дёргает battery optimization** — это делается вручную через
  /// [requestBatteryOptimizationException] из экрана настроек.
  Future<bool> start() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (!GlobalState.isAuthorized) return false;
    final token = GlobalState.authUser?.JWTToken;
    if (token == null || token.isEmpty) {
      debugPrint('[Push] start aborted: no JWT');
      return false;
    }

    final baseUrl = dotenv.env['API_ENDPOINT'];
    if (baseUrl == null || baseUrl.isEmpty) {
      debugPrint('[Push] start aborted: no API_ENDPOINT');
      return false;
    }

    init();

    // Только notification permission — необходим для foreground-сервиса
    // на Android 13+. Без него сервис стартует, но persistent-уведомление
    // не показывается и систем может прибить сервис.
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    debugPrint('[Push] notification permission before request: $notifPerm');
    if (notifPerm != NotificationPermission.granted) {
      final newPerm =
          await FlutterForegroundTask.requestNotificationPermission();
      debugPrint('[Push] notification permission after request: $newPerm');
      if (newPerm != NotificationPermission.granted) {
        debugPrint('[Push] start aborted: user denied notifications');
        return false;
      }
    }

    // Прокидываем токен и base URL в изолят сервиса.
    await FlutterForegroundTask.saveData(key: 'sse_base_url', value: baseUrl);
    await FlutterForegroundTask.saveData(key: 'sse_jwt', value: token);

    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[Push] service already running — restart with new token');
      final result = await FlutterForegroundTask.restartService();
      return result is ServiceRequestSuccess;
    }

    debugPrint('[Push] starting foreground service…');
    final result = await FlutterForegroundTask.startService(
      serviceId: 736251,
      notificationTitle: 'Уведомления активны',
      notificationText: 'Слежу за новыми событиями',
      notificationIcon: null,
      callback: notificationsForegroundCallback,
    );
    final ok = result is ServiceRequestSuccess;
    debugPrint('[Push] startService result: $result (ok=$ok)');

    // Battery optimization автоматически НЕ просим — это раздражает и не
    // обязательно. Пользователь может явно разрешить из «Настройки уведомлений
    // → Push в фоне → Разрешить» если столкнётся с потерей сервиса на
    // агрессивных OEM (Xiaomi/Huawei/Samsung).
    if (ok) {
      _ensureWatchdog();
    }

    return ok;
  }

  /// Проверяет, что foreground-сервис жив, и поднимает его при необходимости.
  /// Безопасно вызывать на каждом resume — если сервис работает,
  /// никаких действий не делается.
  Future<void> ensureRunning() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!GlobalState.isAuthorized) {
      _cancelWatchdog();
      return;
    }
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        debugPrint('[Push] ensureRunning: service is down, restarting');
        await start();
      } else {
        _ensureWatchdog();
      }
    } catch (e) {
      debugPrint('[Push] ensureRunning error: $e');
    }
  }

  void _ensureWatchdog() {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_watchdog != null) return;
    _watchdog = Timer.periodic(_watchdogInterval, (_) => _watchdogTick());
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _watchdogTick() async {
    if (!GlobalState.isAuthorized) {
      _cancelWatchdog();
      return;
    }
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        debugPrint('[Push] watchdog: service not running — restart');
        await start();
      }
    } catch (e) {
      debugPrint('[Push] watchdog tick error: $e');
    }
  }

  /// Останавливаем сервис (logout / disable realtime).
  Future<void> stop() async {
    _cancelWatchdog();
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      await FlutterForegroundTask.removeData(key: 'sse_base_url');
      await FlutterForegroundTask.removeData(key: 'sse_jwt');
    } catch (e) {
      debugPrint('[Push] stop failed: $e');
    }
  }

  /// Запрос на выключение battery optimization — вызывается только
  /// явным действием пользователя из настроек уведомлений.
  ///
  /// На многих OEM (Xiaomi/Huawei/Oppo/Samsung) показывается system-chooser
  /// «Завершить действие через Battery Saver» — это норма, пользователь
  /// должен выбрать системный диалог и разрешить.
  Future<bool> requestBatteryOptimizationException() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return true;
      }
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (e) {
      debugPrint('[Push] requestIgnoreBatteryOptimization failed: $e');
      return false;
    }
  }

  /// Диагностический статус — для UI «почему не работает».
  Future<PushDiagnostics> diagnose() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const PushDiagnostics(
        platformSupported: false,
        notificationPermission: 'n/a',
        batteryOptIgnored: false,
        serviceRunning: false,
      );
    }
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    final running = await FlutterForegroundTask.isRunningService;
    return PushDiagnostics(
      platformSupported: true,
      notificationPermission: perm.toString(),
      batteryOptIgnored: battery,
      serviceRunning: running,
    );
  }
}

class PushDiagnostics {
  final bool platformSupported;
  final String notificationPermission;
  final bool batteryOptIgnored;
  final bool serviceRunning;

  const PushDiagnostics({
    required this.platformSupported,
    required this.notificationPermission,
    required this.batteryOptIgnored,
    required this.serviceRunning,
  });

  @override
  String toString() => 'PushDiagnostics(supported=$platformSupported, '
      'perm=$notificationPermission, batteryIgnored=$batteryOptIgnored, '
      'running=$serviceRunning)';
}
