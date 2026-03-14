import 'dart:io';
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
import '../model/periodic_task_request.dart';
import '../update_manager.dart';
import '../utils/any_controller.dart';
import '../../src/widgets/select_usage_button.dart';
import '../../src/widgets/select_state_button.dart';

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
  final bool highlightDescError;
  final bool highlightPriorityError;

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
    this.highlightDescError = false,
    this.highlightPriorityError = false,
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
          errorText: widget.highlightPriorityError ? 'Укажите приоритет' : null,
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

    // Проверяем наличие параметров и соответствие роли пользователя
    final currentUserRole = GlobalState.authUser?.effectiveRole;
    final hasMatchingParameters = widget.machine.usageParameters.any(
      (param) => param.maintenanceRole?.name == currentUserRole,
    );

    if (widget.machine.usageParameters.length == 0 || !hasMatchingParameters) {
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
              labelText: Strings.checkDescription,
              errorText:
                  widget.highlightDescError ? 'Укажите комментарий' : null),
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
  final stateController = AnyController<String>();
  String? _previousState;
  bool _highlightDescError = false;
  bool _highlightPriorityError = false;

  void _onStateChanged() async {
    final newState = stateController.value;
    if (newState != null && newState.isNotEmpty && newState != _previousState) {
      try {
        await GlobalState.dataProvider.api
            .updateEquipmentState(widget.machine.uuid, newState);
        // Состояние будет обновлено при следующей синхронизации
        _previousState = newState;

        // Обновляем состояние оборудования в Hive боксе
        final inventoryBox = GlobalState.dataProvider.inventoryBox;
        for (var key in inventoryBox.keys) {
          final record = inventoryBox.get(key);
          if (record != null && record.uuid == widget.machine.uuid) {
            // Создаем новую запись с обновленным состоянием
            final updatedRecord = InventoryRecord(
              id: record.id,
              uuid: record.uuid,
              name: record.name,
              typeModel: record.typeModel,
              serialNumber: record.serialNumber,
              location: record.location,
              manufacturer: record.manufacturer,
              quantity: record.quantity,
              dateOfEntry: record.dateOfEntry,
              description: record.description,
              imageData: record.imageData,
              usageParameters: record.usageParameters,
              state: newState,
            );
            await inventoryBox.put(key, updatedRecord);
            GlobalState.dataProvider.updateInventoryRecords();
            break;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Состояние оборудования успешно изменено',
                style: TextStyle(color: Colors.black),
              ),
              backgroundColor: Colors.greenAccent,
            ),
          );
        }
      } on SocketException catch (_) {
        // Ошибка соединения с сервером
        print('Ошибка обновления статуса оборудования: отсутствует интернет');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Состояние не обновлено, потому что нет интернета',
                  style: TextStyle(color: Colors.black)),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } on HttpException catch (_) {
        // Ошибка HTTP соединения
        print('Ошибка обновления статуса оборудования: отсутствует интернет');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Состояние не обновлено, потому что нет интернета',
                  style: TextStyle(color: Colors.black)),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        // Проверяем, не является ли это ошибкой соединения
        final errorString = e.toString();
        if (errorString.contains('SocketException') ||
            errorString.contains('Failed host lookup') ||
            errorString.contains('Connection refused') ||
            errorString.contains('Network is unreachable') ||
            errorString.contains('TimeoutException')) {
          print('Ошибка обновления статуса оборудования: отсутствует интернет');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Состояние не обновлено, потому что нет интернета',
                    style: TextStyle(color: Colors.black)),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        } else {
          // Другие ошибки
          print('Ошибка обновления статуса оборудования: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось изменить состояние оборудования',
                    style: TextStyle(color: Colors.black)),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      }
    }
  }

  Widget passport() {
    // Упрощенный вид - только название станка
    if (Settings.qrResultShowSimplifiedView) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            spacing: 8,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                widget.machine.descriptionTextSimple,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              Row(
                children: [
                  SelectStateButton(
                    controller: stateController,
                    initialValue: widget.machine.state,
                  ),
                ],
              ),
            ],
          ));
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
          SizedBox(
            height: 0,
          ),
          Row(
            children: [
              SelectStateButton(
                controller: stateController,
                initialValue: widget.machine.state,
              ),
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

  List<Scan>? createScans() {
    List<Scan> result = [];

    var images = [
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
    var hasDesc = descController.text.length > 0;
    var hasPriority = priority != null;
    var hasOtherProblem = (problemController.value == TypicalProblem.other);
    var hasTypicalProblem = (problemController.value != null &&
        problemController.value != TypicalProblem.other);

    var hasTasks = false;
    for (var task in equipmentController.value) {
      if (task.resultStatus == 'scheduled') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: images,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: task.periodicTask!.uuid));
        hasTasks = true;
      }
      if (task.resultStatus == 'open') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: images,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: ''));
        hasTasks = true;
      }
    }

    print('hasDesc ${hasDesc}');
    print('hasProblem ${hasTypicalProblem}');
    print('hasProblem ${hasOtherProblem}');
    print('hasPriority ${hasPriority}');
    print('hasTasks ${hasTasks}');

    if (hasOtherProblem) {
      var returnEmpty = false;
      if (!hasDesc) {
        returnEmpty = true;
      }
      if (!hasPriority) {
        returnEmpty = true;
      }
      if (returnEmpty) {
        if (mounted) {
          setState(() {
            _highlightDescError = !hasDesc;
            _highlightPriorityError = !hasPriority;
          });
        }
        return null;
      }
    }

    if (mounted) {
      setState(() {
        _highlightDescError = false;
        _highlightPriorityError = false;
      });
    }

    if ((hasDesc && hasOtherProblem && hasPriority) ||
        (hasTypicalProblem) ||
        (hasDesc && !hasOtherProblem && !hasPriority && !hasTypicalProblem && !hasTasks)) {
      result.add(Scan(
          taskUuid: '',
          resultStatus:
              (hasOtherProblem && faultUUID.length == 0) ? 'open' : 'closed',
          files: images,
          comment: descController.text,
          priority: priority,
          equipmentUuid: widget.machine.uuid,
          closedAt: GlobalState.nowUTCDate,
          createdAt: widget.openDateTime,
          faultUuid: faultUUID,
          isOtherFault: hasOtherProblem,
          periodicTaskUuid: ''));
    }
    return result;
  }

  addScans(List<Scan> scans, List<UsageUpdate> usageScans) async {
    for (var usageParameter in usageScans) {
      await GlobalState.dataProvider.addUsageScan(usageParameter);
    }

    for (var scan in scans) {
      if (scan.resultStatus == 'open') {
        scan.resultStatus = 'closed';
        var periodicTask = PeriodicTaskRequest(
          equipmentUuid: widget.machine.uuid,
          node: null,
          title: 'Проблема',
          description:
              descController.text.isNotEmpty ? descController.text : null,
          periodicityRule: 'once',
          customRoleIds: null,
          nextDueAt: GlobalState.nowUTCDate,
          photos: scan.files,
          params: {
            'target_type': 'ad_hoc',
            'priority': scan.priority,
          },
        );
        await GlobalState.dataProvider.addPeriodicTask(periodicTask);
      }
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
                spacing: 8,
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
                    highlightDescError: _highlightDescError,
                    highlightPriorityError: _highlightPriorityError,
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
                          if (scans != null) {
                            if (scans.length + usageScans.length == 0) {
                              Dialogs.notify(context, 'Не отправлено',
                                  'Укажите данные обхода (комментарий, проблему, задачу или наработку)');
                            } else {
                              var rewriteMessage = null;
                              var desc = null;
                              // if (scans.length == 0) {
                              //   rewriteMessage =
                              //       'Вы уверены, что хотите отправить только наработку?';
                              // }
                              Dialogs.areYouSure(context, onOk: () async {
                                // await dataProvider.syncScans();
                                // dataProvider.syncInventory();
                                await addScans(scans, usageScans);
                                dataProvider.mainSync();
                                for (var usageScan in usageScans) {
                                  if (usageScan.usageParameterValue == null) {
                                    continue;
                                  }
                                  for (var usageParam
                                      in widget.machine.usageParameters) {
                                    if (usageScan.usageParameterUuid ==
                                        usageParam.uuid) {
                                      usageParam.currentValue =
                                          usageScan.usageParameterValue!;
                                    }
                                  }
                                }
                                if (GoRouter.of(context).location ==
                                    '/qr_result_problems') {
                                  GoRouter.of(context)
                                      .clearStackAndNavigate("/problems");
                                } else {
                                  GoRouter.of(context)
                                      .clearStackAndNavigate("/qr_scanner");
                                }
                              }, rewriteMessage: rewriteMessage, desc: desc);
                            }
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

  void _clearValidationHighlights() {
    if (_highlightDescError || _highlightPriorityError) {
      setState(() {
        _highlightDescError = false;
        _highlightPriorityError = false;
      });
    }
  }

  void _onProblemChanged() {
    if (problemController.value != TypicalProblem.other &&
        priorityController.value != null) {
      priorityController.value = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _previousState = widget.machine.state;
    stateController.valueNotifier.addListener(_onStateChanged);
    descController.addListener(_clearValidationHighlights);
    priorityController.valueNotifier.addListener(_clearValidationHighlights);
    problemController.valueNotifier.addListener(_onProblemChanged);

    // Preload ad for the win screen.
    // final adsRemoved =
    //     context.read<InAppPurchaseController?>()?.adRemoval.active ?? false;
    // if (!adsRemoved) {
    //   final adsController = context.read<AdsController?>();
    //   adsController?.preloadAd();
    // }
  }

  @override
  void dispose() {
    // stateController.valueNotifier.removeListener(_onStateChanged);
    descController.removeListener(_clearValidationHighlights);
    priorityController.valueNotifier.removeListener(_clearValidationHighlights);
    problemController.valueNotifier.removeListener(_onProblemChanged);
    stateController.dispose();
    descController.dispose();
    imageData1Controller.dispose();
    imageData2Controller.dispose();
    imageData3Controller.dispose();
    equipmentController.dispose();
    super.dispose();
  }
}
