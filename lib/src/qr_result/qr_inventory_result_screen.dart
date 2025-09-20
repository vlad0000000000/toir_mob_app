import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';
import 'package:qr_machine_scanner/src/data/data_provider.dart';
import 'package:qr_machine_scanner/src/model/inventory_scan.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';
import 'package:qr_machine_scanner/src/widgets/select_image_button.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';
import 'package:qr_machine_scanner/strings.dart';

class ResultControls extends StatefulWidget {
  final TextEditingController descController;
  final SelectImageButtonController imageData1Controller;
  final SelectImageButtonController imageData2Controller;
  final SelectImageButtonController imageData3Controller;
  final TextEditingController priorityController;
  final TextEditingController problemController;

  const ResultControls(
      {super.key,
        required this.descController,
        required this.imageData1Controller,
        required this.imageData2Controller,
        required this.imageData3Controller,
        required this.priorityController,
        required this.problemController});

  @override
  State<ResultControls> createState() => _ResultControlsState();
}

class _ResultControlsState extends State<ResultControls> {
  @override
  Widget build(BuildContext context) {
    List<Widget> addButtons = [
      SelectImageButton(
        controller: widget.imageData1Controller,
      ),
      SelectImageButton(
        controller: widget.imageData2Controller,
      ),
      SelectImageButton(
        controller: widget.imageData3Controller,
      ),
    ];

    Widget problemSelect = Row(
      children: [
        Expanded(
            child: DropdownMenu(
              requestFocusOnTap: true,
              onSelected: (value) {
                setState(() {});
              },
              controller: widget.problemController,
              expandedInsets: EdgeInsets.zero,
              label: Text("Проблема"),
              initialSelection: "Проблем нет",
              dropdownMenuEntries: [
                "Проблем нет",
                "Не включается",
                "Не выключается",
                "Шумит",
                "Искрит",
                "Дымит",
                "Другое"
              ].map((x) {
                return DropdownMenuEntry(value: x, label: x);
              }).toList(),
            )),
      ],
    );

    Widget prioritySelect = Row(
      children: [
        Expanded(
            child: DropdownMenu(
              // menuStyle: MenuStyle(
              //   backgroundColor: WidgetStatePropertyAll(Colors.red),
              // ),
              requestFocusOnTap: true,
              controller: widget.priorityController,
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
                      backgroundColor: WidgetStatePropertyAll(x[1] as Color),
                    ),
                    labelWidget: Text(
                      x[0] as String,
                      style: TextStyle(color: Colors.black),
                    ));
              }).toList(),
            )),
      ],
    );

    Widget rest = Column(spacing: 8, children: [
      TextFormField(
        // obscureText:false,
        maxLines: 8,
        // expands:true,
        controller: widget.descController,
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
      SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: addButtons,
          )),
      SizedBox()
    ]);

    if (widget.problemController.text.length == 0 ||
        widget.problemController.text == 'Проблем нет') {
      return Column(
        spacing: 8,
        children: [problemSelect],
      );
    }

    return Column(
      spacing: 8,
      children: [problemSelect, prioritySelect, rest],
    );
  }
}

class QRResultScreen extends StatefulWidget {
  final InventoryRecord machine;

  const QRResultScreen(this.machine, {super.key});

  @override
  State<QRResultScreen> createState() => _QRResultScreenState();
}

class _QRResultScreenState extends State<QRResultScreen> {
  final quantityController = TextEditingController();
  final descController = TextEditingController();
  final imageData1Controller = SelectImageButtonController();
  final imageData2Controller = SelectImageButtonController();
  final imageData3Controller = SelectImageButtonController();
  final priorityController = TextEditingController();
  final problemController = TextEditingController();

  Widget passport() {
    var passportType = 1;
    // image + text
    if (passportType == 1) {
      return Column(
        spacing: 8,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // const Image(image: AssetImage('assets/images/lathe.jpg')),
          // Image.memory(base64Decode(widget.machine.imageData)),
          Row(
            children: [
              Expanded(child: MarkdownBody(data: """
- **Наименование**: ${widget.machine.name}

- **Код**: ${widget.machine.serialNumber}
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
    final dataProvider = context.watch<DataProvider>();

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
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
                      TextFormField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'Колличество'),
                        // validator: (value) {
                        //   if (value == null || value.isEmpty) {
                        //     return Strings.loginHelp;
                        //   }
                        //   return null;
                        // },
                      ),
                      // TextField(
                      //   decoration: InputDecoration(
                      //     border: OutlineInputBorder(),
                      //     hintText: 'Колличество',
                      //   ),
                      //   controller: quantityController,
                      // )
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
                          // Dialogs.areYouSure(context, onOk: () async {
                          //   await dataProvider.addScan(InventoryScan(
                          //       publicId: widget.machine.uuid,
                          //       quantity: int.parse(quantityController.text),
                          //       ts: GlobalState.now));
                          //   await dataProvider.syncScans();
                          //   GoRouter.of(context)
                          //       .clearStackAndNavigate("/qr_scanner");
                          // });
                        },
                        child: Text("Отправить"))),
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
