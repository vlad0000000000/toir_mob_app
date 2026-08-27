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

  /// Оставить выбранной одну задачу — первую из списка.
  ///
  /// Раньше метод назывался `selectAll`, хотя всех никогда не выбирал: он
  /// сбрасывает выбор и берёт `tasks.first`. Пока выбор был только одиночным,
  /// расхождение было безобидным, но с появлением `allowMultiSelect` имя стало
  /// прямой ловушкой — вызвавший «выбрать все» молча потерял бы остальные
  /// задачи. Вызовов нет ни одного; метод оставлен как часть multi-select API
  /// контроллера.
  void selectFirst(List<Task> tasks) {
    selectedTasks.clear();
    if (tasks.isNotEmpty) {
      selectedTasks.add(tasks.first);
      value = [tasks.first];
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
