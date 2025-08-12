import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/tasks/tasks.dart';
import 'package:qr_machine_scanner/src/widgets/square_button.dart';
import 'package:qr_machine_scanner/strings.dart';
import 'package:themed/themed.dart';

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
  late final SelectTaskButtonController controller;
  Machine machine;

  SelectTaskButton({required this.machine, super.key, controller = null}) {
    if (controller == null) {
      this.controller = SelectTaskButtonController();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectTaskButton> createState() => _SelectImageButton();
}

class _SelectImageButton extends State<SelectTaskButton> {
  Task? task = null;

  @override
  void dispose() {
    widget.controller.valueNotifier.removeListener(_onValueChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.valueNotifier.addListener(_onValueChanged);
  }

  void _onValueChanged() {
    setState(() {
      task = widget.controller.value;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  task.node,
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

    // List<Widget> equipmentList = [];
    // for (int ei
    //     in EquipmentListScreen.machineIdToEquipment[widget.machine.id]!) {
    //   equipmentList.add(Flexible(child: EquipmentDetailScreen(
    //     isModal: true,
    //     onTaskTap: (Task task) {
    //       widget.controller.value = task;
    //       Navigator.pop(context);
    //     },
    //     equipment: EquipmentListScreen.equipmentListAll[ei],
    //   )));
    //   equipmentList.add(SizedBox(height: 20,));
    // }

    // final mediaQuery = MediaQuery.of(context);
    // final height = mediaQuery.size.height * 0.9;
    // Widget modal = Container(
    //   padding: EdgeInsets.symmetric(vertical: 10),
    //   height: height,
    //   child: Column(
    //     children: [
    //       SizedBox(
    //         height: 10,
    //       ),
    //       Row(
    //         mainAxisAlignment: MainAxisAlignment.end,
    //         children: [
    //           InkWell(
    //             child: Icon(
    //               Icons.close,
    //               size: 32,
    //             ),
    //             onTap: () => Navigator.of(context).pop(),
    //           ),
    //           SizedBox(width: 20)
    //         ],
    //       ),
    //       SizedBox(
    //         height: 10,
    //       ),
    //       Expanded(child:     equipmentList[0])
    //     ],
    //   ),
    //   margin: EdgeInsets.symmetric(
    //     horizontal: 20,
    //     vertical: 20,
    //   ),
    //   decoration: BoxDecoration(
    //     color: Colors.white,
    //     borderRadius: BorderRadius.circular(20),
    //     boxShadow: [
    //       BoxShadow(
    //         color: Colors.black.withOpacity(0.3),
    //         blurRadius: 20,
    //         spreadRadius: 5,
    //       )
    //     ],
    //   ),
    // );

    // Widget modal = equipmentList[0];

    return Expanded(
        child: SquareButton(
      child: Text('Выбрать задачу'),
      onPressed: () {
        showModalBottomSheet(
            barrierColor: Colors.black54,
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            isScrollControlled: true,
            // Ключевой параметр для полного экрана
            backgroundColor: Colors.transparent,
            // builder: (context) {
            //   return Column(
            //     children: equipmentList,
            //   );
            // }
            // builder: (context) => modal,
            builder: (context) => EquipmentDetailScreen(
                  isModal: true,
                  onTaskTap: (Task task) {
                    widget.controller.value = task;
                    Navigator.pop(context);
                  },
                  equipment: EquipmentListScreen.equipmentListAll[EquipmentListScreen.machineIdToEquipment[widget.machine.id]![0]],
                )
            );
      },
    ));
  }
}
