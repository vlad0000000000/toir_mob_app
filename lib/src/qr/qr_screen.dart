import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';
import 'package:qr_machine_scanner/src/data/data_provider.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
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
      backgroundColor: Colors.black,
      appBar: MyAppBar.build(context) as AppBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final scanWindow = Rect.fromCenter(
              center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
              width: 200,
              height: 200,
            );
            return Stack(
              children: [
                Center(
                  child: MobileScanner(
                    onDetect: (barcodes) async {
                      // if (!allowScan) {
                      //   return;
                      // }
                      if (barcodes.barcodes.length > 0) {
                        for (var barcode in barcodes.barcodes) {
                          // debugPrint("barcode = " + barcode.displayValue.toString());
                          for (var machine in dataProvider.machines) {
                            // debugPrint(machine.getQRValue());
                            if (machine.getQRValue() ==
                                barcode.displayValue.toString()) {
                              GlobalState.needTaskSync = true;
                              GoRouter.of(context)
                                  .clearStackAndNavigate('/qr_result', extra: machine);
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
          },),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ToggleFlashlightButton(controller: controller),
                  SwitchCameraButton(controller: controller),
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
    return BarcodeScannerWithController();
  }
}
