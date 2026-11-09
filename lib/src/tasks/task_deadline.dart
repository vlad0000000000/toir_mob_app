import 'package:flutter/material.dart';

import '../../strings.dart';
import '../model/task.dart';
import '../notifications/notification_formatters.dart';

/// Подпись срока в строке задачи: «Срок: …» или «Просрочено, срок …».
/// `null` — подписывать нечего: срока нет или это доработка
/// ([Task.isOverdueAt]).
String? taskDeadlineText(Task task, DateTime now) {
  final deadline = task.deadlineAt;
  if (deadline == null || task.isReturnedForRework) return null;
  final date = NotificationFormatters.formatDateTime(deadline);
  return task.isOverdueAt(now)
      ? TaskDeadlineStrings.overdue(date)
      : TaskDeadlineStrings.due(date);
}

/// Значение строки «Срок» в карточке задачи: дата, у просроченной — с
/// пометкой. `null` — по тем же правилам, что и [taskDeadlineText].
String? taskDeadlineValue(Task task, DateTime now) {
  final deadline = task.deadlineAt;
  if (deadline == null || task.isReturnedForRework) return null;
  final date = NotificationFormatters.formatDateTime(deadline);
  return task.isOverdueAt(now) ? TaskDeadlineStrings.overdueValue(date) : date;
}

/// Порядок задач внутри группы: сначала самый ранний срок, задачи без срока —
/// после них. Экземпляров одной задачи бывает несколько (сервер их сам не
/// закрывает), и самый старый не должен потеряться в конце списка. При равном
/// сроке — по uuid, чтобы строки не менялись местами между перестроениями.
int compareTasksByDeadline(Task a, Task b) {
  final left = a.deadlineAt;
  final right = b.deadlineAt;
  if (left != null && right != null) {
    final byDeadline = left.compareTo(right);
    if (byDeadline != 0) return byDeadline;
  } else if (left != null) {
    return -1;
  } else if (right != null) {
    return 1;
  }
  return a.uuid.compareTo(b.uuid);
}

/// Строка срока под названием задачи: у просроченной — красным и жирным.
/// Общая для задач оборудования и списка ППР.
///
/// Срок живёт в карточке задачи (замечание 14, 09.11.2026), в списке строка
/// остаётся только у задачи без карточки — без шаблона кнопки «i» нет, и
/// иначе срок не было бы видно нигде.
class TaskDeadlineLine extends StatelessWidget {
  final Task task;

  const TaskDeadlineLine({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = taskDeadlineText(task, now);
    if (text == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final overdue = task.isOverdueAt(now);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: tt.bodySmall?.copyWith(
          color: overdue ? cs.error : cs.onSurfaceVariant,
          fontWeight: overdue ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
