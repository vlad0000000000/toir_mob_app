import 'package:flutter/material.dart';
import 'package:my_app/src/utils/any_controller.dart';
import '../../global_state.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/usage_unit.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/square_button.dart';
import 'package:flutter/services.dart';

class UsageController {
  final ValueNotifier<List<UsageParameter>> _valueNotifier = ValueNotifier([]);

  ValueNotifier<List<UsageParameter>> get valueNotifier => _valueNotifier;

  List<UsageParameter> get value => _valueNotifier.value;

  set value(List<UsageParameter> newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }

  final Set<UsageParameter> selectedTasks = {};
  VoidCallback? onSelectionChanged;

  UsageController({this.onSelectionChanged});

  void toggleTaskSelection(UsageParameter task) {
    if (selectedTasks.contains(task)) {
      selectedTasks.remove(task);
    } else {
      selectedTasks.add(task);
    }
    onSelectionChanged?.call();
    value = selectedTasks.toList();
  }

  void selectAll(List<UsageParameter> allTasks) {
    selectedTasks.addAll(allTasks);
    value = allTasks;
    onSelectionChanged?.call();
  }

  void clearSelection() {
    selectedTasks.clear();
    value = [];
    onSelectionChanged?.call();
  }

  List<UsageParameter> getSelectedTasks() {
    return selectedTasks.toList();
  }
}

class SelectUsageButton extends StatefulWidget {
  final UsageController controller;
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
    int selectedUsageCount = widget.controller.value?.length ?? 0;

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
  final UsageController controller;

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
    }
  }

  @override
  void dispose() {
    usageControllers.forEach((key, value) => value.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  .where((element) => element.value == usageParameter.unitType)
                  .toList()[0];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  title: Text(usageUnit.displayName),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Текущее значение: ${usageParameter.currentValue}'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: controller,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Значение не может быть пустым';
                              }
                              double v = 0;
                              try {
                                double.parse(value);
                              } catch (e) {
                                return 'Значение должно быть числом';
                              }
                              if (v < usageParameter.currentValue) {
                                return 'Значение должно быть больше текущего';
                              }
                              return null;
                            },
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                              labelText:
                                  'Новое значение ${usageUnit.shortName}',
                              border: const OutlineInputBorder(),
                            ),
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
          child: SquareButton(
            onPressed: () {
              List<UsageParameter> newValues = [];
              widget.machine.usageParameters.forEach(
                (element) {
                  var controller = usageControllers[element.unitType];
                  if (controller != null &&
                      controller.text.isNotEmpty &&
                      controller.text != element.currentValue) {
                    newValues.add(UsageParameter(
                        id: element.id,
                        uuid: element.uuid,
                        unitType: element.unitType,
                        currentValue: double.parse(controller.text),
                        prohibitDecrease: element.prohibitDecrease,
                        createMaintenanceTasks: element.createMaintenanceTasks,
                        lastMaintenanceValue: element.lastMaintenanceValue,
                        maintenanceInterval: element.maintenanceInterval,
                        nextMaintenanceValue: element.nextMaintenanceValue));
                  }
                },
              );
              widget.controller.value = newValues;
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}
