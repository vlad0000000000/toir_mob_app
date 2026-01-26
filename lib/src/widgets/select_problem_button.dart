import 'package:flutter/material.dart';
import '../../src/utils/any_controller.dart';
import '../../global_state.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/typical_problem.dart';

class SelectProblemButton extends StatefulWidget {
  late final AnyController<TypicalProblem> controller;
  final InventoryRecord machine;

  SelectProblemButton({super.key, controller = null, required this.machine}) {
    if (controller == null) {
      this.controller = AnyController<TypicalProblem>();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectProblemButton> createState() => _SelectProblemButton();
}

class _SelectProblemButton extends State<SelectProblemButton> {
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
          value: TypicalProblem.empty, label: TypicalProblem.empty.title)
    ];
    problems.addAll(GlobalState.dataProvider
        .getTypicalProblemsForMachine(widget.machine.uuid)
        .map((x) {
      return DropdownMenuEntry(value: x, label: x.title);
    }).toList());
    problems.add(DropdownMenuEntry(
        value: TypicalProblem.other, label: TypicalProblem.other.title));

    return Expanded(
        child: DropdownMenu(
      requestFocusOnTap: true,
      onSelected: (value) {
        if ((value as TypicalProblem) == TypicalProblem.empty) {
          widget.controller.value = null;
          return;
        }
        widget.controller.value = value;
      },
      expandedInsets: EdgeInsets.zero,
      label: Text("Проблема"),
      initialSelection:
          widget.controller.value == null ? "" : widget.controller.value!.title,
      dropdownMenuEntries: problems,
    ));
  }
}
