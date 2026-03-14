import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../global_state.dart';
import '../../src/knowledge_base/knowledge_base_utils.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../strings.dart';

/// Серая подчёркнутая ссылка "Помощь" — как на экране логина
Widget _buildHelpLink(BuildContext context) {
  return GestureDetector(
    onTap: () => context.push('/knowledge_base'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/ix_user-manual.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              Colors.grey.shade700,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Помощь',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 16,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    ),
  );
}

class MyAppBar {
  static Widget build(BuildContext context) {
    ButtonStyle style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent)
    );
    Widget logoutBlackText = TextButton(
      style: style,
        onPressed: () async {
          Dialogs.areYouSure(context, onOk: () async {
            GlobalState.authUser = null;
            GlobalState.updateDebug();
            GoRouter.of(context).clearStackAndNavigate('/login');
          });
        },
        child: Text(Strings.logout,
            style: TextStyle(color: Colors.black, fontSize: 14)));
    Widget logoutWhiteText = TextButton(
        style: style,
        onPressed: () async {
          Dialogs.areYouSure(context, onOk: () async {
            GlobalState.authUser = null;
            GlobalState.updateDebug();
            GoRouter.of(context).clearStackAndNavigate('/login');
          });
        },
        child: Text(Strings.logout,
            style: TextStyle(color: Colors.white, fontSize: 14)));

    if (GoRouter.of(context).location == '/qr_result') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/qr_scanner');
          },
        ),
        actions: [
          // logoutBlackText
        ],
      );
    }
    if (GoRouter.of(context).location == '/qr_result_problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/problems');
          },
        ),
        actions: [
          // logoutBlackText
        ],
      );
    }
    if (GoRouter.of(context).location == '/tasks') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/actions');
          },
        ),
        title: Text('Оборудование'),
        actions: [
          // logoutBlackText
        ],
      );
    }
    if (GoRouter.of(context).location == '/problems') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/actions');
          },
        ),
        title: Text('Оборудование'),
        actions: [
          // logoutBlackText
        ],
      );
    }
    if (GoRouter.of(context).location == '/knowledge_base') {
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
        title: Text('Помощь'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Открыть в браузере',
            onPressed: openKnowledgeBaseInBrowser,
          ),
        ],
      );
    }
    if (GoRouter.of(context).location.startsWith('/details')) {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/tasks');
          },
        ),
        title: Text('Задачи'),
        actions: [
          // logoutBlackText
        ],
      );
    }
    if (GoRouter.of(context).location.startsWith('/qr_scanner')) {
      return AppBar(
        leading: BackButton(
          color: Colors.white,
          onPressed: () {
            GoRouter.of(context).clearStackAndNavigate('/actions');
          },
        ),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        actions: [
          // logoutWhiteText
        ],
      );
    }
    if (GoRouter.of(context).location.startsWith('/actions')) {
      return AppBar(
        automaticallyImplyLeading: false,
        leading: _buildHelpLink(context),
        leadingWidth: 120,
        actions: [logoutBlackText],
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black,
      actions: [
        logoutWhiteText
      ],
    );
  }
}
