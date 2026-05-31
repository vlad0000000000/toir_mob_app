import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../global_state.dart';
import '../../src/knowledge_base/knowledge_base_utils.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../src/widgets/help_link.dart';
import '../../strings.dart';
import '../design/app_constants.dart';

class MyAppBar {
  static Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final transparentStyle = const ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    );

    Widget _logout({required Color textColor}) => TextButton(
          style: transparentStyle,
          onPressed: () async {
            Dialogs.areYouSure(context, onOk: () async {
              GlobalState.authUser = null;
              GlobalState.updateDebug();
              NotificationsService.instance.onLogout();
              await PushNotificationsController.instance.stop();
              GoRouter.of(context).clearStackAndNavigate('/login');
            });
          },
          child: Text(
            Strings.logout,
            style: labelStyle?.copyWith(color: textColor),
          ),
        );

    final logoutOnSurface = _logout(textColor: cs.onSurface);
    final logoutOnInverseSurface = _logout(textColor: cs.onInverseSurface);

    final location = GoRouter.of(context).location;

    if (location == '/qr_result' || location == '/qr_result_demo') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).clearStackAndNavigate('/qr_scanner'),
        ),
      );
    }
    if (location == '/qr_result_problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).clearStackAndNavigate('/problems'),
        ),
      );
    }
    if (location == '/tasks' || location == '/problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).clearStackAndNavigate('/actions'),
        ),
        title: const Text('Оборудование'),
      );
    }
    if (location == '/knowledge_base') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              GoRouter.of(context).go('/login');
            }
          },
        ),
        title: const Text('Помощь'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Открыть в браузере',
            onPressed: openKnowledgeBaseInBrowser,
          ),
        ],
      );
    }
    if (location.startsWith('/details')) {
      return AppBar(
        leading: BackButton(
          onPressed: () => GoRouter.of(context).clearStackAndNavigate('/tasks'),
        ),
        title: const Text('Задачи'),
      );
    }
    if (location.startsWith('/qr_scanner')) {
      // QR-сканер: тёмный AppBar нужен для камеры.
      return AppBar(
        leading: BackButton(
          color: cs.onInverseSurface,
          onPressed: () =>
              GoRouter.of(context).clearStackAndNavigate('/actions'),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: cs.inverseSurface,
      );
    }
    if (location.startsWith('/actions')) {
      final username = GlobalState.authUser?.username ?? '';
      return AppBar(
        automaticallyImplyLeading: false,
        leading: const HelpLink(
          padding: EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSM,
            vertical: AppConstants.spacingSM + 4,
          ),
        ),
        leadingWidth: 120,
        title: username.isEmpty
            ? null
            : Text(
                username,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
              ),
        centerTitle: true,
        actions: [logoutOnSurface],
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: cs.inverseSurface,
      actions: [logoutOnInverseSurface],
    );
  }
}
