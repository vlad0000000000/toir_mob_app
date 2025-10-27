import 'package:flutter/material.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/square_button.dart';
import 'modal.dart';

class SelectTaskButton extends StatefulWidget {
  final EquipmentDetailController equipmentDetailController;
  InventoryRecord machine;

  SelectTaskButton(
      {required this.machine,
      super.key,
      required this.equipmentDetailController}) {}

  @override
  State<SelectTaskButton> createState() => _SelectImageButton();

  static showModal(context, machine, equipmentDetailController){
    showModalBottomSheet(
        barrierColor: Colors.black54,
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        isScrollControlled: true,
        enableDrag: false,
        isDismissible: false,
        // Ключевой параметр для полного экрана
        backgroundColor: Colors.transparent,
        builder: (context) => Modal(
            child: EquipmentDetailScreen(
              isModal: true,
              controller: equipmentDetailController,
              onTaskTap: (Task task) {
                Navigator.pop(context);
              },
              machine: machine,
            )));
  }
}

class _SelectImageButton extends State<SelectTaskButton> {
  @override
  void dispose() {
    widget.equipmentDetailController.valueNotifier
        .removeListener(_onValueChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.equipmentDetailController.valueNotifier.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

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
