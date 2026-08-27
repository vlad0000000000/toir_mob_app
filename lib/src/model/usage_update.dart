import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class UsageUpdate {
  final String? usageParameterUuid;
  final double? usageParameterValue;
  final String? equipmentUuid;

  /// Причина, по которой сервер отказался принять наработку.
  ///
  /// До её появления у этой очереди не было понятия отказа вовсе: любая
  /// ошибка возвращала запись обратно в бокс, и отказ по существу (значение
  /// меньше предыдущего, параметр удалили, отозвали права) означал вечный
  /// цикл раз в пять секунд. Хуже того, осмотр задачи ТО намеренно ждёт, пока
  /// уедет наработка по тому же оборудованию, — и вместе с ним навсегда
  /// зависало закрытие ТО и списание ЗИП, ничем себя не проявляя.
  ///
  /// Хранится по-русски: показывается обходчику. Не финальное — пометка
  /// ставится и снимается очередью на уже лежащей в боксе записи.
  ///
  /// В [key] и [toJson] **не входит**: ключ обязан остаться прежним у уже
  /// поставленных в очередь записей, иначе после обновления приложения
  /// `scanUsageBox.delete(scan.key())` не нашёл бы старую. А `toJson` — это
  /// формат ключа, а не тела запроса (тело собирает `updateUsageParameter`).
  String? lastError;

  bool get isRejected => (lastError ?? '').isNotEmpty;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  @override
  String toString() {
    return "Scan(usageParameterUuid: $usageParameterUuid, usageParameterValue: $usageParameterValue, equipmentUuid: $equipmentUuid)";
  }

  UsageUpdate({
    this.usageParameterUuid,
    this.usageParameterValue,
    this.equipmentUuid,
    this.lastError,
  });

  Map<String, dynamic> toJson() {
    return {
      'usage_parameter_uuid': usageParameterUuid,
      'usage_parameter_value': usageParameterValue,
      'equipment_uuid': equipmentUuid,
    };
  }
}

class UsageUpdateAdapter extends TypeAdapter<UsageUpdate> {
  @override
  final int typeId = 14;

  @override
  UsageUpdate read(BinaryReader reader) {
    // Поля читаем по одному, а не прямо в аргументах конструктора: порядок
    // вычисления именованных аргументов в Dart совпадает с порядком записи,
    // но полагаться на это в формате хранения не стоит. Так же написан
    // `SparePartAdapter`.
    final usageParameterUuid = reader.read();
    final usageParameterValue = reader.read();
    final equipmentUuid = reader.read();
    String? lastError;
    try {
      lastError = reader.read() as String?;
    } catch (_) {
      // Записи, сохранённые до появления пометки об отказе: в потоке поля
      // нет, чтение упирается в конец записи. Такая наработка считается
      // неотклонённой и уйдёт обычным порядком.
      lastError = null;
    }
    return UsageUpdate(
      usageParameterUuid: usageParameterUuid,
      usageParameterValue: usageParameterValue,
      equipmentUuid: equipmentUuid,
      lastError: lastError,
    );
  }

  @override
  void write(BinaryWriter writer, UsageUpdate obj) {
    writer.write(obj.usageParameterUuid);
    writer.write(obj.usageParameterValue);
    writer.write(obj.equipmentUuid);
    // Новое поле — строго в конец: read() читает его так же, через try/catch.
    writer.write(obj.lastError);
  }
}
