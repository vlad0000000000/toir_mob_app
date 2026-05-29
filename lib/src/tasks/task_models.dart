import '../../src/model/inventory_record.dart';
import '../../src/model/task.dart';

class Equipment {
  final List<Checklist> checklists;
  final InventoryRecord machine;

  Equipment(this.machine, this.checklists);
}

class Checklist {
  final String period;
  final List<Task> tasks;
  bool isExpanded;

  Checklist(this.period, this.tasks, {this.isExpanded = false});
}
