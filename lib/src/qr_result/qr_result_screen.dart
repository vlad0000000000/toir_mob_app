import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';
import 'package:qr_machine_scanner/src/data/data_provider.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/tasks/tasks.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';
import 'package:qr_machine_scanner/src/widgets/select_image_button.dart';
import 'package:qr_machine_scanner/src/widgets/select_problem_button.dart';
import 'package:qr_machine_scanner/src/widgets/select_task_button.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';
import 'package:qr_machine_scanner/strings.dart';

class ResultControls extends StatefulWidget {
  final TextEditingController descController;
  final SelectImageButtonController imageData1Controller;
  final SelectImageButtonController imageData2Controller;
  final SelectImageButtonController imageData3Controller;
  final TextEditingController priorityController;
  final SelectProblemButtonController problemController;
  final SelectTaskButtonController taskController;
  final EquipmentDetailController equipmentDetailController;
  final InventoryRecord machine;

  const ResultControls({
    super.key,
    required this.descController,
    required this.imageData1Controller,
    required this.imageData2Controller,
    required this.imageData3Controller,
    required this.priorityController,
    required this.problemController,
    required this.taskController,
    required this.machine,
    required this.equipmentDetailController,
  });

  @override
  State<ResultControls> createState() => _ResultControlsState();
}

class _ResultControlsState extends State<ResultControls> {
  void _onValueChanged() {
    setState(() {});
  }

  @override
  void initState() {
    widget.problemController.valueNotifier.addListener(_onValueChanged);
    super.initState();
  }

  @override
  void dispose() {
    widget.problemController.valueNotifier.removeListener(_onValueChanged);
    super.dispose();
  }

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
        SelectProblemButton(
          machine: widget.machine,
          controller: widget.problemController,
        ),
        // Expanded(
        //     child: DropdownMenu(
        //   requestFocusOnTap: true,
        //   onSelected: (value) {
        //     setState(() {});
        //   },
        //   controller: widget.problemController,
        //   expandedInsets: EdgeInsets.zero,
        //   label: Text("Проблема"),
        //   initialSelection: "Проблем нет",
        //   dropdownMenuEntries: GlobalState.dataProvider.getTypicalProblemsForMachine(widget.machine.uuid).map((x) {
        //     return DropdownMenuEntry(value: x, label: x.title);
        //   }).toList(),
        // )),
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

    Widget? rest = Column(spacing: 8, children: [
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
    ]);

    Widget selectTask =
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      FutureBuilder(
        future: GlobalState.syncTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (GlobalState.dataProvider
                    .getTasksForMachine(widget.machine.uuid)
                    .length >
                0) {
              return SelectTaskButton(
                  machine: widget.machine,
                  controller: widget.taskController,
                  equipmentDetailController: widget.equipmentDetailController);
            } else {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Нет активных задач',
                  style: TextStyle(color: Colors.black26),
                ),
              );
            }
          }
          return Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Загрузка задач',
                    style: TextStyle(color: Colors.black26),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  const Center(
                      child: CircularProgressIndicator(
                    color: Colors.black26,
                    strokeWidth: 2,
                    constraints: BoxConstraints(minHeight: 8, minWidth: 8),
                  ))
                ],
              ));
        },
      ),
      // SelectTaskButton(
      //   machine: widget.machine,
      //   controller: widget.taskController,
      // )
    ]);

    if (widget.problemController.value == null) {
      rest = null;
    }

    return Column(
      spacing: 8,
      children: [
        selectTask,
        SizedBox(
          height: 8,
        ),
        problemSelect,
        // prioritySelect,
        if (rest != null) rest,
        SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: addButtons,
            )),
        SizedBox(),
        SizedBox(
          height: 8,
        ),
      ],
    );
  }
}

class YandexImage extends StatelessWidget {
  final String imageUrl;

  const YandexImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.shortestSide,
            // Set width
            height: MediaQuery.of(context).size.shortestSide,
            // Set height to be equal for a square
            // decoration: BoxDecoration(
            //   image: DecorationImage(
            //     image: NetworkImage(imageUrl),
            //     alignment: Alignment.center,// Your image source
            //     fit: BoxFit.cover, // How the image should be inscribed into the box
            //   ),
            //   // You can add other decoration properties here, like:
            //   // color: Colors.blue, // Background color of the container
            //   // borderRadius: BorderRadius.circular(10), // To make it a rounded square
            // ),
            // child: BackdropFilter(
            //   filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            //   child: Container(
            //     decoration: new BoxDecoration(color: Colors.white.withOpacity(0.0)),
            //   ),
            // ),
            color: Colors.black,
          ),
          Container(
            width: MediaQuery.of(context).size.shortestSide, // Set width
            height: MediaQuery.of(context)
                .size
                .shortestSide, // Set height to be equal for a square
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                alignment: Alignment.center, // Your image source
                fit: BoxFit
                    .contain, // How the image should be inscribed into the box
              ),
              // You can add other decoration properties here, like:
              // color: Colors.blue, // Background color of the container
              // borderRadius: BorderRadius.circular(10), // To make it a rounded square
            ),
          )
        ],
      ),
    );
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Text('Failed to load image'));
      },
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
  final descController = TextEditingController();
  final imageData1Controller = SelectImageButtonController();
  final imageData2Controller = SelectImageButtonController();
  final imageData3Controller = SelectImageButtonController();
  final priorityController = TextEditingController();
  final problemController = SelectProblemButtonController();
  final taskController = SelectTaskButtonController();
  final equipmentController = EquipmentDetailController();

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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: max(MediaQuery.of(context).size.shortestSide, 350)
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(color: Colors.black87,),
                Image.network(
                  widget.machine.imageData,
                )
              ],
            ),
          ),
          // YandexImage(imageUrl: widget.machine.imageData,),
          Row(
            children: [
              Expanded(child: MarkdownBody(data: """
${widget.machine.descriptionText}
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
                  ResultControls(
                    machine: widget.machine,
                    descController: descController,
                    imageData1Controller: imageData1Controller,
                    imageData2Controller: imageData2Controller,
                    imageData3Controller: imageData3Controller,
                    priorityController: priorityController,
                    problemController: problemController,
                    taskController: taskController,
                    equipmentDetailController: equipmentController,
                  )
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
                            for (var task in equipmentController.value) {
                              await dataProvider.addScan(Scan(
                                  taskUuid: task.uuid,
                                  resultStatus: 'closed',
                                  files: [
                                    imageData1Controller.value,
                                    imageData2Controller.value,
                                    imageData3Controller.value,
                                  ].where((v) {
                                    return v.length > 0;
                                  }).toList(),
                                  comment: '',
                                  equipmentUuid: '',
                                  faultUuid: '',
                                  periodicTaskUuid: task.periodicTask.uuid));
                            }
                            var status = 'closed';
                            if (problemController.value != null) {
                              status = 'open';
                            }
                            await dataProvider.addScan(Scan(
                                taskUuid: '',
                                resultStatus: status,
                                files: [
                                  imageData1Controller.value,
                                  imageData2Controller.value,
                                  imageData3Controller.value,
                                ].where((v) {
                                  return v.length > 0;
                                }).toList(),
                                comment: descController.text,
                                equipmentUuid: widget.machine.uuid,
                                faultUuid: problemController.value != null &&
                                        problemController.value!.id != 0
                                    ? problemController.value!.uuid
                                    : '',
                                periodicTaskUuid: ''));
                            //TODO:     ts: GlobalState.now
                            // await dataProvider.syncScans();
                            GoRouter.of(context)
                                .clearStackAndNavigate("/qr_scanner");
                          });
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
