import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../src/utils/go_router_ext.dart';

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
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GoRouter.of(context).clearStackAndNavigate('/login');
      });
    }
    // _startConnectionCheck();
  }

  // void _timerCallback(timer) async {
  //   final isSynced = GlobalState.dataProvider.users.length > 0 &&
  //       GlobalState.dataProvider.inventoryRecords.length > 0;
  //   if (isSynced) {
  //     timer.cancel();
  //     if (mounted) {
  //       WidgetsBinding.instance.addPostFrameCallback((_) {
  //         GoRouter.of(context).clearStackAndNavigate('/login');
  //       });
  //     }
  //   } else {
  //     // await GlobalState.dataProvider.checkConnectivityAndSync();
  //     if (await GlobalState.hasConnectionToServer) {
  //       await GlobalState.dataProvider.syncUsersAndMachines();
  //       // await syncChecks();
  //       // await syncTasks();
  //     }
  //     setState(() {
  //       showConnectionNotify = true;
  //     });
  //   }
  // }
  //
  // void _startConnectionCheck() {
  //   _timer = Timer.periodic(const Duration(seconds: 5), _timerCallback);
  //   _timerCallback(_timer);
  // }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 128,
                  height: 128,
                  child: CircularProgressIndicator(
                    color: cs.primary,
                    strokeWidth: 4,
                    backgroundColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16.0),
                  child: const Image(
                    image: AssetImage('assets/images/icon.png'),
                    width: 64,
                  ),
                ),
              ],
            ),
            if (showConnectionNotify) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Убедитесь, что телефон подключен к интернету',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
