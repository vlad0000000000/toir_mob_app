import 'dart:convert';
import 'dart:math';

import 'package:hive_ce/hive.dart';
import '../../global_state.dart';

class Scan {
  final List<String>? files;
  final String? periodicTaskUuid;
  final String? equipmentUuid;
  String resultStatus;
  final String? comment;
  final String? faultUuid;
  final bool? isOtherFault;
  final String? taskUuid;
  final String? priority;
  final String? createdAt;
  final String? closedAt;

  /// Фактический расход ЗИП — уже готовая строка JSON
  /// `[{"spare_part_uuid": "...", "quantity": 2}]`, ровно в том виде, в каком
  /// её ждёт `PATCH /v1/company/fault_inspections/{uuid}` (поле формы
  /// `actual_consumptions`).
  ///
  /// Строкой, а не списком объектов: расход собирается один раз при отправке
  /// и больше не редактируется, разбирать его обратно незачем. Заодно это
  /// избавляет от новых Hive-адаптеров.
  ///
  /// Заполняется только для закрываемой периодической задачи, у которой
  /// сервер прислал `spare_part_usage`.
  final String? actualConsumptions;

  /// Названия позиций расхода — строкой JSON `{"<uuid>": "Болт 6009-40"}`.
  ///
  /// Отдельно от [actualConsumptions] и **на сервер не уходит**: тот формат
  /// принадлежит запросу, добавлять в него лишние поля нельзя. Это чисто
  /// клиентская подпись.
  ///
  /// Зачем хранить то, что есть в справочнике: экран разрешения конфликта
  /// открывается и через сутки, и без связи, а позицию к тому моменту могли
  /// удалить на сервере — тогда инкрементальная синхронизация честно убирает
  /// её из каталога, и подпись брать неоткуда. Раньше в этом случае
  /// показывался голый uuid. Причём именно такой отказ («на складе 0») чаще
  /// всего и означает, что позиции больше нет.
  ///
  /// В [key] не входит: ключ обязан оставаться прежним у уже поставленных в
  /// очередь осмотров — по той же причине, что и [actualConsumptions].
  final String? consumptionNames;

  /// Причина, по которой сервер отказался принять осмотр.
  ///
  /// Отличает «сервер ответил и отказал» от «связи нет»: во втором случае
  /// осмотр просто ждёт своей очереди, в первом — повторять бессмысленно,
  /// пока обходчик что-то не изменит. Хранится по-русски, потому что
  /// показывается ему же.
  ///
  /// Не финальное: отметка ставится и снимается очередью на уже лежащей в
  /// боксе записи. В [key] не входит — ключ обязан оставаться прежним, иначе
  /// запись потеряется в боксе.
  String? lastError;

  /// Позиции, которых не хватило на складе, — строкой JSON, как их прислал
  /// сервер (`shortages` из ответа 409).
  ///
  /// Храним вместе с осмотром, а не пересчитываем: экран разрешения конфликта
  /// открывается и через сутки, и без связи, а локальный справочник ЗИП к
  /// тому моменту уже другой. `null` — отказ по другой причине.
  String? lastShortages;

  /// Постоянный идентификатор события — уходит в `Idempotency-Key` при
  /// создании осмотра (POST).
  ///
  /// Не [key]: тот не включает время, и два разных осмотра с одинаковым
  /// содержимым (тот же комментарий по тому же оборудованию назавтра) дают
  /// один ключ — сервер склеил бы их в одно событие. Этот считается один раз
  /// при создании и больше не меняется, поэтому повтор после потерянного
  /// ответа сервер узнаёт, а новый осмотр — нет.
  ///
  /// `null` у записей, поставленных в очередь до его появления: они уходят
  /// без заголовка, как раньше. В [key] и [toJson] не входит.
  final String? eventId;

  /// Ключи записей наработки ([UsageUpdate.key]), без которых этот осмотр
  /// отправлять нельзя.
  ///
  /// Заполняется у осмотра «только наработка»: его комментарий — показания, и
  /// уйди он раньше, чем сервер их примет, в истории было бы значение,
  /// которого на сервере нет (например, сервер отказал: «меньше прежнего»).
  /// Очередь держит осмотр, пока хоть одна из этих записей лежит в очереди
  /// наработки; удаление отклонённой наработки удаляет и его.
  ///
  /// `null` — ждать нечего. В [key] и [toJson] не входит.
  final List<String>? usageKeys;

  bool get isRejected => (lastError ?? '').isNotEmpty;

  /// Новый [eventId]: 128 случайных бит, hex.
  static String newEventId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// Копия с другим фактическим расходом — для экрана разрешения конфликта.
  ///
  /// Поля расхода объявлены `final`, потому что при обычной жизни осмотра они
  /// не меняются: расход собирают один раз при отправке. Исключение одно —
  /// сервер отказал по нехватке на складе, и обходчик правит количества, чтобы
  /// отправить снова. Через копию, а не через изменяемое поле: так остаётся
  /// видно, что это особый случай, а не рядовая правка.
  ///
  /// Ключ записи при этом **не меняется** — [key] расход не учитывает
  /// намеренно (см. комментарий рядом с ним), поэтому копия ложится в бокс на
  /// место оригинала, а не второй записью.
  ///
  /// Отметки об отказе переносятся как есть: снимать их — дело вызывающего,
  /// он же решает, отправлять осмотр заново или просто сохранить правку.
  Scan copyWithConsumption({
    required String? actualConsumptions,
    required String? consumptionNames,
  }) {
    return Scan(
      files: files,
      periodicTaskUuid: periodicTaskUuid,
      equipmentUuid: equipmentUuid,
      resultStatus: resultStatus,
      comment: comment,
      faultUuid: faultUuid,
      isOtherFault: isOtherFault,
      taskUuid: taskUuid,
      priority: priority,
      createdAt: createdAt,
      closedAt: closedAt,
      actualConsumptions: actualConsumptions,
      consumptionNames: consumptionNames,
      lastError: lastError,
      lastShortages: lastShortages,
      // Та же запись, то же событие: повтор с новым ключом сервер принял бы
      // за новый осмотр.
      eventId: eventId,
      usageKeys: usageKeys,
    );
  }

  String key() {
    return GlobalState.digest(jsonEncode({
      'files': files,
      'periodic_task_uuid': periodicTaskUuid,
      'equipment_uuid': equipmentUuid,
      'result_status': resultStatus,
      'comment': comment,
      'fault_uuid': faultUuid,
      'task_uuid': taskUuid,
      'priority': priority,
    }));
  }
  // Расход ЗИП в ключ намеренно не входит. Ключ — это идентификатор записи в
  // боксе, и он обязан оставаться прежним у уже поставленных в очередь
  // осмотров: иначе после обновления приложения `scanBox.delete(scan.key())`
  // не нашёл бы старую запись, и осмотр отправлялся бы бесконечно.
  // Схлопывания это не создаёт: `task_uuid` в ключе уже уникален для
  // закрываемой задачи, а у осмотра без задачи расхода не бывает.

  @override
  String toString() {
    return "Scan(resultStatus: $resultStatus, equipmentUuid: $equipmentUuid)";
  }

  Scan(
      {this.files,
      this.periodicTaskUuid,
      this.equipmentUuid,
      required this.resultStatus,
      this.comment,
      this.faultUuid,
      this.isOtherFault,
      this.taskUuid,
      this.priority,
      this.createdAt,
      this.closedAt,
      this.actualConsumptions,
      this.consumptionNames,
      this.lastError,
      this.lastShortages,
      this.eventId,
      this.usageKeys});

  Map<String, dynamic> toJson() {
    var result = <String, dynamic>{
      'files': files,
      'periodic_task_uuid': periodicTaskUuid,
      'equipment_uuid': equipmentUuid,
      'result_status': resultStatus,
      'comment': comment,
      'fault_uuid': faultUuid,
      'task_uuid': taskUuid,
      'priority': priority,
      'app_created_at': createdAt,
      'app_closed_at': closedAt,
      // Пустую строку отправлять нельзя: сервер разбирает поле как JSON и
      // на пустом значении ответил бы 422. `sendScan` пустые и так отсеивает.
      'actual_consumptions': actualConsumptions,
    };
    if (isOtherFault == true) {
      result['is_other_fault'] = 'true';
    }
    return result;
  }
}

class ScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2;

  @override
  Scan read(BinaryReader reader) {
    var files = reader.read().cast<String>();
    var periodicTaskUuid = reader.read();
    var equipmentUuid = reader.read();
    var resultStatus = reader.read();
    var comment = reader.read();
    var faultUuid = reader.read();
    var taskUuid = reader.read();
    var priority = reader.read();
    var createdAt = reader.read();
    var closedAt = reader.read();
    bool? isOtherFault;
    try {
      isOtherFault = reader.read();
    } catch (_) {
      isOtherFault = null; // старые записи без поля is_other_fault
    }
    String? actualConsumptions;
    try {
      actualConsumptions = reader.read() as String?;
    } catch (_) {
      actualConsumptions = null; // записи до появления расхода ЗИП
    }
    String? lastError;
    try {
      lastError = reader.read() as String?;
    } catch (_) {
      lastError = null; // записи до появления отметки об отказе
    }
    String? lastShortages;
    try {
      lastShortages = reader.read() as String?;
    } catch (_) {
      lastShortages = null; // записи до появления серверных данных о нехватке
    }
    String? consumptionNames;
    try {
      consumptionNames = reader.read() as String?;
    } catch (_) {
      // Записи до появления названий: подпись возьмётся из справочника, а не
      // найдётся — останется прежний запасной путь.
      consumptionNames = null;
    }
    String? eventId;
    try {
      eventId = reader.read() as String?;
    } catch (_) {
      eventId = null; // записи до появления ключа события — уйдут без него
    }
    List<String>? usageKeys;
    try {
      usageKeys = (reader.read() as List?)?.cast<String>();
    } catch (_) {
      usageKeys = null; // записи до появления связи с наработкой — не ждут
    }
    return Scan(
      files: files,
      periodicTaskUuid: periodicTaskUuid,
      equipmentUuid: equipmentUuid,
      resultStatus: resultStatus,
      comment: comment,
      faultUuid: faultUuid,
      taskUuid: taskUuid,
      priority: priority,
      createdAt: createdAt,
      closedAt: closedAt,
      isOtherFault: isOtherFault,
      actualConsumptions: actualConsumptions,
      consumptionNames: consumptionNames,
      lastError: lastError,
      lastShortages: lastShortages,
      eventId: eventId,
      usageKeys: usageKeys,
    );
  }

  @override
  void write(BinaryWriter writer, Scan obj) {
    writer.write(obj.files);
    writer.write(obj.periodicTaskUuid);
    writer.write(obj.equipmentUuid);
    writer.write(obj.resultStatus);
    writer.write(obj.comment);
    writer.write(obj.faultUuid);
    writer.write(obj.taskUuid);
    writer.write(obj.priority);
    writer.write(obj.createdAt);
    writer.write(obj.closedAt);
    writer.write(obj.isOtherFault);
    // Новые поля — строго в конец и в этом порядке: read() читает их так же.
    writer.write(obj.actualConsumptions);
    writer.write(obj.lastError);
    writer.write(obj.lastShortages);
    writer.write(obj.consumptionNames);
    writer.write(obj.eventId);
    writer.write(obj.usageKeys);
  }
}
