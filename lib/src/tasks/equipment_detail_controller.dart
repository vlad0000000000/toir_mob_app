import 'package:flutter/material.dart';
import '../../global_state.dart';
import '../../src/model/task.dart';

// Контроллер для управления выбором задач. По умолчанию — single-select
// (radio) под multi-select API. Если у компании включена настройка
// allow_multiple_tasks_per_qr_scan, разрешается выбирать несколько задач.
class EquipmentDetailController {
  final ValueNotifier<List<Task>> _valueNotifier = ValueNotifier([]);

  ValueNotifier<List<Task>> get valueNotifier => _valueNotifier;

  List<Task> get value => _valueNotifier.value;

  set value(List<Task> newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }

  final Set<Task> selectedTasks = {};
  VoidCallback? onSelectionChanged;

  EquipmentDetailController({this.onSelectionChanged});

  /// Разрешён ли выбор нескольких задач одновременно — управляется
  /// настройкой компании `allow_multiple_tasks_per_qr_scan`.
  bool get allowMultiSelect =>
      GlobalState.dataProvider.company?.allowMultipleTasksPerQrScan ?? false;

  void toggleTaskSelection(Task task) {
    if (selectedTasks.contains(task)) {
      selectedTasks.remove(task);
    } else if (allowMultiSelect) {
      selectedTasks.add(task);
    } else {
      selectedTasks
        ..clear()
        ..add(task);
    }
    onSelectionChanged?.call();
    value = selectedTasks.toList();
  }

  void selectAll(List<Task> allTasks) {
    selectedTasks.clear();
    if (allTasks.isNotEmpty) {
      selectedTasks.add(allTasks.first);
      value = [allTasks.first];
    } else {
      value = [];
    }
    onSelectionChanged?.call();
  }

  void clearSelection() {
    selectedTasks.clear();
    value = [];
    onSelectionChanged?.call();
  }

  List<Task> getSelectedTasks() {
    return selectedTasks.toList();
  }
}
