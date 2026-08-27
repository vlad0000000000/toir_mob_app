import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../global_state.dart';
import 'repair.dart';

/// Черновик ремонта — созданный обходчиком, но ещё не принятый сервером.
///
/// Живёт в отдельном боксе `pending_repairs` и уезжает очередью, как осмотры
/// и наработки. Отличие одно, и оно важное: у ремонта есть побочный эффект —
/// сервер переводит оборудование в состояние «В ремонте» и рассылает
/// уведомления. Поэтому повтор отправки обязан быть безопасным, и ключ
/// [localId] уходит в заголовок `Idempotency-Key`: сервер помнит пару
/// «компания + ключ» и на повтор возвращает тот же ремонт с кодом 200 вместо
/// создания второго.
class PendingRepair {
  /// Ключ бокса и он же `Idempotency-Key`. Считается один раз при создании
  /// черновика и больше не меняется — иначе повтор превратился бы в новый
  /// ремонт.
  final String localId;

  final String equipmentUuid;

  /// Название оборудования — только для списка черновиков. Сервер его не
  /// принимает: в запросе уходит один `equipment_uuid`.
  final String equipmentName;

  final String? consumptionNormUuid;
  final String? consumptionNormName;
  final DateTime startedAt;
  final String comment;

  /// Когда черновик лёг в очередь. Показывается в списке и участвует в
  /// [localId], чтобы два одинаковых по содержанию ремонта не слиплись в один.
  final DateTime createdAt;

  /// Сколько раз очередь пыталась отправить. Растёт только на настоящих
  /// отказах: когда связи нет, попытки не считаем.
  final int attempts;

  /// Причина последнего отказа сервера, уже по-русски. Пусто — черновик просто
  /// ждёт связи.
  final String? lastError;

  /// Ремонт, из-за которого черновик отклонили: сервер отвечает «Equipment is
  /// already in repair», а какой именно ремонт занял оборудование —
  /// доискивается очередью. Нужен экрану разрешения конфликта, чтобы показать
  /// «Существующий ремонт №N» и предложить перенос.
  final String? conflictRepairUuid;

  /// Фактический расход, введённый до отправки. Заполняется в карточке
  /// черновика — она открывается и без связи (п. 4.5.1) — и целиком уходит в
  /// существующий ремонт при разрешении конфликта.
  final List<RepairConsumption> consumptions;

  /// Ремонт уже создан на сервере, но черновик ещё не доделан — остались
  /// неотправленные снимки. Отправка возобновляется с этого места, повторно
  /// создавать ремонт не нужно.
  final String? serverUuid;

  /// Пути к файлам снимков, ждущих загрузки. Путь исчезает отсюда сразу после
  /// того, как **этот** файл принят сервером: загрузка фотографий не
  /// идемпотентна, и повтор после частичной отправки иначе продублировал бы
  /// уже принятые снимки.
  final List<String> photoPaths;

  /// Обходчик нажал «Отправить на рассмотрение» ещё до того, как ремонт уехал.
  /// Очередь отработает это последним шагом: создание → фото → перевод в
  /// «На рассмотрении» (п. 4.5.4 отчёта).
  final bool submitForReview;

  /// Состав нормы, выбранной при создании. Нужен только карточке черновика —
  /// без него не показать плановые количества и не заполнить расход из нормы,
  /// пока сервер о ремонте не знает.
  final List<RepairNormItem> normItems;

  PendingRepair({
    required this.localId,
    required this.equipmentUuid,
    required this.equipmentName,
    required this.startedAt,
    required this.createdAt,
    this.consumptionNormUuid,
    this.consumptionNormName,
    this.comment = '',
    this.attempts = 0,
    this.lastError,
    this.conflictRepairUuid,
    this.consumptions = const [],
    this.serverUuid,
    this.photoPaths = const [],
    this.submitForReview = false,
    this.normItems = const [],
  });

  /// Новый черновик: ключ идемпотентности выводим из содержимого плюс момента
  /// создания. Тот же приём, что у `Scan.key()`, — двойное нажатие «Создать»
  /// с теми же данными даст один ключ и, значит, один ремонт.
  factory PendingRepair.create({
    required String equipmentUuid,
    required String equipmentName,
    required DateTime startedAt,
    String? consumptionNormUuid,
    String? consumptionNormName,
    String comment = '',
    List<RepairNormItem> normItems = const [],
  }) {
    final createdAt = DateTime.now();
    final localId = GlobalState.digest(jsonEncode({
      'equipment_uuid': equipmentUuid,
      'started_at': startedAt.toUtc().toIso8601String(),
      'consumption_norm_uuid': consumptionNormUuid,
      'comment': comment,
      'created_at': createdAt.millisecondsSinceEpoch,
    }));
    return PendingRepair(
      localId: localId,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      startedAt: startedAt,
      createdAt: createdAt,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      comment: comment,
      normItems: normItems,
    );
  }

  /// Отказ был окончательным (сервер ответил, но отказал), а не «нет связи».
  bool get isRejected => lastError != null && lastError!.isNotEmpty;

  /// Черновик в виде [Repair] — чтобы карточка ремонта работала по нему без
  /// второй, почти такой же реализации.
  ///
  /// `id` нулевой, `uuid` пустой: серверной записи ещё нет, и подделывать её
  /// нельзя. Карточка по этим признакам понимает, что перед ней черновик, —
  /// вместо «Ремонт №128» показывает «Черновик» и сохраняет не на сервер, а
  /// обратно в очередь.
  Repair toRepair({String? responsibleUuid, String? responsibleName}) {
    return Repair(
      id: 0,
      uuid: '',
      status: RepairStatuses.open,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      createdAt: createdAt,
      startedAt: startedAt,
      comment: comment,
      responsibleUserUuid: responsibleUuid,
      responsibleUserFullname: responsibleName,
      actualConsumptions: consumptions,
      normItems: normItems,
    );
  }

  /// Обычная правка черновика. Пометку об отказе **не трогает**: менять её
  /// умеют только [markRejected] и [clearRejection].
  ///
  /// Раньше `lastError` и `conflictRepairUuid` были параметрами этого метода
  /// и сбрасывались, если их не передали. Прочитать это по месту вызова было
  /// невозможно: `draft.copyWith(photoPaths: …)` выглядит как «добавили
  /// снимок», а на деле снимал отказ, и очередь тут же отправляла черновик
  /// заново — получая тот же отказ. Теперь каждый переход назван.
  PendingRepair copyWith({
    int? attempts,
    String? serverUuid,
    List<String>? photoPaths,
    String? comment,
    List<RepairConsumption>? consumptions,
    bool? submitForReview,
  }) {
    return PendingRepair(
      localId: localId,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      startedAt: startedAt,
      createdAt: createdAt,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      comment: comment ?? this.comment,
      consumptions: consumptions ?? this.consumptions,
      attempts: attempts ?? this.attempts,
      lastError: lastError,
      conflictRepairUuid: conflictRepairUuid,
      serverUuid: serverUuid ?? this.serverUuid,
      photoPaths: photoPaths ?? this.photoPaths,
      submitForReview: submitForReview ?? this.submitForReview,
      normItems: normItems,
    );
  }

  /// Сервер ответил и отказал. Причина — по-русски, [conflictRepairUuid] —
  /// ремонт, занявший оборудование, если его удалось найти (иначе `null`,
  /// и прежнее значение сюда тянуть нельзя: оно от другого отказа).
  PendingRepair markRejected({
    required String reason,
    String? conflictRepairUuid,
  }) {
    return PendingRepair(
      localId: localId,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      startedAt: startedAt,
      createdAt: createdAt,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      comment: comment,
      consumptions: consumptions,
      attempts: attempts + 1,
      lastError: reason,
      conflictRepairUuid: conflictRepairUuid,
      serverUuid: serverUuid,
      photoPaths: photoPaths,
      submitForReview: submitForReview,
      normItems: normItems,
    );
  }

  /// Черновик снова готов к отправке: обходчик нажал «Повторить» или изменил
  /// форму. Очередь берёт в работу только черновики без пометки.
  PendingRepair clearRejection() {
    return PendingRepair(
      localId: localId,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      startedAt: startedAt,
      createdAt: createdAt,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      comment: comment,
      consumptions: consumptions,
      attempts: attempts,
      lastError: null,
      conflictRepairUuid: null,
      serverUuid: serverUuid,
      photoPaths: photoPaths,
      submitForReview: submitForReview,
      normItems: normItems,
    );
  }
}

/// Адаптер написан руками, как и все в проекте: порядок чтения обязан
/// совпадать с порядком записи, новые поля — только в конец через try/catch.
class PendingRepairAdapter extends TypeAdapter<PendingRepair> {
  @override
  final int typeId = 27;

  @override
  PendingRepair read(BinaryReader reader) {
    // Поля читаем по одному, а не прямо в аргументах конструктора: порядок
    // вычисления именованных аргументов в Dart совпадает с порядком записи,
    // но полагаться на это в формате хранения не стоит. Так же написан
    // `SparePartAdapter`.
    final localId = reader.read();
    final equipmentUuid = reader.read();
    final equipmentName = reader.read();
    final consumptionNormUuid = reader.read();
    final consumptionNormName = reader.read();
    final startedAt = reader.read();
    final comment = reader.read();
    final createdAt = reader.read();
    final attempts = reader.read();
    final lastError = reader.read();
    // Дальше — поля, дописанные в конец после первого выпуска. Их порядок
    // тоже обязан совпадать с порядком записи: первое же чтение за концом
    // записи гасит все следующие.
    final conflictRepairUuid = _readTrailing<String>(reader);
    final consumptions =
        _readTrailing<List<dynamic>>(reader)?.cast<RepairConsumption>() ??
            const <RepairConsumption>[];
    final serverUuid = _readTrailing<String>(reader);
    final photoPaths =
        _readTrailing<List<dynamic>>(reader)?.cast<String>() ?? const <String>[];
    final submitForReview = _readTrailing<bool>(reader) ?? false;
    final normItems =
        _readTrailing<List<dynamic>>(reader)?.cast<RepairNormItem>() ??
            const <RepairNormItem>[];
    return PendingRepair(
      localId: localId,
      equipmentUuid: equipmentUuid,
      equipmentName: equipmentName,
      consumptionNormUuid: consumptionNormUuid,
      consumptionNormName: consumptionNormName,
      startedAt: startedAt,
      comment: comment,
      createdAt: createdAt,
      attempts: attempts,
      lastError: lastError,
      conflictRepairUuid: conflictRepairUuid,
      consumptions: consumptions,
      serverUuid: serverUuid,
      photoPaths: photoPaths,
      submitForReview: submitForReview,
      normItems: normItems,
    );
  }

  /// Поля, добавленные после первого выпуска: у черновиков, сохранённых
  /// прежней версией, их в потоке нет.
  static T? _readTrailing<T>(BinaryReader reader) {
    try {
      return reader.read() as T?;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(BinaryWriter writer, PendingRepair obj) {
    writer.write(obj.localId);
    writer.write(obj.equipmentUuid);
    writer.write(obj.equipmentName);
    writer.write(obj.consumptionNormUuid);
    writer.write(obj.consumptionNormName);
    // DateTime Hive умеет сам — так же написан адаптер Repair рядом.
    writer.write(obj.startedAt);
    writer.write(obj.comment);
    writer.write(obj.createdAt);
    writer.write(obj.attempts);
    writer.write(obj.lastError);
    writer.write(obj.conflictRepairUuid);
    writer.write(obj.consumptions);
    writer.write(obj.serverUuid);
    writer.write(obj.photoPaths);
    writer.write(obj.submitForReview);
    writer.write(obj.normItems);
  }
}
