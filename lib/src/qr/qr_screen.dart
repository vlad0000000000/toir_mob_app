import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../settings.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/data/data_provider.dart';
import '../../src/onboarding/scanner_demo_modal.dart';
import '../../src/utils/go_router_ext.dart';

import '../update_manager.dart';
import 'scanner_button_widgets.dart';
import 'scanner_error_widget.dart';

class BarcodeScannerWithController extends StatefulWidget {
  const BarcodeScannerWithController({super.key});

  @override
  State<BarcodeScannerWithController> createState() =>
      _BarcodeScannerWithControllerState();
}

class _BarcodeScannerWithControllerState
    extends State<BarcodeScannerWithController> with WidgetsBindingObserver {
  final MobileScannerController controller = MobileScannerController(
    autoStart: false,
    autoZoom: true,
  );
  bool _demoModalShown = false;

  /// Карточка оборудования уже открывается — новые распознавания пропускаем.
  ///
  /// `MobileScanner` зовёт `onDetect` на каждом кадре, где видит код, то есть
  /// десятки раз в секунду. Камера при этом продолжает работать и после
  /// перехода: экран сканера намеренно остаётся в стеке под карточкой, чтобы
  /// «назад» возвращал к камере. Без этого флага каждый кадр, пока QR в
  /// объективе, добавлял в стек ещё одну карточку того же оборудования — а
  /// при включённой настройке «сразу открывать задачи» каждая открывала свою
  /// шторку выбора задач.
  bool _navigating = false;

  bool get _isOnboardingScanner =>
      Settings.onboardingInProgress && Settings.onboardingStep == 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
    if (_isOnboardingScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDemoModal());
    }
  }

  /// Останавливает камеру, не роняя экран.
  ///
  /// `stop()` бросает, если камера уже не работает, — а её мог погасить
  /// системный обработчик жизненного цикла ровно перед нашим вызовом.
  Future<void> _stopCamera() async {
    try {
      await controller.stop();
    } catch (_) {
      // Уже остановлена — делать нечего.
    }
  }

  void _showDemoModal() {
    if (_demoModalShown) return;
    _demoModalShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => ScannerDemoModal(
        onStart: () {
          Navigator.of(context).pop();
          Settings.onboardingStep = 3;
          GoRouter.of(context).clearStackAndNavigate('/onboarding_video');
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        unawaited(controller.start());
      case AppLifecycleState.inactive:
        unawaited(controller.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = context.watch<DataProvider>();
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      appBar: MyAppBar.build(context) as AppBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scanWindow = Rect.fromCenter(
                center:
                    Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
                width: 200,
                height: 200,
              );
              return Stack(
                children: [
                  Center(
                    child: MobileScanner(
                      onDetect: (barcodes) async {
                        if (_isOnboardingScanner) return;
                        if (_navigating) return;
                        if (barcodes.barcodes.length > 0) {
                          for (var barcode in barcodes.barcodes) {
                            var barcodeUUID = "";
                            try {
                              barcodeUUID = jsonDecode(
                                  barcode.displayValue.toString())['uuid'];
                            } catch (e) {}
                            // print("barcode uuid = " + barcodeUUID);
                            for (var machine in dataProvider.inventoryRecords) {
                              // print(machine.getQRValue());
                              if (machine.uuid.toLowerCase() ==
                                  barcodeUUID.toLowerCase()) {
                                // push, а не сброс стека: сканер остаётся под
                                // карточкой, и «назад» возвращает к камере.
                                //
                                // Флаг снимаем после возврата с карточки, а
                                // не сразу: иначе тот же QR, всё ещё
                                // висящий в объективе, тут же открыл бы её
                                // второй раз.
                                _navigating = true;
                                // Роутер берём до `await`: после него
                                // обращаться к `context` уже нельзя.
                                final router = GoRouter.of(context);
                                // Гасим камеру на время карточки. Смена
                                // маршрута внутри приложения состояние
                                // жизненного цикла не меняет, поэтому
                                // штатный обработчик её не остановит — и
                                // камера работала бы всё время, пока
                                // обходчик заполняет осмотр: грелась и ела
                                // батарею.
                                await _stopCamera();
                                await router.push('/qr_result',
                                    extra: machine);
                                if (!mounted) return;
                                _navigating = false;
                                unawaited(controller.start());
                                return;
                              }
                            }
                          }
                        }
                      },
                      fit: BoxFit.contain,
                      controller: controller,
                      scanWindow: scanWindow,
                      errorBuilder: (context, error) {
                        return ScannerErrorWidget(error: error);
                      },
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      if (!value.isInitialized ||
                          !value.isRunning ||
                          value.error != null ||
                          scanWindow.isEmpty) {
                        return const SizedBox();
                      }

                      return ScanWindowOverlay(
                        controller: controller,
                        scanWindow: scanWindow,
                      );
                    },
                  ),
                ],
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ToggleFlashlightButton(controller: controller),
                  SwitchCameraButton(controller: controller),
                  ZoomButton(controller: controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    await controller.dispose();
  }
}

class QRScreen extends StatelessWidget {
  const QRScreen({super.key});

  @override
  Widget build(BuildContext context) {

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      UpdateManager.checkForUpdate(context);
    },);

    return BarcodeScannerWithController();
  }
}
