import 'package:hive_ce/hive.dart';

import 'server_decimal.dart';

/// Статусы ремонта. Значения совпадают с `RepairStatus` на сервере.
class RepairStatuses {
  RepairStatuses._();

  static const String open = 'open';
  static const String underReview = 'under_review';
  static const String closed = 'closed';

  static String displayName(String status) {
    switch (status) {
      case open:
        return 'Открыт';
      case underReview:
        return 'На рассмотрении';
      case closed:
        return 'Закрыт';
    }
    return status;
  }
}

/// Ремонт оборудования.
///
/// Одна модель обслуживает и список, и карточку: `GET /v1/repairs/` отдаёт
/// урезанный `RepairListSchema` (без комментария, расхода и фото), а
/// `GET /v1/repairs/{uuid}` — полный `RepairSchema`. Поэтому [fromJson]
/// терпимо относится к отсутствующим полям, а не требует их.
///
/// Вложенные объекты сервера разложены в плоские поля «uuid + название» —
/// как в [SparePart]: экрану нужны только подписи, а плоские поля экономят
/// рукописные адаптеры и typeId.
class Repair {
  final int id;
  final String uuid;
  final String status;
  final String equipmentUuid;
  final String equipmentName;
  final String? equipmentTypeModel;
  final String? consumptionNormUuid;
  final String? consumptionNormName;
  final DateTime createdAt;
  final DateTime startedAt;
  final DateTime? underReviewAt;
  final DateTime? completedAt;

  /// Готовая строка вида «2 дн 16 ч 4 мин» — её собирает сервер, клиент
  /// ничего не пересчитывает.
  final String? duration;

  final String? comment;
  final String? responsibleUserUuid;
  final String? responsibleUserFullname;
  final String? responsibleRoleUuid;
  final String? responsibleRoleName;
  final List<RepairConsumption> actualConsumptions;
  final List<RepairPhoto> photos;

  /// Состав нормы расхода. Приходит вложенным в сам ремонт
  /// (`RepairSchema.consumption_norm.items`), поэтому «Заполнить из нормы»
  /// работает без дополнительного запроса — и в том числе без сети.
  final List<RepairNormItem> normItems;

  Repair({
    required this.id,
    required this.uuid,
    required this.status,
    required this.equipmentUuid,
    required this.equipmentName,
    this.equipmentTypeModel,
    this.consumptionNormUuid,
    this.consumptionNormName,
    required this.createdAt,
    required this.startedAt,
    this.underReviewAt,
    this.completedAt,
    this.duration,
    this.comment,
    this.responsibleUserUuid,
    this.responsibleUserFullname,
    this.responsibleRoleUuid,
    this.responsibleRoleName,
    this.actualConsumptions = const [],
    this.photos = const [],
    this.normItems = const [],
  });

  bool get isOpen => status == RepairStatuses.open;

  bool get isUnderReview => status == RepairStatuses.underReview;

  bool get isClosed => status == RepairStatuses.closed;

  /// Активный ремонт — открытый или отправленный на рассмотрение. Именно их
  /// приложение держит в офлайн-кэше; закрытые тянутся с сервера по запросу.
  bool get isActive => isOpen || isUnderReview;

  /// Ремонт назначен на должность, но исполнителя ещё нет — такой может
  /// взять в работу любой обходчик подходящей роли (этап 4).
  bool get isUnassigned =>
      (responsibleUserUuid == null || responsibleUserUuid!.isEmpty) &&
      responsibleRoleUuid != null;

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  factory Repair.fromJson(Map<String, dynamic> json) {
    final equipment = json['equipment'] as Map<String, dynamic>?;
    final norm = json['consumption_norm'] as Map<String, dynamic>?;
    final user = json['responsible_user'] as Map<String, dynamic>?;
    final role = json['responsible_role'] as Map<String, dynamic>?;
    final startedAt = _parseDate(json['started_at']);
    final createdAt = _parseDate(json['created_at']);
    return Repair(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      status: json['status'] as String,
      equipmentUuid: equipment?['uuid'] as String? ?? '',
      equipmentName: equipment?['name'] as String? ?? '',
      equipmentTypeModel: equipment?['type_model'] as String?,
      consumptionNormUuid: norm?['uuid'] as String?,
      consumptionNormName: norm?['name'] as String?,
      // Даты обязательны на сервере, но подставляем запасной вариант вместо
      // падения: одна кривая запись не должна ронять разбор всего списка.
      createdAt: createdAt ?? startedAt ?? DateTime.now().toUtc(),
      startedAt: startedAt ?? createdAt ?? DateTime.now().toUtc(),
      underReviewAt: _parseDate(json['under_review_at']),
      completedAt: _parseDate(json['completed_at']),
      duration: json['duration'] as String?,
      comment: json['comment'] as String?,
      responsibleUserUuid: user?['uuid'] as String?,
      responsibleUserFullname: user?['fullname'] as String?,
      responsibleRoleUuid: role?['uuid'] as String?,
      responsibleRoleName: role?['name'] as String?,
      actualConsumptions: (json['actual_consumptions'] as List<dynamic>?)
              ?.map((item) =>
                  RepairConsumption.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      photos: (json['photos'] as List<dynamic>?)
              ?.map(
                  (item) => RepairPhoto.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      normItems: (norm?['items'] as List<dynamic>?)
              ?.map((item) =>
                  RepairNormItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Repair && runtimeType == other.runtimeType && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;
}

/// Позиция фактического расхода ЗИП в ремонте.
class RepairConsumption {
  final String sparePartUuid;
  final String sparePartName;
  final String? unitName;
  final double quantity;

  /// Плановое количество по норме. `null` — позиции нет в норме либо нормы
  /// у ремонта нет вовсе.
  final double? normQuantity;

  RepairConsumption({
    required this.sparePartUuid,
    required this.sparePartName,
    this.unitName,
    this.quantity = 0,
    this.normQuantity,
  });

  factory RepairConsumption.fromJson(Map<String, dynamic> json) {
    final sparePart = json['spare_part'] as Map<String, dynamic>?;
    final unit = sparePart?['unit'] as Map<String, dynamic>?;
    return RepairConsumption(
      sparePartUuid: sparePart?['uuid'] as String? ?? '',
      sparePartName: sparePart?['name'] as String? ?? '',
      unitName: unit?['name'] as String? ?? unit?['code'] as String?,
      quantity: parseServerDecimal(json['quantity']) ?? 0,
      normQuantity: parseServerDecimal(json['norm_quantity']),
    );
  }
}

/// Позиция состава нормы расхода: что и сколько положено по норме.
class RepairNormItem {
  final String sparePartUuid;
  final String sparePartName;
  final double quantity;

  RepairNormItem({
    required this.sparePartUuid,
    required this.sparePartName,
    this.quantity = 0,
  });

  factory RepairNormItem.fromJson(Map<String, dynamic> json) {
    final sparePart = json['spare_part'] as Map<String, dynamic>?;
    return RepairNormItem(
      sparePartUuid: sparePart?['uuid'] as String? ?? '',
      sparePartName: sparePart?['name'] as String? ?? '',
      quantity: parseServerDecimal(json['quantity']) ?? 0,
    );
  }
}

/// Фотография, приложенная к ремонту.
class RepairPhoto {
  final String uuid;
  final String url;
  final int? order;

  RepairPhoto({required this.uuid, required this.url, this.order});

  factory RepairPhoto.fromJson(Map<String, dynamic> json) {
    return RepairPhoto(
      uuid: json['uuid'] as String? ?? '',
      url: json['url'] as String? ?? '',
      order: json['order'] as int?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hive-адаптеры. Написаны руками: порядок чтения обязан совпадать с
// порядком записи, новое поле — только в конец write() и через try/catch
// в read(). typeId переиспользованию не подлежат.
// ─────────────────────────────────────────────────────────────────────────

class RepairAdapter extends TypeAdapter<Repair> {
  @override
  final int typeId = 23;

  @override
  Repair read(BinaryReader reader) {
    return Repair(
      id: reader.read(),
      uuid: reader.read(),
      status: reader.read(),
      equipmentUuid: reader.read(),
      equipmentName: reader.read(),
      equipmentTypeModel: reader.read(),
      consumptionNormUuid: reader.read(),
      consumptionNormName: reader.read(),
      createdAt: reader.read(),
      startedAt: reader.read(),
      underReviewAt: reader.read(),
      completedAt: reader.read(),
      duration: reader.read(),
      comment: reader.read(),
      responsibleUserUuid: reader.read(),
      responsibleUserFullname: reader.read(),
      responsibleRoleUuid: reader.read(),
      responsibleRoleName: reader.read(),
      actualConsumptions: reader.read().cast<RepairConsumption>(),
      photos: reader.read().cast<RepairPhoto>(),
      // Поле добавлено позже остальных, поэтому читается последним и через
      // try/catch: в записях, сохранённых до его появления, его просто нет.
      normItems: _readTrailingList<RepairNormItem>(reader),
    );
  }

  static List<T> _readTrailingList<T>(BinaryReader reader) {
    try {
      return reader.read().cast<T>();
    } catch (_) {
      return const [];
    }
  }

  @override
  void write(BinaryWriter writer, Repair obj) {
    writer.write(obj.id);
    writer.write(obj.uuid);
    writer.write(obj.status);
    writer.write(obj.equipmentUuid);
    writer.write(obj.equipmentName);
    writer.write(obj.equipmentTypeModel);
    writer.write(obj.consumptionNormUuid);
    writer.write(obj.consumptionNormName);
    writer.write(obj.createdAt);
    writer.write(obj.startedAt);
    writer.write(obj.underReviewAt);
    writer.write(obj.completedAt);
    writer.write(obj.duration);
    writer.write(obj.comment);
    writer.write(obj.responsibleUserUuid);
    writer.write(obj.responsibleUserFullname);
    writer.write(obj.responsibleRoleUuid);
    writer.write(obj.responsibleRoleName);
    writer.write(obj.actualConsumptions);
    writer.write(obj.photos);
    writer.write(obj.normItems);
  }
}

class RepairNormItemAdapter extends TypeAdapter<RepairNormItem> {
  @override
  final int typeId = 26;

  @override
  RepairNormItem read(BinaryReader reader) {
    return RepairNormItem(
      sparePartUuid: reader.read(),
      sparePartName: reader.read(),
      quantity: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, RepairNormItem obj) {
    writer.write(obj.sparePartUuid);
    writer.write(obj.sparePartName);
    writer.write(obj.quantity);
  }
}

class RepairConsumptionAdapter extends TypeAdapter<RepairConsumption> {
  @override
  final int typeId = 24;

  @override
  RepairConsumption read(BinaryReader reader) {
    return RepairConsumption(
      sparePartUuid: reader.read(),
      sparePartName: reader.read(),
      unitName: reader.read(),
      quantity: reader.read(),
      normQuantity: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, RepairConsumption obj) {
    writer.write(obj.sparePartUuid);
    writer.write(obj.sparePartName);
    writer.write(obj.unitName);
    writer.write(obj.quantity);
    writer.write(obj.normQuantity);
  }
}

class RepairPhotoAdapter extends TypeAdapter<RepairPhoto> {
  @override
  final int typeId = 25;

  @override
  RepairPhoto read(BinaryReader reader) {
    return RepairPhoto(
      uuid: reader.read(),
      url: reader.read(),
      order: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, RepairPhoto obj) {
    writer.write(obj.uuid);
    writer.write(obj.url);
    writer.write(obj.order);
  }
}
