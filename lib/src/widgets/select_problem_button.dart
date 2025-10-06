import 'package:flutter/material.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/typical_problem.dart';

class SelectProblemButtonController {
  final ValueNotifier<TypicalProblem?> _valueNotifier = ValueNotifier(null);

  ValueNotifier<TypicalProblem?> get valueNotifier => _valueNotifier;

  TypicalProblem? get value => _valueNotifier.value;

  set value(TypicalProblem? newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }
}

class SelectProblemButton extends StatefulWidget {
  late final SelectProblemButtonController controller;
  final InventoryRecord machine;

  SelectProblemButton({super.key, controller = null, required this.machine}) {
    if (controller == null) {
      this.controller = SelectProblemButtonController();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectProblemButton> createState() => _SelectImageButton();
}

class _SelectImageButton extends State<SelectProblemButton> {
  TypicalProblem? typicalProblem = null;

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
      typicalProblem = widget.controller.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<DropdownMenuEntry> problems = [
      DropdownMenuEntry(
          value: TypicalProblem(
              id: -1,
              title: "Проблем нет",
              defaultPriority: "low",
              equipmentUUID: "-1",
              uuid: ''),
          label: "Проблем нет")
    ];
    problems.addAll(GlobalState.dataProvider
        .getTypicalProblemsForMachine(widget.machine.uuid)
        .map((x) {
      return DropdownMenuEntry(value: x, label: x.title);
    }).toList());
    problems.add(DropdownMenuEntry(
        value: TypicalProblem(
            id: 0,
            title: "Другое",
            defaultPriority: "low",
            equipmentUUID: "-1",
            uuid: ''),
        label: "Другое"));

    return Expanded(
        child: DropdownMenu(
      requestFocusOnTap: true,
      onSelected: (value) {
        if ((value as TypicalProblem).id == -1) {
          widget.controller.value = null;
          return;
        }
        widget.controller.value = value;
      },
      expandedInsets: EdgeInsets.zero,
      label: Text("Проблема"),
      initialSelection: widget.controller.value == null
          ? "Проблем нет"
          : widget.controller.value!.title,
      dropdownMenuEntries: problems,
    ));
  }
}
