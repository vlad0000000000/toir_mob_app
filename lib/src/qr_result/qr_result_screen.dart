import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app/settings.dart';
import 'package:provider/provider.dart';
import '../../src/widgets/select_priority_button.dart';
import '../../src/model/priority.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/data/data_provider.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/scan.dart';
import '../../src/tasks/tasks.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../src/widgets/select_image_button.dart';
import '../../src/widgets/select_problem_button.dart';
import '../../src/widgets/select_task_button.dart';
import '../../src/widgets/square_button.dart';
import '../../strings.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../update_manager.dart';
import '../utils/any_controller.dart';
import '../../src/widgets/select_usage_button.dart';
import '../../src/model/usage_unit.dart';

class ResultControls extends StatefulWidget {
  final TextEditingController descController;
  final SelectImageButtonController imageData1Controller;
  final SelectImageButtonController imageData2Controller;
  final SelectImageButtonController imageData3Controller;
  final AnyController<Priority> priorityController;
  final AnyController<TypicalProblem> problemController;
  final EquipmentDetailController equipmentDetailController;
  final AnyController<List<UsageUpdate>> usageController;
  final InventoryRecord machine;

  const ResultControls({
    super.key,
    required this.descController,
    required this.imageData1Controller,
    required this.imageData2Controller,
    required this.imageData3Controller,
    required this.priorityController,
    required this.problemController,
    required this.machine,
    required this.equipmentDetailController,
    required this.usageController,
  });

  @override
  State<ResultControls> createState() => _ResultControlsState();
}

class _ResultControlsState extends State<ResultControls> {
  bool firstPaint = true;

  void _onValueChanged() {
    setState(() {});
  }

  @override
  void initState() {
    widget.problemController.valueNotifier.addListener(_onValueChanged);
    widget.priorityController.valueNotifier.addListener(_onValueChanged);
    // widget.usageController.valueNotifier.addListener(_onValueChanged);
    super.initState();
  }

  @override
  void dispose() {
    widget.problemController.valueNotifier.removeListener(_onValueChanged);
    widget.priorityController.valueNotifier.removeListener(_onValueChanged);
    // widget.usageController.valueNotifier.removeListener(_onValueChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Settings.qrResultShowTasksFirst && firstPaint) {
      if (GlobalState.dataProvider
              .getTasksForMachine(widget.machine.uuid)
              .length >
          0) {
        scheduler.SchedulerBinding.instance.addPostFrameCallback((ts) {
          firstPaint = false;
          SelectTaskButton.showModal(
              context, widget.machine, widget.equipmentDetailController);
        });
      }
    }

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
        //   initialSelection: "",
        //   dropdownMenuEntries: GlobalState.dataProvider.getTypicalProblemsForMachine(widget.machine.uuid).map((x) {
        //     return DropdownMenuEntry(value: x, label: x.title);
        //   }).toList(),
        // )),
      ],
    );

    Widget prioritySelect = Row(
      children: [
        SelectPriorityButton(
          controller: widget.priorityController,
        )
        // Expanded(
        //     child: DropdownMenu(
        //   // menuStyle: MenuStyle(
        //   //   backgroundColor: WidgetStatePropertyAll(Colors.red),
        //   // ),
        //   requestFocusOnTap: true,
        //   controller: widget.priorityController,
        //   label: Text(Strings.priority),
        //   expandedInsets: EdgeInsets.zero,
        //   onSelected: (x) {
        //     // setState(() {
        //     //   widget.priorityController.text = x;
        //     // });
        //     // widget.priorityController.value = x;
        //   },
        //   dropdownMenuEntries: Priorities.ALL.map((x) {
        //     return DropdownMenuEntry<Priority>(
        //         value: x,
        //         label: x.name,
        //         style: ButtonStyle(
        //           backgroundColor: WidgetStatePropertyAll(x.color),
        //         ),
        //         labelWidget: Text(
        //           x.name as String,
        //           style: TextStyle(color: Colors.black),
        //         ));
        //   }).toList(),
        // )),
      ],
    );

    Widget? rest = Column(spacing: 8, children: [prioritySelect]);

    Widget selectTask =
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      FutureBuilder(
        // future: GlobalState.syncTasks(),
        future: Future.value(1),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (GlobalState.dataProvider
                    .getTasksForMachine(widget.machine.uuid)
                    .length >
                0) {
              return SelectTaskButton(
                  machine: widget.machine,
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

    if (widget.problemController.value == null ||
        widget.problemController.value! != TypicalProblem.other) {
      rest = null;
    }

    Widget? selectUsage = Row(
      children: [
        SelectUsageButton(
          machine: widget.machine,
          controller: widget.usageController,
        ),
      ],
    );

    if (widget.machine.usageParameters.length == 0) {
      selectUsage = null;
    }

    return Column(
      spacing: 8,
      children: [
        if (selectUsage != null) selectUsage,
        selectTask,
        problemSelect,
        if (rest != null) rest,
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
        // if (rest != null) rest,
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
  }
}

class QRResultScreen extends StatefulWidget {
  final InventoryRecord machine;
  final String openDateTime;

  const QRResultScreen(this.machine, {super.key, required this.openDateTime});

  @override
  State<QRResultScreen> createState() => _QRResultScreenState();
}

class _QRResultScreenState extends State<QRResultScreen> {
  final descController = TextEditingController();
  final imageData1Controller = SelectImageButtonController();
  final imageData2Controller = SelectImageButtonController();
  final imageData3Controller = SelectImageButtonController();
  final priorityController = AnyController<Priority>();
  final problemController = AnyController<TypicalProblem>();
  final equipmentController = EquipmentDetailController();
  final usageController = AnyController<List<UsageUpdate>>();

  Widget passport() {
    // Упрощенный вид - только название станка
    if (Settings.qrResultShowSimplifiedView) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          widget.machine.name,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

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
                maxHeight: max(MediaQuery.of(context).size.shortestSide, 350)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  color: Colors.black87,
                ),
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

  List<UsageUpdate> createUsageScans() {
    List<UsageUpdate> result = [];
    if (usageController.value != null) {
      for (var usageParameter in usageController.value!) {
        result.add(usageParameter);
      }
    }
    return result;
  }

  List<Scan> createScans() {
    List<Scan> result = [];
    var status = 'closed';
    if (problemController.value != null) {
      status = 'open';
    }
    var files = [
      imageData1Controller.value,
      imageData2Controller.value,
      imageData3Controller.value,
    ].where((v) {
      return v.length > 0;
    }).toList();

    var faultUUID =
        problemController.value != null && problemController.value!.id != 0
            ? problemController.value!.uuid
            : '';
    var priority = priorityController.value == null
        ? null
        : priorityController.value!.value;
    if (problemController.value != null && priority == null) {
      priority = (problemController.value!).defaultPriority;
    }
    var hasData = false;
    hasData = hasData || descController.text.length > 0;
    hasData = hasData || files.length > 0;
    hasData =
        hasData || (hasData && problemController.value == TypicalProblem.other);
    hasData = hasData ||
        (problemController.value != null &&
            problemController.value != TypicalProblem.other);

    var hasTasks = equipmentController.value.length > 0;
    for (var task in equipmentController.value) {
      if (task.resultStatus == 'scheduled') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: files,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: task.periodicTask!.uuid));
      }
      if (task.resultStatus == 'open') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: files,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: ''));
      }
    }

    if (hasData) {
      result.add(Scan(
          taskUuid: '',
          resultStatus: status,
          files: files,
          comment: descController.text,
          priority: priority,
          equipmentUuid: widget.machine.uuid,
          closedAt: GlobalState.nowUTCDate,
          createdAt: widget.openDateTime,
          faultUuid: faultUUID,
          periodicTaskUuid: ''));
    }
    return result;
  }

  addScans(List<Scan> scans, List<UsageUpdate> usageScans) async {
    for (var usageParameter in usageScans) {
      await GlobalState.dataProvider.addUsageScan(usageParameter);
    }

    for (var scan in scans) {
      await GlobalState.dataProvider.addScan(scan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = context.watch<DataProvider>();

    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        UpdateManager.checkForUpdate(context);
      },
    );

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
                    equipmentDetailController: equipmentController,
                    usageController: usageController,
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
                          var scans = createScans();
                          var usageScans = createUsageScans();
                          if (scans.length + usageScans.length == 0) {
                            Dialogs.notify(context, 'Не отправлено',
                                'Укажите данные обхода (комментарий, фото, типовая неисправность, задача или наработка)');
                          } else {
                            Dialogs.areYouSure(context, onOk: () async {
                              // await dataProvider.syncScans();
                              // dataProvider.syncInventory();
                              await addScans(scans, usageScans);
                              dataProvider.mainSync();
                              if (GoRouter.of(context).location ==
                                  '/qr_result_problems') {
                                GoRouter.of(context)
                                    .clearStackAndNavigate("/problems");
                              } else {
                                GoRouter.of(context)
                                    .clearStackAndNavigate("/qr_scanner");
                              }
                            });
                          }
                        },
                        child: Text("Отправить")))
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
