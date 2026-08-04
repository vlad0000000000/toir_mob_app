import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../global_state.dart';
import '../design/app_theme.dart';
import '../model/notification.dart';

/// Чистые форматтеры/стили уведомлений. Вынесены из `_NotificationsScreenState`,
/// чтобы и экран, и `NotificationCard` использовали их без cross-class доступа
/// к приватным статикам State.
class NotificationFormatters {
  /// Тег типа уведомления для верхней метки карточки/детали. Для снятия с
  /// осмотра сервер не меняет `notification_type` (остаётся
  /// `assigned_inspection`), а помечает снятие через `status == unassigned`.
  /// Дефолтная метка «Назначение осмотра» тут вводит в заблуждение, поэтому
  /// показываем «Снятие с осмотра».
  static String typeLabel(AppNotification n) {
    if (n.status == NotificationStatuses.unassigned) {
      return 'Снятие с осмотра';
    }
    return NotificationTypes.displayName(n.notificationType);
  }

  /// Статус для отображения. Сервер у некоторых типов (напр. уведомление о
  /// снятии исполнителя с осмотра) присылает статус вне нашего словаря —
  /// тогда показываем Новая/Просмотрена по флагу is_read, чтобы у всех
  /// уведомлений был единый бейдж и цвет (зелёный/голубой), и в списке, и
  /// в карточке.
  static String effectiveStatus(AppNotification n) {
    if (NotificationStatuses.known.contains(n.status)) return n.status;
    return n.isRead
        ? NotificationStatuses.viewed
        : NotificationStatuses.newStatus;
  }

  /// Семантический цвет статуса уведомления, опираясь на ColorScheme
  /// (success / info / error). Контекст обязателен — нужен ColorScheme.
  static Color statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case NotificationStatuses.newStatus:
        return cs.primary;
      case NotificationStatuses.viewed:
        return cs.info;
      case NotificationStatuses.completed:
        return cs.success;
      case NotificationStatuses.overdue:
        return cs.error;
    }
    return cs.onSurfaceVariant;
  }

  static String formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(local);
  }

  /// Текст сводки по задачам: `Новых`, `Назначенных`, `Просроченных`.
  /// В детальной карточке (`multiline: true`) каждый параметр выводится
  /// с новой строки, в списке — через запятую.
  static String? summaryDescription(AppNotification n, {bool multiline = false}) {
    if (n.notificationType != NotificationTypes.summaryTask) return null;
    final s = n.payload['summary'];
    if (s is! Map) return null;
    final newTasks = (s['new_tasks'] ?? 0) as int;
    final assigned = (s['assigned_inspections'] ?? 0) as int;
    final overdue = (s['overdue_tasks'] ?? 0) as int;
    final sep = multiline ? '\n' : ', ';
    return 'Новых: $newTasks${sep}Назначенных: $assigned${sep}Просроченных: $overdue';
  }

  static String executorLabel(AppNotification n) {
    // 1) Конкретный человек (исполнитель/ответственный) — топ-приоритет.
    if (n.responsibleUserFullname != null &&
        n.responsibleUserFullname!.isNotEmpty) {
      return 'Исполнитель: ${n.responsibleUserFullname}';
    }
    // 2) Роль из payload. Сервер может класть её в несколько мест в
    // зависимости от типа уведомления — обходим все известные.
    final role = _extractRoleName(n.payload);
    if (role != null && role.isNotEmpty) {
      return 'Исполнитель: $role';
    }
    // 3) Фоллбэк — роль текущего пользователя. По ТЗ для «Новой задачи»
    // исполнитель = роль, которой адресовано уведомление; сервер её не
    // возвращает, но уведомление и так доходит только нужной роли, поэтому
    // безопасно показать роль текущего юзера вместо прочерка.
    final myRole = GlobalState.authUser?.effectiveRole;
    if (myRole != null && myRole.isNotEmpty) {
      return 'Исполнитель: $myRole';
    }
    return 'Исполнитель: —';
  }

  static String? _extractRoleName(Map<String, dynamic> payload) {
    // Прямые ключи
    final direct = _readName(payload['role']) ??
        _readName(payload['target_role']) ??
        _readName(payload['custom_role']);
    if (direct != null) return direct;

    // Внутри task / inspection
    for (final key in const ['task', 'inspection', 'periodic_task']) {
      final nested = payload[key];
      if (nested is Map<String, dynamic>) {
        final r = _readName(nested['role']) ??
            _readName(nested['custom_role']) ??
            _readName(nested['target_role']);
        if (r != null) return r;
        // Список custom_roles — берём первую с name
        final list = nested['custom_roles'];
        if (list is List) {
          for (final item in list) {
            final n = _readName(item);
            if (n != null) return n;
          }
        }
      }
    }
    return null;
  }

  static String? _readName(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map) {
      final name = v['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  /// Текст описания уведомления для карточки/детального экрана.
  /// Сначала берём `description` от сервера, потом fallback'и в payload —
  /// для `new_task` сервер часто кладёт описание задачи в `payload['task']`.
  static String effectiveDescription(AppNotification n) {
    if (n.description.isNotEmpty) return n.description;
    for (final key in const ['task', 'periodic_task', 'inspection']) {
      final nested = n.payload[key];
      if (nested is Map<String, dynamic>) {
        final d = nested['description'];
        if (d is String && d.isNotEmpty) return d;
      }
    }
    final pd = n.payload['description'];
    if (pd is String && pd.isNotEmpty) return pd;
    return '';
  }

  /// Дата создания связанной сущности (осмотра/задачи) из payload.
  /// Нужно для уведомлений о назначении осмотра — показываем когда сам
  /// осмотр был создан, а не когда мы прислали push.
  static DateTime? sourceCreatedAt(AppNotification n) {
    DateTime? parse(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    for (final key in const ['inspection', 'task', 'periodic_task']) {
      final nested = n.payload[key];
      if (nested is Map<String, dynamic>) {
        final dt = parse(nested['created_at']) ?? parse(nested['createdAt']);
        if (dt != null) return dt;
      }
    }
    return parse(n.payload['source_created_at']);
  }
}
