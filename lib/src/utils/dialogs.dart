import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:my_app/global_state.dart';
import '../../strings.dart';

class Dialogs {
  static ButtonStyle style = ButtonStyle(
      padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 16, horizontal: 16)));

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

  static Future<dynamic> notifyMD(context, title, desc, md) async {
    return AwesomeDialog(
      reverseBtnOrder: true,
      context: context,
      animType: AnimType.scale,
      dialogType: DialogType.noHeader,
      headerAnimationLoop: false,
      title: title,
      desc: desc,
      body: Padding(padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8), child: MarkdownBody(data: md),),
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
