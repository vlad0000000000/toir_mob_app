import 'dart:convert';

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';
import 'package:qr_machine_scanner/strings.dart';
import 'package:themed/themed.dart';

class ButtonWithSelectDialogController {
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

class ButtonWithSelectDialog extends StatefulWidget {
  late final ButtonWithSelectDialogController controller;

  final String dialogTitle;
  final String buttonText;
  final List<String> items;

  ButtonWithSelectDialog(
      {super.key,
      controller = null,
      required this.dialogTitle,
      required this.buttonText,
      required this.items}) {
    if (controller == null) {
      this.controller = ButtonWithSelectDialogController();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<ButtonWithSelectDialog> createState() => _ButtonWithSelectDialog();
}

class _ButtonWithSelectDialog extends State<ButtonWithSelectDialog> {
  void _showAwesomeDialog(BuildContext context) {

    AwesomeDialog(
            context: context,
            dialogType: DialogType.noHeader,
            headerAnimationLoop: false,
            body: Container(
              height: 200,
              child: Column(
                children: [
                  Text(
                    widget.dialogTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Expanded(
                      child: ListView(
                    children: widget.items.map((item) {
                      return ListTile(
                        title: Text(item),
                        onTap: () {
                          Navigator.pop(context);
                          _onItemSelected(context, item);
                        },
                      );
                    }).toList(),
                  ))
                ],
              ),
            ),
            btnOk: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(Strings.back)))
        .show();
  }

  void _onItemSelected(BuildContext context, String selectedItem) {
    widget.controller.value = selectedItem;
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Вы выбрали: $selectedItem')),
    // );
  }

  @override
  void dispose() {
    widget.controller.valueNotifier.removeListener(_onValueChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.valueNotifier.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: SquareButton(
            onPressed: () {
              _showAwesomeDialog(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(widget.controller.value.length == 0
                  ? widget.buttonText
                  : widget.controller.value),
            ))
    );
  }
}
