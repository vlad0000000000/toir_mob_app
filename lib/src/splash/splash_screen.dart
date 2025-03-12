import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/global_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // Загрузка данных из API
    await GlobalState.dataProvider.checkConnectivityAndSync();

    // После загрузки данных перенаправляем пользователя
    if (mounted) {
      GoRouter.of(context)
          .go('/login'); // Или на другой экран, в зависимости от логики
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Stack(
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
              child: const Image(image: AssetImage('assets/images/icon.png'))),
          width: 64,
        ))
      ],
    ));
  }
}
