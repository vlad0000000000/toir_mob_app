import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';
import 'package:qr_machine_scanner/src/data/data_provider.dart';
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/src/widgets/button_with_select_dialog.dart';
import 'package:qr_machine_scanner/src/widgets/select_image_button.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';
import 'package:qr_machine_scanner/strings.dart';
import '../style/palette.dart';
import '../style/text_styles.dart';

class QRResultScreen extends StatefulWidget {
  final Machine machine;

  const QRResultScreen(this.machine, {super.key});

  @override
  State<QRResultScreen> createState() => _QRResultScreenState();
}

class _QRResultScreenState extends State<QRResultScreen> {
  final descController = TextEditingController();
  final imageData1Controller = SelectImageButtonController();
  final imageData2Controller = SelectImageButtonController();
  final imageData3Controller = SelectImageButtonController();
  final priorityController = TextEditingController();
  final problemController = TextEditingController();
  String problem = '';

  Widget checkControls() {
    List<Widget> addButtons = [
      SelectImageButton(
        controller: imageData1Controller,
      ),
      SelectImageButton(
        controller: imageData2Controller,
      ),
      SelectImageButton(
        controller: imageData3Controller,
      ),
    ];

    return Column(spacing: 8, children: [
      TextFormField(
        // obscureText:false,
        maxLines: 8,
        // expands:true,
        controller: descController,
        // obscureText: true,
        // style: TextStyle(backgroundColor: Colors.white,decorationColor: Colors.white, color: Colors.white),
        decoration: InputDecoration(
            floatingLabelAlignment: FloatingLabelAlignment.start,
            border: const OutlineInputBorder(),
            fillColor: Colors.white,
            filled: true,
            alignLabelWithHint: true,
            hoverColor: Colors.white,
            labelText: Strings.checkDescription),
        validator: (value) {
          // if (value == null || value.isEmpty) {
          //   return Strings.passwordHelp;
          // }
          return null;
        },
      ),
      Row(
        spacing: 8,
        children: [
          Expanded(
              child: Column(
            spacing: 4,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: DropdownMenu(
                    controller: problemController,
                    expandedInsets: EdgeInsets.zero,
                    label: Text("Проблема"),
                    dropdownMenuEntries: [
                      "Не включается",
                      "Не выключается",
                      "Шумит",
                      "Искрит",
                      "Дымит"
                    ].map((x) {
                      return DropdownMenuEntry(value: x, label: x);
                    }).toList(),
                  )),
                ],
              )
            ],
          )),
          Expanded(
              child: Column(
            spacing: 4,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Expanded(
                  //     child: DropdownButton(
                  //   onChanged: (x) {},
                  //
                  //   items: [
                  //     "Низкий",
                  //     "Средний",
                  //     "Высокий",
                  //   ].map((x) {
                  //     return DropdownMenuItem(
                  //       value: x,
                  //       child: Text(x),
                  //     );
                  //   }).toList(),
                  // )),
                  Expanded(
                      child: DropdownMenu(
                    controller: priorityController,
                    label: Text("Приоритет"),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      ["Низкий", Colors.yellow],
                      ["Средний", Colors.orange],
                      ["Высокий", Colors.red],
                    ].map((x) {
                      return DropdownMenuEntry(
                          value: x[0],
                          label: x[0] as String,
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStatePropertyAll(x[1] as Color),
                          ),
                          labelWidget: Text(
                            x[0] as String,
                            style: TextStyle(color: Colors.black),
                          ));
                    }).toList(),
                  )),
                ],
              )
            ],
          )),
        ],
      ),
      SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: addButtons,
          )),
      SizedBox()
    ]);
  }

  Widget passport() {
    var passportType = 1;
    // image + text
    if (passportType == 1) {
//       return Container(
//         color: Colors.white,
//         child: ClipRRect(
//             borderRadius: BorderRadius.circular(16.0),
//             child: Column(
//               spacing: 8,
//               mainAxisAlignment: MainAxisAlignment.start,
//               children: [
//                 // const Image(image: AssetImage('assets/images/lathe.jpg')),
//                 Image.memory(base64Decode(widget.machine.imageData)),
//                 Row(
//                   children: [
//                     Expanded(child: MarkdownBody(data: """
// **Название**: ${widget.machine.name}
//
// **Номер**: ${widget.machine.id}
//
// ${widget.machine.description}
//     """))
//                   ],
//                 ),
//               ],
//             ),
//       ));
      return Column(
        spacing: 8,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // const Image(image: AssetImage('assets/images/lathe.jpg')),
          Image.memory(base64Decode(widget.machine.imageData)),
          Row(
            children: [
              Expanded(child: MarkdownBody(data: """
**Название**: ${widget.machine.name}

**Номер**: ${widget.machine.id}

${widget.machine.description}
    """))
            ],
          ),
        ],
      );
    }

    // pdf
    if (passportType == 2) {}
    return SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final textStyles = context.watch<TextStyles>();
    final dataProvider = context.watch<DataProvider>();


    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      // appBar: AppBar(
      //   title: Text(Strings.qrResultScreenTitle),
      // ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          spacing: 8,
          children: [
            Expanded(
                child: SingleChildScrollView(
              child: Column(
                spacing: 16,
                children: [
                  passport(),
                  checkControls(),
                  // Row(children: [
                  //   Expanded(
                  //       child: SquareButton(
                  //           onPressed: () {
                  //             Dialogs.areYouSure(context, onOk: () async {
                  //               await dataProvider.sendMachineCheck(Check(
                  //                   userId: GlobalState.authUser.id,
                  //                   machineId: widget.machine.id,
                  //                   status: 1,
                  //                   images: [
                  //                     imageData1Controller.value,
                  //                     imageData2Controller.value,
                  //                     imageData3Controller.value,
                  //                   ],
                  //                   description: descController.text,
                  //                   priority: priorityController.text,
                  //                   problem: problemController.text,
                  //                   ts: GlobalState.now));
                  //               GoRouter.of(context).go("/qr_scanner");
                  //             });
                  //           },
                  //           child: Text("Отправить")))
                  // ],)
                ],
              ),
            )),
            // passport(),
            Row(
              spacing: 8,
              children: [
                Expanded(
                    child: SquareButton(
                        onPressed: () {
                          Dialogs.areYouSure(context, onOk: () async {
                            await dataProvider.sendMachineCheck(Check(
                                userId: GlobalState.authUser!.id,
                                machineId: widget.machine.id,
                                status: 1,
                                images: [
                                  imageData1Controller.value,
                                  imageData2Controller.value,
                                  imageData3Controller.value,
                                ],
                                description: descController.text,
                                priority: priorityController.text,
                                problem: problemController.text,
                                ts: GlobalState.now));
                            GoRouter.of(context).go("/qr_scanner");
                          });
                        },
                        child: Text("Отправить"))),
                // Expanded(
                //     child: SquareButton(
                //         color: Colors.red,
                //         onPressed: () async {
                //           Dialogs.areYouSure(context, onOk: () async {
                //             await dataProvider.sendMachineCheck(Check(
                //                 userId: GlobalState.authUser.id,
                //                 machineId: widget.machine.id,
                //                 status: 2,
                //                 images: [
                //                   imageData1Controller.value,
                //                   imageData2Controller.value,
                //                   imageData3Controller.value,
                //                 ],
                //                 description: descController.text,
                //                 priority: priorityController.value,
                //                 problem: problemController.value,
                //                 ts: GlobalState.now));
                //             GoRouter.of(context).go("/qr_scanner");
                //           });
                //         },
                //         child: Icon(
                //           Icons.thumb_down,
                //           color: Colors.white,
                //           size: 32,
                //         ))),
              ],
            ),
            // checkControls()
            SizedBox()
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Preload ad for the win screen.
    // final adsRemoved =
    //     context.read<InAppPurchaseController?>()?.adRemoval.active ?? false;
    // if (!adsRemoved) {
    //   final adsController = context.read<AdsController?>();
    //   adsController?.preloadAd();
    // }
  }
}
