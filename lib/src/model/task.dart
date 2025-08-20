import 'package:hive_ce/hive.dart';

class Task {
  final int id;
  final int start;
  final int end;
  final bool isCompleted;
  final String? node;
  final String operation;
  final String? material;
  final String? quantity;
  final String? category;
  final String? periodName;
  final int role;
  final int machineId;

  Task({
    required this.id,
    required this.start,
    required this.end,
    required this.isCompleted,
    this.node,
    required this.operation,
    this.material,
    this.quantity,
    this.category,
    this.periodName,
    required this.role,
    required this.machineId,
  });

  // Фабричный конструктор из JSON
  factory Task.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'start': int start,
        'end': int end,
        'is_completed': bool isCompleted,
        'operation': String operation,
        'role': int role,
        'machine_id': int machineId,
        'node': String? node,
        'material': String? material,
        'quantity': String? quantity,
        'category': String? category,
        'period_name': String? periodName,
      } =>
        Task(
          id: id,
          start: start,
          end: end,
          isCompleted: isCompleted,
          node: node,
          operation: operation,
          material: material,
          quantity: quantity,
          category: category,
          periodName: periodName,
          role: role,
          machineId: machineId,
        ),
      _ => throw const FormatException('Failed to load task.'),
    };
  }

  // Метод для преобразования в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'start': start,
      'end': end,
      'is_completed': isCompleted,
      'node': node,
      'operation': operation,
      'material': material,
      'quantity': quantity,
      'category': category,
      'period_name': periodName,
      'role': role,
      'machine_id': machineId,
    };
  }
}

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 3;

  @override
  Task read(BinaryReader reader) {
    return Task(
      id: reader.read(),
      start: reader.read(),
      end: reader.read(),
      isCompleted: reader.read(),
      node: reader.read(),
      operation: reader.read(),
      material: reader.read(),
      quantity: reader.read(),
      category: reader.read(),
      periodName: reader.read(),
      role: reader.read(),
      machineId: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer.write(obj.id);
    writer.write(obj.start);
    writer.write(obj.end);
    writer.write(obj.isCompleted);
    writer.write(obj.node);
    writer.write(obj.operation);
    writer.write(obj.material);
    writer.write(obj.quantity);
    writer.write(obj.category);
    writer.write(obj.periodName);
    writer.write(obj.role);
    writer.write(obj.machineId);
  }
}
