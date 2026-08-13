class NotificationSettings {
  bool notificationsEnabled;
  bool realtimeEnabled;
  int? maxFutureDays;
  Map<String, bool> typePreferences;
  Map<String, bool> statusPreferences;

  NotificationSettings({
    required this.notificationsEnabled,
    required this.realtimeEnabled,
    required this.maxFutureDays,
    required this.typePreferences,
    required this.statusPreferences,
  });

  factory NotificationSettings.defaults() => NotificationSettings(
        notificationsEnabled: true,
        realtimeEnabled: true,
        maxFutureDays: null,
        // Зеркало серверных DEFAULT_TYPE_PREFERENCES /
        // DEFAULT_STATUS_PREFERENCES (`services/notifications/mobile.py`).
        // Значения нужны только до первого ответа сервера, но расходиться им
        // незачем: экран настроек рисует переключатели по этому набору.
        typePreferences: {
          'assigned_inspection': true,
          'new_task': true,
          'overdue_task': true,
          'summary_task': true,
          'repair_assigned': true,
          'repair_returned_for_rework': true,
        },
        statusPreferences: {
          'new': true,
          'viewed': true,
          'completed': true,
          'overdue': true,
          'unassigned': true,
        },
      );

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final types = <String, bool>{};
    (json['type_preferences'] as Map<String, dynamic>?)?.forEach((k, v) {
      types[k] = v as bool;
    });
    final statuses = <String, bool>{};
    (json['status_preferences'] as Map<String, dynamic>?)?.forEach((k, v) {
      statuses[k] = v as bool;
    });
    return NotificationSettings(
      notificationsEnabled: (json['notifications_enabled'] ?? true) as bool,
      realtimeEnabled: (json['realtime_enabled'] ?? true) as bool,
      maxFutureDays: json['max_future_days'] as int?,
      typePreferences: types,
      statusPreferences: statuses,
    );
  }

  Map<String, dynamic> toJson() => {
        'notifications_enabled': notificationsEnabled,
        'realtime_enabled': realtimeEnabled,
        'max_future_days': maxFutureDays,
        'type_preferences': typePreferences,
        'status_preferences': statusPreferences,
      };
}
