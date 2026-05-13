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

  static String displayName(String type) {
    switch (type) {
      case assignedInspection:
        return 'Назначение осмотра';
      case newTask:
        return 'Новая задача';
      case overdueTask:
        return 'Просрочка задачи';
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
      default:
        return status;
    }
  }
}
