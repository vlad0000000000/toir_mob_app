import 'package:flutter/material.dart';
import '../../src/model/priority.dart';
import '../../src/utils/any_controller.dart';
import '../../strings.dart';

class SelectPriorityButton extends StatefulWidget {
  late final AnyController<Priority> controller;
  final String? errorText;

  SelectPriorityButton({super.key, controller = null, this.errorText}) {
    if (controller == null) {
      this.controller = AnyController<Priority>();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectPriorityButton> createState() => _SelectPriorityButton();
}

class _SelectPriorityButton extends State<SelectPriorityButton> {
  Priority? value = null;

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
      value = widget.controller.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: DropdownMenu(
      requestFocusOnTap: true,
      onSelected: (value) {
        widget.controller.value = value as Priority?;
      },
      expandedInsets: EdgeInsets.zero,
      label: Text(Strings.priority),
      errorText: widget.errorText,
      initialSelection:
          widget.controller.value == null ? "" : widget.controller.value!.name,
      dropdownMenuEntries: Priorities.ALL.map((x) {
        return DropdownMenuEntry<Priority>(
            value: x,
            label: x.name,
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(x.color),
            ),
            labelWidget: Text(
              x.name as String,
              style: TextStyle(color: Colors.black),
            ));
      }).toList(),
    ));
  }
}
