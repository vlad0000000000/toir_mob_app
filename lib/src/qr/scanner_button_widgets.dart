import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AnalyzeImageFromGalleryButton extends StatelessWidget {
  const AnalyzeImageFromGalleryButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Colors.white,
      icon: const Icon(Icons.image),
      iconSize: 32.0,
      onPressed: () async {
        final ImagePicker picker = ImagePicker();

        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
        );

        if (image == null) {
          return;
        }

        final BarcodeCapture? barcodes = await controller.analyzeImage(
          image.path,
        );

        if (!context.mounted) {
          return;
        }

        final SnackBar snackbar = barcodes != null
            ? const SnackBar(
                content: Text('Barcode found!'),
                backgroundColor: Colors.green,
              )
            : const SnackBar(
                content: Text('No barcode found!'),
                backgroundColor: Colors.red,
              );

        ScaffoldMessenger.of(context).showSnackBar(snackbar);
      },
    );
  }
}

class StartStopMobileScannerButton extends StatelessWidget {
  const StartStopMobileScannerButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return IconButton(
            color: Colors.white,
            icon: const Icon(Icons.play_arrow),
            iconSize: 32.0,
            onPressed: () async {
              await controller.start();
            },
          );
        }

        return IconButton(
          color: Colors.white,
          icon: const Icon(Icons.stop),
          iconSize: 32.0,
          onPressed: () async {
            await controller.stop();
          },
        );
      },
    );
  }
}

class SwitchCameraButton extends StatelessWidget {
  const SwitchCameraButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }

        final int? availableCameras = state.availableCameras;

        if (availableCameras != null && availableCameras < 2) {
          return const SizedBox.shrink();
        }

        final Widget icon;

        switch (state.cameraDirection) {
          case CameraFacing.front:
            icon = const Icon(Icons.camera_front);
          case CameraFacing.back:
            icon = const Icon(Icons.camera_rear);
          case CameraFacing.external:
            icon = const Icon(Icons.usb);
          case CameraFacing.unknown:
            icon = const Icon(Icons.device_unknown);
        }

        return IconButton(
          color: Colors.white,
          iconSize: 32.0,
          icon: icon,
          onPressed: () async {
            await controller.switchCamera();
          },
        );
      },
    );
  }
}

class ToggleFlashlightButton extends StatelessWidget {
  const ToggleFlashlightButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }

        switch (state.torchState) {
          case TorchState.auto:
            return IconButton(
              color: Colors.white,
              iconSize: 32.0,
              icon: const Icon(Icons.flash_auto),
              onPressed: () async {
                await controller.toggleTorch();
              },
            );
          case TorchState.off:
            return IconButton(
              color: Colors.white,
              iconSize: 32.0,
              icon: const Icon(Icons.flash_off),
              onPressed: () async {
                await controller.toggleTorch();
              },
            );
          case TorchState.on:
            return IconButton(
              color: Colors.white,
              iconSize: 32.0,
              icon: const Icon(Icons.flash_on),
              onPressed: () async {
                await controller.toggleTorch();
              },
            );
          case TorchState.unavailable:
            return const SizedBox.square(
              dimension: 48.0,
              child: Icon(
                Icons.no_flash,
                size: 32.0,
                color: Colors.grey,
              ),
            );
        }
      },
    );
  }
}

class PauseMobileScannerButton extends StatelessWidget {
  const PauseMobileScannerButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }

        return IconButton(
          color: Colors.white,
          iconSize: 32.0,
          icon: const Icon(Icons.pause),
          onPressed: () async {
            await controller.pause();
          },
        );
      },
    );
  }
}

class ZoomButton extends StatefulWidget {
  const ZoomButton({required this.controller, super.key});

  final MobileScannerController controller;

  @override
  State<ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<ZoomButton> {
  final List<double> _zoomLevels = [1.0, 1.5, 2.0, 2.5, 3.0];
  int _currentZoomIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, child) {
        if (!state.isInitialized || !state.isRunning) {
          return const SizedBox.shrink();
        }

        return IconButton(
          color: Colors.white,
          iconSize: 32.0,
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_in),
              // Text(
              //   '${_zoomLevels[_currentZoomIndex].toStringAsFixed(1)}x',
              //   style: const TextStyle(
              //     fontSize: 10,
              //     color: Colors.white,
              //   ),
              // ),
            ],
          ),
          onPressed: () async {
            if (kIsWeb) {
              return;
            }

            setState(() {
              _currentZoomIndex = (_currentZoomIndex + 1) % _zoomLevels.length;
            });
            await widget.controller
                .setZoomScale((_zoomLevels[_currentZoomIndex] - 1) / 2);
            // Показываем уведомление о текущем уровне зума
            // if (mounted) {
            //   ScaffoldMessenger.of(context).showSnackBar(
            //     SnackBar(
            //       content: Text('Зум: ${_zoomLevels[_currentZoomIndex].toStringAsFixed(1)}x'),
            //       duration: const Duration(seconds: 1),
            //     ),
            //   );
            // }
          },
        );
      },
    );
  }
}
