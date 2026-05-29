import 'package:flutter/material.dart';
import '../../src/model/task.dart';

// Контроллер для управления выбором задач (single-select под multi-select API).
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

  void toggleTaskSelection(Task task) {
    if (selectedTasks.contains(task)) {
      selectedTasks.clear();
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
