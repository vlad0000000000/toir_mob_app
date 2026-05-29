import 'package:flutter/material.dart';
import '../model/task.dart';

enum TasksDateRange { all, today, yesterday, week, month, custom }

const Map<String, String> tasksStatusLabels = {
  'open': 'Открыта',
  'scheduled': 'Запланирована',
  'closed': 'Закрыта',
};

const Map<String, String> tasksPriorityLabels = {
  'low': 'Низкий',
  'medium': 'Средний',
  'high': 'Высокий',
};

class TasksFilterState {
  Set<String> statuses;
  String? equipmentUuid;
  String? priority;
  TasksDateRange dateRange;
  DateTimeRange? customRange;

  TasksFilterState({
    Set<String>? statuses,
    this.equipmentUuid,
    this.priority,
    this.dateRange = TasksDateRange.all,
    this.customRange,
  }) : statuses = statuses ?? <String>{};

  TasksFilterState clone() => TasksFilterState(
        statuses: {...statuses},
        equipmentUuid: equipmentUuid,
        priority: priority,
        dateRange: dateRange,
        customRange: customRange,
      );

  int get activeCount {
    int c = 0;
    if (statuses.isNotEmpty) c++;
    if (equipmentUuid != null) c++;
    if (priority != null) c++;
    if (dateRange != TasksDateRange.all) c++;
    return c;
  }

  bool get isEmpty => activeCount == 0;

  /// Применяет фильтр к локальному списку задач (только те, которые есть).
  List<Task> apply(List<Task> tasks) {
    DateTime? from;
    DateTime? to;
    final now = DateTime.now();
    switch (dateRange) {
      case TasksDateRange.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case TasksDateRange.yesterday:
        from = DateTime(now.year, now.month, now.day - 1);
        to = DateTime(now.year, now.month, now.day);
        break;
      case TasksDateRange.week:
        from = now.subtract(const Duration(days: 7));
        break;
      case TasksDateRange.month:
        from = now.subtract(const Duration(days: 30));
        break;
      case TasksDateRange.custom:
        if (customRange != null) {
          from = customRange!.start;
          to = customRange!.end;
        }
        break;
      case TasksDateRange.all:
        break;
    }

    return tasks.where((t) {
      if (statuses.isNotEmpty && !statuses.contains(t.resultStatus)) {
        return false;
      }
      if (equipmentUuid != null && t.equipmentUuid != equipmentUuid) {
        return false;
      }
      // У Task нет own priority. Если когда-нибудь появится — фильтровать тут.
      if (priority != null) {
        return false;
      }
      if (from != null || to != null) {
        final createdAt = t.periodicTask?.createdAt;
        if (createdAt == null) return false;
        if (from != null && createdAt.isBefore(from)) return false;
        if (to != null && createdAt.isAfter(to)) return false;
      }
      return true;
    }).toList();
  }
}
