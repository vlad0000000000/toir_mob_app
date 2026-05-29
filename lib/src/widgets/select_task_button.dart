import 'package:flutter/material.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/square_button.dart';
import 'app_bottom_sheet.dart';
import 'controller_listener_mixin.dart';

class SelectTaskButton extends StatefulWidget {
  final EquipmentDetailController equipmentDetailController;
  final InventoryRecord machine;

  SelectTaskButton(
      {required this.machine,
      super.key,
      required this.equipmentDetailController}) {}

  @override
  State<SelectTaskButton> createState() => _SelectImageButton();

  static showModal(context, machine, equipmentDetailController) {
    showAppModalSheet(
      context,
      child: EquipmentDetailScreen(
        isModal: true,
        controller: equipmentDetailController,
        onTaskTap: (Task task) {
          Navigator.pop(context);
        },
        machine: machine,
      ),
    );
  }
}

class _SelectImageButton extends State<SelectTaskButton>
    with ControllerListenerMixin {
  @override
  Listenable get controllerListenable =>
      widget.equipmentDetailController.valueNotifier;

  @override
  Widget build(BuildContext context) {
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
        SelectTaskButton.showModal(context, widget.machine, widget.equipmentDetailController);
      },
    ));
  }
}
