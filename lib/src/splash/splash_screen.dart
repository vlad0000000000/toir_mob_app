import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool showConnectionNotify = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startConnectionCheck();
  }

  void _timerCallback(timer) async {
    final isSynced = GlobalState.dataProvider.users.length > 0 &&
        GlobalState.dataProvider.machines.length > 0;
    if (isSynced) {
      timer.cancel();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          GoRouter.of(context).clearStackAndNavigate('/login');
        });
      }
    } else {
      // await GlobalState.dataProvider.checkConnectivityAndSync();
      if (await GlobalState.hasConnectionToServer) {
        await GlobalState.dataProvider.syncUsersAndMachines();
        // await syncChecks();
        // await syncTasks();
      }
      setState(() {
        showConnectionNotify = true;
      });
    }
  }

  void _startConnectionCheck() {
    _timer = Timer.periodic(const Duration(seconds: 5), _timerCallback);
    _timerCallback(_timer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 8,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const Center(
                  child: CircularProgressIndicator(
                color: Colors.black,
                strokeWidth: 8,
                constraints: BoxConstraints(minHeight: 128, minWidth: 128),
              )),
              Center(
                  child: Container(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: const Image(
                        image: AssetImage('assets/images/icon.png'))),
                width: 64,
              ))
            ],
          ),
          showConnectionNotify
              ? Text('Убедитесь, что телефон подключен к интернету')
              : SizedBox()
        ],
      ),
    ));
  }
}
