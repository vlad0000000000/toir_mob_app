import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_scan_industry/settings.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/data/data_provider.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/priority.dart';
import '../../src/model/scan.dart';
import '../../src/tasks/tasks.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../src/widgets/select_image_button.dart';
import '../../src/widgets/select_state_button.dart';
import '../../src/widgets/square_button.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../model/periodic_task_request.dart';
import '../update_manager.dart';
import '../utils/any_controller.dart';
import '../../src/onboarding/demo_equipment.dart';
import 'result_controls.dart';

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
      // Demo mode: skip API call, just update UI
      if (widget.machine.uuid == DemoEquipment.demoUuid) {
        _previousState = newState;
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
        return;
      }
      try {
        await GlobalState.dataProvider
            .updateEquipmentState(widget.machine.uuid, newState);
        _previousState = newState;

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
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
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
          if (widget.machine.imageData.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight:
                      max(MediaQuery.of(context).size.shortestSide, 350)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    color: Theme.of(context).colorScheme.inverseSurface,
                  ),
                  Image.network(
                    widget.machine.imageData,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .onInverseSurface
                            .withValues(alpha: 0.5),
                      );
                    },
                  )
                ],
              ),
            ),
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
            Row(
              spacing: 8,
              children: [
                Expanded(
                    child: SquareButton(
                        onPressed: () {
                          final isDemoMode = widget.machine.uuid ==
                              DemoEquipment.demoUuid;
                          if (isDemoMode) {
                            Settings.onboardingStep = 4;
                            GoRouter.of(context)
                                .clearStackAndNavigate('/onboarding_video');
                            return;
                          }
                          var scans = createScans();
                          var usageScans = createUsageScans();
                          if (scans != null) {
                            if (scans.length + usageScans.length == 0) {
                              Dialogs.notify(context, 'Не отправлено',
                                  'Укажите данные обхода (комментарий, проблему, задачу или наработку)');
                            } else {
                              var rewriteMessage = null;
                              var desc = null;
                              Dialogs.areYouSure(context, onOk: () async {
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

  bool _isProcessingConflict = false;

  void _onProblemChanged() async {
    if (_isProcessingConflict) return;

    final problem = problemController.value;

    if (problem != null && problem != TypicalProblem.empty) {
      if (equipmentController.selectedTasks.isNotEmpty) {
        if (!mounted) return;

        final cancelTask = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Задача и проблема'),
            content: const Text(
              'Нельзя одновременно выбрать задачу и проблему.\n\nОтменить задачу?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (cancelTask == true) {
          equipmentController.clearSelection();
        } else {
          _isProcessingConflict = true;
          problemController.value = null;
          _isProcessingConflict = false;
          return;
        }
      }
    }

    final currentProblem = problemController.value;
    if (currentProblem != TypicalProblem.other &&
        priorityController.value != null) {
      priorityController.value = null;
    }
  }

  void _onTaskChanged() async {
    if (_isProcessingConflict) return;

    if (equipmentController.selectedTasks.isNotEmpty) {
      if (problemController.value != null) {
        if (!mounted) return;

        final cancelProblem = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Задача и проблема'),
            content: const Text(
              'Нельзя одновременно выбрать задачу и проблему.\n\nОтменить проблему?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (cancelProblem == true) {
          _isProcessingConflict = true;
          problemController.value = null;
          _isProcessingConflict = false;
        } else {
          _isProcessingConflict = true;
          equipmentController.clearSelection();
          _isProcessingConflict = false;
        }
      }
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
    equipmentController.valueNotifier.addListener(_onTaskChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // stateController.valueNotifier.removeListener(_onStateChanged);
    descController.removeListener(_clearValidationHighlights);
    priorityController.valueNotifier.removeListener(_clearValidationHighlights);
    problemController.valueNotifier.removeListener(_onProblemChanged);
    equipmentController.valueNotifier.removeListener(_onTaskChanged);
    stateController.dispose();
    descController.dispose();
    imageData1Controller.dispose();
    imageData2Controller.dispose();
    imageData3Controller.dispose();
    equipmentController.dispose();
    super.dispose();
  }
}
