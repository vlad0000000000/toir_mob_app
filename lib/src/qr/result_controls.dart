import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:qr_scan_industry/settings.dart';
import '../../global_state.dart';
import '../../src/model/priority.dart';
import '../../src/model/inventory_record.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/select_image_button.dart';
import '../../src/widgets/select_priority_button.dart';
import '../../src/widgets/select_problem_button.dart';
import '../../src/widgets/select_task_button.dart';
import '../../src/widgets/select_usage_button.dart';
import '../../strings.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../utils/any_controller.dart';

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
      ],
    );

    Widget prioritySelect = Row(
      children: [
        SelectPriorityButton(
          controller: widget.priorityController,
          errorText: widget.highlightPriorityError ? 'Укажите приоритет' : null,
        )
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
          maxLines: 8,
          controller: widget.descController,
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
            height: MediaQuery.of(context).size.shortestSide,
            color: Colors.black,
          ),
          Container(
            width: MediaQuery.of(context).size.shortestSide,
            height: MediaQuery.of(context).size.shortestSide,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                alignment: Alignment.center,
                fit: BoxFit.contain,
              ),
            ),
          )
        ],
      ),
    );
  }
}
