import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';
import 'package:qr_machine_scanner/strings.dart';

class MyAppBar {
  static Widget build(BuildContext context) {
    ButtonStyle style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent)
    );
    Widget logoutBlackText = TextButton(
      style: style,
        onPressed: () async {
          Dialogs.areYouSure(context, onOk: () async {
            await GlobalState.loginBox.clear();
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
            await GlobalState.loginBox.clear();
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
