import 'package:flutter/material.dart';
import '../../src/model/usage_update.dart';
import '../../src/utils/any_controller.dart';
import '../../global_state.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/usage_unit.dart';
import '../../src/widgets/square_button.dart';

import 'app_bottom_sheet.dart';
import 'controller_listener_mixin.dart';

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

class _SelectUsageButtonState extends State<SelectUsageButton>
    with ControllerListenerMixin {
  @override
  Listenable get controllerListenable => widget.controller.valueNotifier;

  @override
  Widget build(BuildContext context) {
    // Проверяем наличие параметров с соответствующей ролью
    final currentUserRole = GlobalState.authUser?.effectiveRole;
    final hasMatchingParameters = widget.machine.usageParameters.any(
      (param) => param.maintenanceRole?.name == currentUserRole,
    );
    
    // Если нет подходящих параметров, не показываем кнопку
    if (!hasMatchingParameters) {
      return const SizedBox.shrink();
    }
    
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
          showAppModalSheet(
            context,
            child: UsageSelectionModal(
              machine: widget.machine,
              controller: widget.controller,
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
  final formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final currentUserRole = GlobalState.authUser?.effectiveRole;
    // Фильтруем параметры по роли пользователя
    final matchingParameters = widget.machine.usageParameters.where(
      (param) => param.maintenanceRole?.name == currentUserRole,
    );
    
    for (var unit in matchingParameters) {
      usageControllers[unit.unitType] = TextEditingController();
      usageControllers[unit.unitType]!.text =
          unit.currentValue.toString(); // Display current value
      if (widget.controller.value != null &&
          widget.controller.value!.length > 0) {
        var selected = widget.controller.value!
            .where((element) => element.usageParameterUuid == unit.uuid);
        if (selected.length > 0) {
          usageControllers[unit.unitType]!.text =
              selected.first.usageParameterValue.toString();
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
    final currentUserRole = GlobalState.authUser?.effectiveRole;
    // Фильтруем параметры по роли пользователя
    final matchingParameters = widget.machine.usageParameters.where(
      (param) => param.maintenanceRole?.name == currentUserRole,
    ).toList();

    final tt = Theme.of(context).textTheme;
    return Form(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'НАРАБОТКА',
                  style: tt.labelSmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.machine.name,
                  style:
                      tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: matchingParameters.length,
              itemBuilder: (context, index) {
                final usageParameter = matchingParameters[index];
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
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      usageUnit.displayName,
                      style: tt.titleMedium,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Текущее значение: ${usageParameter.currentValue}'),
                            // Text(
                            //     'Следующее ТО: ${usageParameter.nextMaintenanceValue}'),
                            const SizedBox(height: 16),
                            TextFormField(
                              onChanged: (value) {
                                formKey.currentState!.validate();
                              },
                              controller: controller,
                              validator: (value) {
                                return usageParameter.validate(value,
                                    allowCurrentValue: true);
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
                                  hoverColor: Theme.of(context).colorScheme.surface,
                                  fillColor: Theme.of(context).colorScheme.surface),
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
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final currentUserRole = GlobalState.authUser?.effectiveRole;
                  final matchingParameters =
                      widget.machine.usageParameters.where(
                    (param) => param.maintenanceRole?.name == currentUserRole,
                  );
                  List<UsageUpdate> newValues = [];
                  for (var element in matchingParameters) {
                    var controller = usageControllers[element.unitType];
                    if (controller != null &&
                        element.validate(controller.text) == null) {
                      newValues.add(UsageUpdate(
                          equipmentUuid: widget.machine.uuid,
                          usageParameterUuid: element.uuid,
                          usageParameterValue: double.parse(controller.text)));
                    }
                  }
                  widget.controller.value = newValues;
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Сохранить'),
              ),
            ),
          ),
        ],
      ),
      key: formKey,
    );
  }
}
