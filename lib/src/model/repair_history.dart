import 'package:intl/intl.dart';

import 'repair.dart';

/// Запись истории ремонта — `GET /v1/repairs/{uuid}/history` (бэкенд
/// `7be3756`): создание, перенос даты начала, смена статуса, удаление.
///
/// В Hive не хранится: история нужна только на её экране и только в сети.
class RepairHistoryEntry {
  final int id;

  /// `created` / `rescheduled` / `started` / `status_changed` / `deleted`.
  final String action;

  /// `scheduler` — ремонт запустил сервер по наступлении даты, автора нет.
  final String source;
  final DateTime createdAt;

  /// ФИО автора. `null` — автора нет: запуск по расписанию или учётную
  /// запись удалили.
  final String? actorFullname;
  final String? oldStatus;
  final String? newStatus;
  final DateTime? oldStartedAt;
  final DateTime? newStartedAt;

  const RepairHistoryEntry({
    required this.id,
    required this.action,
    required this.source,
    required this.createdAt,
    this.actorFullname,
    this.oldStatus,
    this.newStatus,
    this.oldStartedAt,
    this.newStartedAt,
  });

  factory RepairHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic value) =>
        value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
    final actor = json['actor_user'];
    return RepairHistoryEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      action: json['action'] as String? ?? '',
      source: json['source'] as String? ?? '',
      createdAt: date(json['created_at']) ?? DateTime.now().toUtc(),
      actorFullname: actor is Map ? actor['fullname'] as String? : null,
      oldStatus: json['old_status'] as String?,
      newStatus: json['new_status'] as String?,
      oldStartedAt: date(json['old_started_at']),
      newStartedAt: date(json['new_started_at']),
    );
  }

  /// Запуск по расписанию — автор «Система».
  bool get isSystem => source == 'scheduler';

  /// Подпись автора: «Система», «Сидоров А. И.» или «Автор неизвестен» — как
  /// в веб-админке.
  String get authorLabel {
    if (isSystem) return 'Система';
    final name = actorFullname?.trim() ?? '';
    return name.isEmpty ? 'Автор неизвестен' : shortName(name);
  }

  /// Что изменила запись — строки «подпись · значение» (макет 14i).
  ///
  /// Перенос открытого ремонта на будущее меняет и дату, и статус — тогда
  /// строк две. Запись без видимых изменений даёт пустой список: её не
  /// показываем.
  List<(String, String)> get changes {
    if (action == 'created') {
      return [('Ремонт создан', _status(newStatus))];
    }
    if (action == 'deleted') {
      return [('Ремонт удалён', _status(oldStatus))];
    }
    final result = <(String, String)>[];
    final oldStart = oldStartedAt;
    final newStart = newStartedAt;
    if (oldStart != null &&
        newStart != null &&
        formatDateTime(oldStart) != formatDateTime(newStart)) {
      result.add((
        'Дата начала',
        '${formatDateTime(oldStart)} – ${formatDateTime(newStart)}',
      ));
    }
    final from = oldStatus;
    final to = newStatus;
    if (from != null && to != null && from != to) {
      result.add(('Статус', '${_status(from)} – ${_status(to)}'));
    }
    return result;
  }

  static String _status(String? status) => status == null || status.isEmpty
      ? '—'
      : RepairStatuses.displayName(status);

  static String formatDateTime(DateTime value) =>
      DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());

  /// «Сидоров Алексей Иванович» → «Сидоров А. И.».
  static String shortName(String fullname) {
    final parts = fullname.trim().split(RegExp(r'\s+'));
    final initials = [
      for (final part in parts.skip(1))
        if (part.isNotEmpty) '${part[0]}.',
    ].join(' ');
    return initials.isEmpty ? parts.first : '${parts.first} $initials';
  }
}
