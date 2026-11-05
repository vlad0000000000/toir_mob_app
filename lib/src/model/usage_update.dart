import 'dart:convert';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';
import 'queue_owned.dart';

/// Значение наработки до сотых — точность колонки на сервере
/// (`Numeric(15, 2)`).
double roundUsageValue(double value) => double.parse(value.toStringAsFixed(2));

/// Поле формы `usage_updates` осмотра — строка JSON
/// `[{"usage_parameter_uuid": "...", "current_value": "1250.00"}]`.
///
/// Значение — строкой с двумя знаками, а не числом: `jsonEncode` от `double`
/// дал бы `1250.1000000000001`, а сервер больше двух знаков не принимает.
/// Один параметр — одна строка (сервер отклоняет повторы uuid), берётся
/// последнее значение. Записи без значения или без параметра пропускаются.
/// `null` — отправлять нечего, поля в форме не будет.
String? usageUpdatesPayload(Iterable<UsageUpdate> updates) {
  final byParameter = <String, double>{};
  for (final update in updates) {
    final uuid = update.usageParameterUuid;
    final value = update.usageParameterValue;
    if (uuid == null || uuid.isEmpty || value == null) continue;
    byParameter[uuid] = value;
  }
  if (byParameter.isEmpty) return null;
  return jsonEncode([
    for (final entry in byParameter.entries)
      {
        'usage_parameter_uuid': entry.key,
        'current_value': entry.value.toStringAsFixed(2),
      },
  ]);
}

class UsageUpdate implements QueueOwned {
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

  /// Когда показание сняли — ISO-8601 UTC, тот же формат, что `Scan.createdAt`.
  ///
  /// Нужно для порядка. Наработка уходит двумя путями: отдельной записью
  /// этой очереди и внутри осмотра (`Scan.usageUpdates`). Две очереди
  /// разбираются независимо, и без отметки времени более старое показание
  /// могло бы уехать позже нового и откатить счётчик назад. По ней очередь
  /// держит запись, пока по тому же оборудованию не уйдёт всё более раннее.
  ///
  /// `null` у записей прошлой версии — считаются самыми ранними. В [key] и
  /// [toJson] не входит — по той же причине, что [lastError].
  final String? createdAt;

  /// Обходчик, поставивший запись в очередь, — см. [Scan.ownerUuid]. Не
  /// `final`: перенос старых записей ставит его на месте. В [key] и [toJson]
  /// не входит.
  @override
  String? ownerUuid;

  /// Сервер, на который запись должна уйти, — см. [Scan.ownerServer]. Не
  /// `final`: перенос старых записей ставит его на месте. Входит в [key].
  @override
  String? ownerServer;

  bool get isRejected => (lastError ?? '').isNotEmpty;

  String key() {
    return GlobalState.digest(jsonEncode(toJson()));
  }

  /// Ключ до привязки очередей к аккаунту — без владельца и сервера, см.
  /// [Scan.legacyKey]. По нему на старте восстанавливаются ссылки осмотров
  /// на эту наработку ([Scan.usageKeys]).
  String legacyKey() {
    return GlobalState.digest(jsonEncode(
        toJson()
          ..remove('owner_uuid')
          ..remove('owner_server')));
  }

  /// Ключ до привязки очередей к серверу — с владельцем, без сервера. Для
  /// того же переноса ссылок, что [legacyKey].
  String ownerOnlyKey() {
    return GlobalState.digest(jsonEncode(toJson()..remove('owner_server')));
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
    this.createdAt,
    this.ownerUuid,
    this.ownerServer,
  });

  Map<String, dynamic> toJson() {
    return {
      'usage_parameter_uuid': usageParameterUuid,
      'usage_parameter_value': usageParameterValue,
      'equipment_uuid': equipmentUuid,
      // Владелец — в ключе, как у [Scan.key]: одинаковое показание другого
      // обходчика не должно лечь на место этого. Только если задан.
      if (ownerUuid != null && ownerUuid!.isNotEmpty) 'owner_uuid': ownerUuid,
      // И сервер: то же показание того же обходчика для другого сервера.
      if (ownerServer != null && ownerServer!.isNotEmpty)
        'owner_server': ownerServer,
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
    String? createdAt;
    try {
      createdAt = reader.read() as String?;
    } catch (_) {
      createdAt = null; // записи до появления отметки времени — самые ранние
    }
    String? ownerUuid;
    try {
      ownerUuid = reader.read() as String?;
    } catch (_) {
      ownerUuid = null; // записи до привязки очередей к аккаунту
    }
    String? ownerServer;
    try {
      ownerServer = reader.read() as String?;
    } catch (_) {
      ownerServer = null; // записи до привязки очередей к серверу
    }
    return UsageUpdate(
      usageParameterUuid: usageParameterUuid,
      usageParameterValue: usageParameterValue,
      equipmentUuid: equipmentUuid,
      lastError: lastError,
      createdAt: createdAt,
      ownerUuid: ownerUuid,
      ownerServer: ownerServer,
    );
  }

  @override
  void write(BinaryWriter writer, UsageUpdate obj) {
    writer.write(obj.usageParameterUuid);
    writer.write(obj.usageParameterValue);
    writer.write(obj.equipmentUuid);
    // Новое поле — строго в конец: read() читает его так же, через try/catch.
    writer.write(obj.lastError);
    writer.write(obj.createdAt);
    writer.write(obj.ownerUuid);
    writer.write(obj.ownerServer);
  }
}
