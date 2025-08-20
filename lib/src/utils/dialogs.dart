import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:qr_machine_scanner/strings.dart';

class Dialogs {

  static ButtonStyle style = ButtonStyle(
      padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 16, horizontal: 16))
  );

  static Future<dynamic> notify(context, title, desc) async {
    return AwesomeDialog(
      reverseBtnOrder: true,
      context: context,
      animType: AnimType.scale,
      dialogType: DialogType.noHeader,
      headerAnimationLoop: false,
      title: title,
      desc: desc,
      btnOk: ElevatedButton(
          style: style,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(Strings.understand)),
    ).show();
  }

  static void areYouSure(context, {onOk = null}) async {
    AwesomeDialog(
      reverseBtnOrder: true,
      context: context,
      animType: AnimType.scale,
      dialogType: DialogType.noHeader,
      headerAnimationLoop: false,
      title: Strings.areYouSure,
      // desc: desc,
      btnOk: ElevatedButton(
          style: style,
          onPressed: () {
            Navigator.pop(context);
            if (onOk != null) {
              onOk();
            }
          },
          child: Text(Strings.yes)),
      btnCancel: ElevatedButton(
          style: style,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(Strings.no)),
    ).show();
  }
}
