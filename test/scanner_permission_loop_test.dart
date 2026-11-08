import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/notifications/push/push_notifications_controller.dart';
import 'package:qr_scan_industry/src/qr/qr_screen.dart';

/// Отчёт тестирования ремонтов, п. 1.2: при запрещённых уведомлениях каждый
/// возврат в приложение снова запрашивал разрешение. Системное окно уводило
/// приложение в `inactive`, сканер гасил и поднимал камеру, превью мигало.
void main() {
  group('запрос разрешения на уведомления', () {
    bool ask(NotificationPermission current, {required bool byUser}) =>
        shouldRequestNotificationPermission(
          current: current,
          askPermission: byUser,
        );

    test('автоматический запуск без разрешения не спрашивает', () {
      expect(ask(NotificationPermission.denied, byUser: false), isFalse);
    });

    test('после окончательного запрета автоматический запуск не спрашивает',
        () {
      expect(
        ask(NotificationPermission.permanently_denied, byUser: false),
        isFalse,
      );
    });

    test('вход или настройки без разрешения — спрашиваем', () {
      expect(ask(NotificationPermission.denied, byUser: true), isTrue);
    });

    test('разрешение уже есть — не спрашиваем даже по действию пользователя',
        () {
      expect(ask(NotificationPermission.granted, byUser: true), isFalse);
      expect(ask(NotificationPermission.granted, byUser: false), isFalse);
    });
  });

  group('запуск камеры при возврате в приложение', () {
    test('сканер на экране — запускаем', () {
      expect(
        shouldStartCameraOnResume(hasCameraPermission: true, navigating: false),
        isTrue,
      );
    });

    test('поверх открыта карточка оборудования — не запускаем', () {
      expect(
        shouldStartCameraOnResume(hasCameraPermission: true, navigating: true),
        isFalse,
      );
    });

    test('нет разрешения на камеру — не запускаем', () {
      expect(
        shouldStartCameraOnResume(
          hasCameraPermission: false,
          navigating: false,
        ),
        isFalse,
      );
    });
  });

  /// «Отмена» в предупреждении о чужом оборудовании после того, как
  /// приложение сворачивали с открытым окном: камеру погасили, при возврате
  /// не подняли (поверх было окно), и без запуска после паузы она оставалась
  /// выключенной.
  group('запуск камеры после «Отмена» в окне о чужом оборудовании', () {
    bool start({
      bool permission = true,
      AppLifecycleState? lifecycle = AppLifecycleState.resumed,
    }) =>
        shouldStartCameraAfterDecline(
          hasCameraPermission: permission,
          lifecycle: lifecycle,
        );

    test('приложение на переднем плане — запускаем', () {
      expect(start(), isTrue);
    });

    test('свернули во время паузы — не запускаем, поднимет возврат', () {
      expect(start(lifecycle: AppLifecycleState.paused), isFalse);
      expect(start(lifecycle: AppLifecycleState.inactive), isFalse);
      expect(start(lifecycle: AppLifecycleState.hidden), isFalse);
    });

    test('состояние ещё не известно — считаем передним планом', () {
      expect(start(lifecycle: null), isTrue);
    });

    test('нет разрешения на камеру — не запускаем', () {
      expect(start(permission: false), isFalse);
    });
  });
}
