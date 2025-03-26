import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/utils/dependent.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/strings.dart';

class MyAppBar {
  static Widget build(BuildContext context) {
    if (GoRouter.of(context).location == '/qr_scanner/qr_result') {
      return AppBar(
        leading: BackButton(
          onPressed: () {
            GoRouter.of(context).go('/qr_scanner');
          },
        ),
        // title: Text(Strings.finishCheck),
        // title: Dependent(
        //   value: GlobalState.debug,
        //   builder: (context, value, child) {
        //     return Text(
        //       value,
        //       style: TextStyle(color: Colors.white, fontSize: 10),
        //     );
        //   },
        // ),
        actions: [
          TextButton(
              onPressed: () async {
                Dialogs.areYouSure(context, onOk: () async {
                  await GlobalState.loginBox.clear();
                  GlobalState.updateDebug();
                  GoRouter.of(context).go('/login');
                });
              },
              child: Text(Strings.logout,
                  style: TextStyle(color: Colors.black, fontSize: 14)))
        ],
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black,
      // title: Dependent(
      //   value: GlobalState.debug,
      //   builder: (context, value, child) {
      //     return Text(
      //       value,
      //       style: TextStyle(color: Colors.white, fontSize: 10),
      //     );
      //   },
      // ),
      actions: [
        TextButton(
            onPressed: () async {
              Dialogs.areYouSure(context, onOk: () async {
                await GlobalState.loginBox.clear();
                GlobalState.updateDebug();
                GoRouter.of(context).go('/login');
              });
            },
            child: Text(Strings.logout,
                style: TextStyle(color: Colors.white, fontSize: 14)))
      ],
    );
  }
}
