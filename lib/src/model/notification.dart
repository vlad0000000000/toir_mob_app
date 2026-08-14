class AppNotification {
  final String uuid;
  final String notificationType;
  final String title;
  final String description;
  final String status;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? priority;
  final String? priorityDisplay;
  final String? equipmentUuid;
  final String? equipmentName;
  final String? inspectionUuid;
  final String? responsibleUserUuid;
  final String? responsibleUserFullname;
  final String? targetScope;
  final bool canOpenTarget;
  final Map<String, dynamic> payload;

  /// Идентификатор ремонта, если уведомление про ремонт. Сервер кладёт его в
  /// `payload.repair.uuid` — наверху ответа (`entity_uuid`) для мобильного
  /// списка его нет. Нужен, чтобы тап открывал сам ремонт, а не общий список
  /// уведомлений.
  String? get repairUuid {
    final repair = payload['repair'];
    if (repair is Map) {
      final uuid = repair['uuid'];
      if (uuid is String && uuid.isNotEmpty) return uuid;
    }
    return null;
  }

  /// Ремонт назначен на должность, а исполнителя у него нет — такой может
  /// взять в работу любой обходчик этой должности.
  ///
  /// Сервер шлёт оба случая одним типом `repair_assigned`, различая их только
  /// заголовком: «Вам назначен ремонт: …» против «Свободный ремонт, можно
  /// взять в работу: …». Признак тот же, по которому он выбирает шаблон, —
  /// пустой `responsible_user` в payload.
  bool get isFreeRepair {
    if (notificationType != NotificationTypes.repairAssigned) return false;
    final user = payload['responsible_user'];
    final uuid = user is Map ? user['uuid'] : null;
    return uuid == null || (uuid is String && uuid.isEmpty);
  }

  AppNotification({
    required this.uuid,
    required this.notificationType,
    required this.title,
    required this.description,
    required this.status,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
    required this.updatedAt,
    required this.priority,
    required this.priorityDisplay,
    required this.equipmentUuid,
    required this.equipmentName,
    required this.inspectionUuid,
    required this.responsibleUserUuid,
    required this.responsibleUserFullname,
    required this.targetScope,
    required this.canOpenTarget,
    required this.payload,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      uuid: json['uuid'] as String,
      notificationType: json['notification_type'] as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      status: (json['status'] ?? 'new') as String,
      isRead: (json['is_read'] ?? false) as bool,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      priority: json['priority'] as String?,
      priorityDisplay: json['priority_display'] as String?,
      equipmentUuid: json['equipment_uuid'] as String?,
      equipmentName: json['equipment_name'] as String?,
      inspectionUuid: json['inspection_uuid'] as String?,
      responsibleUserUuid: json['responsible_user_uuid'] as String?,
      responsibleUserFullname: json['responsible_user_fullname'] as String?,
      targetScope: json['target_scope'] as String?,
      canOpenTarget: (json['can_open_target'] ?? false) as bool,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class NotificationListResponse {
  final List<AppNotification> items;
  final int unreadCount;
  final int total;

  NotificationListResponse({
    required this.items,
    required this.unreadCount,
    required this.total,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>?) ?? const [];
    return NotificationListResponse(
      items: list
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      unreadCount: (json['unread_count'] ?? 0) as int,
      total: (json['total'] ?? 0) as int,
    );
  }
}

class NotificationTypes {
  static const String assignedInspection = 'assigned_inspection';
  static const String newTask = 'new_task';
  static const String overdueTask = 'overdue_task';
  static const String inspectionHighPriority = 'inspection_high_priority';
  static const String summaryTask = 'summary_task';

  /// Администратор вернул ремонт на доработку. Адресуется лично
  /// ответственному либо его должности.
  static const String repairReturnedForRework = 'repair_returned_for_rework';

  /// Ремонт назначен на обходчика или на его должность — при создании
  /// администратором либо при смене ответственного. Как и возврат на
  /// доработку, ведёт прямо в карточку ремонта.
  static const String repairAssigned = 'repair_assigned';

  /// Подпись типа с учётом содержимого уведомления.
  ///
  /// Нужна там, где одного `notification_type` не хватает: `repair_assigned`
  /// приходит и на «вам назначен», и на «свободный, можно взять» — чип с
  /// одинаковой подписью противоречил бы заголовку.
  static String displayNameOf(AppNotification notification) =>
      notification.isFreeRepair
          ? 'Свободный ремонт'
          : displayName(notification.notificationType);

  static String displayName(String type) {
    switch (type) {
      case repairAssigned:
        return 'Назначен ремонт';
      case repairReturnedForRework:
        return 'Ремонт на доработку';
      case assignedInspection:
        return 'Назначение осмотра';
      case newTask:
        return 'Новая задача';
      case overdueTask:
        return 'Просрочка задачи';
      case inspectionHighPriority:
        return 'Осмотр (высокий приоритет)';
      case summaryTask:
        return 'Сводка по задачам';
      default:
        return type;
    }
  }
}

class NotificationStatuses {
  static const String newStatus = 'new';
  static const String viewed = 'viewed';
  static const String completed = 'completed';
  static const String overdue = 'overdue';

  /// У осмотра нет исполнителя: сервер выставляет этот статус уведомлению
  /// `assigned_inspection`, когда в payload есть блок `unassigned`. Без
  /// перевода в чипе статуса светилось английское «unassigned».
  static const String unassigned = 'unassigned';

  static String displayName(String status) {
    switch (status) {
      case newStatus:
        return 'Новая';
      case viewed:
        return 'Просмотрена';
      case completed:
        return 'Выполнена';
      case overdue:
        return 'Просрочена';
      case unassigned:
        return 'Не назначена';
      default:
        return status;
    }
  }
}
