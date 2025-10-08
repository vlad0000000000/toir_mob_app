import 'package:flutter/material.dart';
import 'package:my_app/src/model/usage_update.dart';
import 'package:my_app/src/utils/any_controller.dart';
import '../../global_state.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/usage_unit.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/square_button.dart';
import 'package:flutter/services.dart';

// class UsageController {
//   final ValueNotifier<List<UsageUpdate>> _valueNotifier = ValueNotifier([]);
//
//   ValueNotifier<List<UsageUpdate>> get valueNotifier => _valueNotifier;
//
//   List<UsageUpdate> get value => _valueNotifier.value;
//
//   set value(List<UsageUpdate> newValue) {
//     _valueNotifier.value = newValue;
//   }
//
//   void dispose() {
//     _valueNotifier.dispose();
//   }
//
//   final Set<UsageUpdate> selectedTasks = {};
//   VoidCallback? onSelectionChanged;
//
//   UsageController({this.onSelectionChanged});
//
//   void toggleSelection(UsageUpdate usageUpdate) {
//     if (selectedTasks.contains(usageUpdate)) {
//       selectedTasks.remove(usageUpdate);
//     } else {
//       selectedTasks.add(usageUpdate);
//     }
//     onSelectionChanged?.call();
//     value = selectedTasks.toList();
//   }
//
//   void selectAll(List<UsageUpdate> all) {
//     selectedTasks.addAll(all);
//     value = all;
//     onSelectionChanged?.call();
//   }
//
//   void clearSelection() {
//     selectedTasks.clear();
//     value = [];
//     onSelectionChanged?.call();
//   }
//
//   List<UsageUpdate> getSelection() {
//     return selectedTasks.toList();
//   }
// }

class SelectUsageButton extends StatefulWidget {
  final AnyController<List<UsageUpdate>> controller;
  final InventoryRecord machine;

  const SelectUsageButton({
    super.key,
    required this.controller,
    required this.machine,
  });

  @override
  State<SelectUsageButton> createState() => _SelectUsageButtonState();
}

class _SelectUsageButtonState extends State<SelectUsageButton> {
  @override
  void initState() {
    super.initState();
    widget.controller.valueNotifier.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    widget.controller.valueNotifier.removeListener(_onValueChanged);
    super.dispose();
  }

  void _onValueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    int selectedUsageCount =
        widget.controller.value == null ? 0 : widget.controller.value!.length;

    return Expanded(
      child: SquareButton(
        child: selectedUsageCount > 0
            ? Text(
                'Выбрано наработок: $selectedUsageCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text('Выбрать наработку'),
        onPressed: () {
          showModalBottomSheet(
            barrierColor: Colors.black54,
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Modal(
              child: UsageSelectionModal(
                machine: widget.machine,
                controller: widget.controller,
              ),
            ),
          );
        },
      ),
    );
  }
}

class UsageSelectionModal extends StatefulWidget {
  final InventoryRecord machine;
  final AnyController<List<UsageUpdate>> controller;

  const UsageSelectionModal({
    super.key,
    required this.machine,
    required this.controller,
  });

  @override
  State<UsageSelectionModal> createState() => _UsageSelectionModalState();
}

class _UsageSelectionModalState extends State<UsageSelectionModal> {
  Map<String, TextEditingController> usageControllers = {};

  @override
  void initState() {
    super.initState();
    for (var unit in widget.machine.usageParameters) {
      usageControllers[unit.unitType] = TextEditingController();
      usageControllers[unit.unitType]!.text =
          unit.currentValue.toString(); // Display current value
      if (widget.controller.value != null &&
          widget.controller.value!.length > 0) {
        var selected = widget.controller.value!
            .where((element) => element.usageParameterUuid == unit.uuid);
        if (selected.length > 0) {
          usageControllers[unit.unitType]!.text = selected.first.usageParameterValue.toString();
        }
      }
    }
  }

  @override
  void dispose() {
    usageControllers.forEach((key, value) => value.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return Form(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Наработка для ${widget.machine.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.machine.usageParameters.length,
              itemBuilder: (context, index) {
                final usageParameter = widget.machine.usageParameters[index];
                final controller = usageControllers[usageParameter.unitType]!;
                List<UsageUnit> usageUnits =
                    GlobalState.dataProvider.usageUnits.toList();
                var usageUnit = usageUnits
                    .where(
                        (element) => element.value == usageParameter.unitType)
                    .toList()[0];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Text(usageUnit.displayName),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Текущее значение: ${usageParameter.currentValue}'),
                            Text(
                                'Следующее ТО: ${usageParameter.nextMaintenanceValue}'),
                            const SizedBox(height: 16),
                            TextFormField(
                              onChanged: (value) {
                                formKey.currentState!.validate();
                              },
                              controller: controller,
                              validator: (value) {
                                return usageParameter.validate(value);
                              },
                              keyboardType: TextInputType.number,
                              // inputFormatters: <TextInputFormatter>[
                              //   FilteringTextInputFormatter.digitsOnly,
                              //   FilteringTextInputFormatter.allow()
                              // ],
                              decoration: InputDecoration(
                                  labelText:
                                      'Новое значение (${usageUnit.shortName})',
                                  border: const OutlineInputBorder(),
                                  hoverColor: Colors.white,
                                  fillColor: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                    child: SquareButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }
                    List<UsageUpdate> newValues = [];
                    widget.machine.usageParameters.forEach(
                      (element) {
                        var controller = usageControllers[element.unitType];
                        if (controller != null &&
                            element.validate(controller.text) == null) {
                          newValues.add(UsageUpdate(
                              equipmentUuid: widget.machine.uuid,
                              usageParameterUuid: element.uuid,
                              usageParameterValue:
                                  double.parse(controller.text)));
                        }
                      },
                    );
                    widget.controller.value = newValues;
                    Navigator.pop(context);
                  },
                  child: const Text('Сохранить'),
                ))
              ],
            ),
          ),
        ],
      ),
      key: formKey,
    );
  }
}
