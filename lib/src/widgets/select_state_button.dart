import 'package:flutter/material.dart';
import '../../src/utils/any_controller.dart';
import '../../global_state.dart';
import 'controller_listener_mixin.dart';

class SelectStateButton extends StatefulWidget {
  late final AnyController<String> controller;
  final String? initialValue;

  SelectStateButton({super.key, controller, this.initialValue}) {
    if (controller == null) {
      this.controller = AnyController<String>();
    } else {
      this.controller = controller;
    }
  }

  @override
  State<SelectStateButton> createState() => _SelectStateButton();
}

class _SelectStateButton extends State<SelectStateButton>
    with ControllerListenerMixin {
  String? value = null;

  @override
  Listenable get controllerListenable => widget.controller.valueNotifier;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      widget.controller.value = widget.initialValue;
      value = widget.initialValue;
    }
  }

  @override
  void onControllerChanged() {
    setState(() {
      value = widget.controller.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final equipmentState = GlobalState.dataProvider.equipmentState;
    if (equipmentState == null || equipmentState.states.isEmpty) {
      return SizedBox.shrink();
    }

    List<DropdownMenuEntry<String>> entries = [];
    if (value == null) {
      entries.add(DropdownMenuEntry<String>(value: "", label: "Нет состояния"));
    }

    entries.addAll(equipmentState.states.entries.map((entry) {
      return DropdownMenuEntry<String>(
        value: entry.key,
        label: entry.value,
      );
    }).toList());

    return Expanded(
        child: DropdownMenu<String>(
      requestFocusOnTap: false,
      enableSearch: false,
      onSelected: (selectedValue) {
        widget.controller.value = selectedValue;
      },
      expandedInsets: EdgeInsets.zero,
      label: Text("Состояние"),
      initialSelection: value ?? "",
      dropdownMenuEntries: entries,
    ));
  }
}
