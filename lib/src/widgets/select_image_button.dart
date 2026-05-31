import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../src/widgets/square_button.dart';
import '../../strings.dart';
import 'package:themed/themed.dart';
import 'controller_listener_mixin.dart';

class SelectImageButtonController {
  final ValueNotifier<String> _valueNotifier = ValueNotifier('');

  ValueNotifier<String> get valueNotifier => _valueNotifier;

  String get value => _valueNotifier.value;

  set value(String newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }
}

class SelectImageButton extends StatefulWidget {
  late final SelectImageButtonController controller;

  SelectImageButton({super.key, controller = null}) {
    if (controller == null) {
      this.controller = SelectImageButtonController();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectImageButton> createState() => _SelectImageButton();
}

class _SelectImageButton extends State<SelectImageButton>
    with ControllerListenerMixin {
  String imageData = '';

  @override
  Listenable get controllerListenable => widget.controller.valueNotifier;

  @override
  void onControllerChanged() {
    setState(() {
      imageData = widget.controller.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (imageData.length > 0) {
      var stack = Stack(
        alignment: Alignment.center,
        children: [
          Image.memory(base64Decode(imageData)),
          Center(
            child: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.onInverseSurface.withValues(alpha: 0.75),
              size: 64,
            ),
          )
        ],
      );
      return Expanded(
          child: SquareButton(
              onPressed: () {
                widget.controller.value = '';
              },
              child: stack));
    } else {
      return Expanded(
          child: SquareButton(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: [
                  Icon(
                    Icons.image,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    size: 32,
                  ),
                  Text(
                    Strings.addImage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  )
                ],
              ),
              onPressed: () async {
                final ImagePicker picker = ImagePicker();

                final XFile? image = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 100
                );

                if (image != null) {
                  // GallerySaver.saveImage(image.path);
                  String imageData1 = base64Encode(await image.readAsBytes());
                  widget.controller.value = imageData1;
                  // setState(() {
                  //   imageData = imageData1;
                  // });
                }
              }));
    }
  }
}
