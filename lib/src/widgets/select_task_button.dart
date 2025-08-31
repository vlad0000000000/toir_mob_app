import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/tasks/tasks.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';

class SelectTaskButtonController {
  final ValueNotifier<Task?> _valueNotifier = ValueNotifier(null);

  ValueNotifier<Task?> get valueNotifier => _valueNotifier;

  Task? get value => _valueNotifier.value;

  set value(Task? newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }
}

class SelectTaskButton extends StatefulWidget {
  final SelectTaskButtonController controller;
  final EquipmentDetailController equipmentDetailController;
  Machine machine;

  SelectTaskButton(
      {required this.machine,
      super.key,
      required this.controller,
      required this.equipmentDetailController}) {}

  @override
  State<SelectTaskButton> createState() => _SelectImageButton();
}

class _SelectImageButton extends State<SelectTaskButton> {
  @override
  void dispose() {
    // widget.controller.valueNotifier.removeListener(_onValueChanged);
    widget.equipmentDetailController.valueNotifier
        .removeListener(_onValueChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // widget.controller.valueNotifier.addListener(_onValueChanged);
    widget.equipmentDetailController.valueNotifier.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.equipmentDetailController.selectedTasks.length > 0 && false) {
      return Expanded(
          child: SquareButton(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выбрано задач: ' +
                      widget.equipmentDetailController.selectedTasks.length
                          .toString(),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            )),
            SizedBox(
              width: 10,
            ),
            Icon(
              Icons.close,
              size: 24,
            )
          ],
        ),
        onPressed: () {
          widget.equipmentDetailController.clearSelection();
        },
      ));
    }

    if (widget.controller.value != null) {
      Task task = widget.controller.value!;
      return Expanded(
          child: SquareButton(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.operation,
                  style: TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.node != null && task.node!.length > 0)
                  Text(
                    task.node!,
                    style: TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            )),
            SizedBox(
              width: 10,
            ),
            Icon(
              Icons.close,
              size: 24,
            )
          ],
        ),
        onPressed: () {
          widget.controller.value = null;
        },
      ));
    }

    return Expanded(
        child: SquareButton(
      child: widget.equipmentDetailController.selectedTasks.length > 0
          ? Text(
              'Выбрано задач: ' +
                  widget.equipmentDetailController.selectedTasks.length
                      .toString(),
              style: TextStyle(fontWeight: FontWeight.bold),
            )
          : Text('Выбрать задачу'),
      onPressed: () {
        // GlobalState.needTaskSync = true;
        showModalBottomSheet(
            barrierColor: Colors.black54,
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            isScrollControlled: true,
            // Ключевой параметр для полного экрана
            backgroundColor: Colors.transparent,
            builder: (context) => Modal(
                    child: EquipmentDetailScreen(
                  isModal: true,
                  controller: widget.equipmentDetailController,
                  onTaskTap: (Task task) {
                    widget.controller.value = task;
                    Navigator.pop(context);
                  },
                  machine: widget.machine,
                )));
      },
    ));
  }
}
