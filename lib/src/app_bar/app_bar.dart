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
              GoRouter.of(context).backOr('/qr_scanner'),
        ),
      );
    }
    if (location == '/qr_result_problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).backOr('/problems'),
        ),
      );
    }
    if (location == '/tasks' || location == '/problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).backOr('/actions'),
        ),
        title: const Text('Оборудование'),
      );
    }
    if (location == '/ppr') {
      return AppBar(
        leading: BackButton(
          onPressed: () => GoRouter.of(context).backOr('/actions'),
        ),
        title: const Text('ППР'),
      );
    }
    // Точное совпадение проверяем до префикса: '/repairs/<uuid>' — карточка,
    // а голый '/repairs' — список.
    if (location == '/repairs') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).backOr('/actions'),
        ),
        title: const Text('Ремонты'),
      );
    }
    // Ветки для '/repairs/<uuid>' здесь нет намеренно: карточка ремонта
    // строит свой AppBar — в заголовке номер ремонта, справа пилюля статуса,
    // а таких данных ветвление по строке маршрута не знает.
    if (location == '/spare_parts') {
      return AppBar(
        leading: BackButton(
          onPressed: () =>
              GoRouter.of(context).backOr('/actions'),
        ),
        title: const Text('ЗИП'),
      );
    }
    // '/spare_parts/<uuid>' — по той же причине, что и карточка ремонта:
    // карточка ЗИП строит свой AppBar (значок, название позиции и пилюля
    // наличия) и попадает сюда через push, так что штатная кнопка «назад»
    // работает сама.
    if (location == '/knowledge_base') {
      return AppBar(
        leading: BackButton(
          // База знаний открыта и до входа, поэтому запасной адрес — логин.
          onPressed: () => GoRouter.of(context).backOr('/login'),
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
      // На карточку оборудования приходят и из списка задач, и из ППР —
      // возвращаемся туда, откуда пришли (см. `?from=ppr`).
      final backTo = location.contains('from=ppr') ? '/ppr' : '/tasks';
      return AppBar(
        leading: BackButton(
          // backOr, а не сброс стека: карточка открыта через push, и «назад»
          // должен вернуть на тот экран, откуда пришли, вместе с прокруткой.
          // backTo — запасной адрес на случай пустого стека (приход по пушу).
          onPressed: () => GoRouter.of(context).backOr(backTo),
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
              GoRouter.of(context).backOr('/actions'),
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
