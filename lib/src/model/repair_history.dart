import 'package:intl/intl.dart';

import '../../strings.dart';
import 'repair.dart';
import '../utils/company_time.dart';

/// Запись истории ремонта — `GET /v1/repairs/{uuid}/history` (бэкенд
/// `7be3756`): создание, перенос даты начала, смена статуса, удаление.
///
/// В Hive не хранится: история нужна только на её экране и только в сети.
class RepairHistoryEntry {
  final int id;

  /// `created` / `rescheduled` / `started` / `status_changed` / `deleted` /
  /// `start_time_corrected`.
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
    if (isSystem) return RepairHistoryStrings.authorSystem;
    final name = actorFullname?.trim() ?? '';
    return name.isEmpty ? RepairHistoryStrings.authorUnknown : shortName(name);
  }

  /// Инициалы для кружка автора: фамилия и имя — «МД». `null` — автора нет
  /// (запуск по расписанию или учётную запись удалили).
  String? get initials {
    if (isSystem) return null;
    final parts = (actorFullname?.trim() ?? '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final result = [for (final part in parts) part[0].toUpperCase()].join();
    return result.isEmpty ? null : result;
  }

  /// Что произошло — «закрытие ремонта», «запуск по расписанию», как в
  /// веб-админке.
  String get actionLabel {
    switch (action) {
      case 'created':
        return RepairHistoryStrings.actionCreated;
      case 'deleted':
        return RepairHistoryStrings.actionDeleted;
      case 'rescheduled':
        return RepairHistoryStrings.actionRescheduled;
      // Прежнее и новое начало — строкой «Дата начала» в [changes], как у
      // переноса; статус в этой записи не меняется (открыт → открыт), смена
      // на «На рассмотрении» идёт следующей записью.
      case 'start_time_corrected':
        return RepairHistoryStrings.actionStartTimeCorrected;
      case 'started':
        return isSystem
            ? RepairHistoryStrings.actionStartedByScheduler
            : RepairHistoryStrings.actionStartedEarly;
    }
    switch (newStatus) {
      case RepairStatuses.underReview:
        return RepairHistoryStrings.actionSubmitted;
      case RepairStatuses.closed:
        return RepairHistoryStrings.actionClosed;
      case RepairStatuses.open when oldStatus == RepairStatuses.underReview:
        return RepairHistoryStrings.actionReturned;
    }
    return RepairHistoryStrings.actionStatusChanged;
  }

  /// Что изменила запись (макет 14i): создание, перенос даты начала, смена
  /// статуса.
  ///
  /// Перенос открытого ремонта на будущее меняет и дату, и статус — тогда
  /// строк две. Запись без видимых изменений даёт пустой список: её не
  /// показываем.
  List<RepairHistoryChange> get changes {
    if (action == 'created' || action == 'deleted') {
      final status = action == 'created' ? newStatus : oldStatus;
      return [
        if (status != null && status.isNotEmpty)
          RepairHistoryChange.status(to: status),
      ];
    }
    final result = <RepairHistoryChange>[];
    final oldStart = oldStartedAt;
    final newStart = newStartedAt;
    if (oldStart != null &&
        newStart != null &&
        formatDateTime(oldStart) != formatDateTime(newStart)) {
      result.add(RepairHistoryChange.startDate(
        from: formatDateTime(oldStart),
        to: formatDateTime(newStart),
      ));
    }
    final from = oldStatus;
    final to = newStatus;
    if (from != null && to != null && from != to) {
      result.add(RepairHistoryChange.status(from: from, to: to));
    }
    return result;
  }

  static String formatDateTime(DateTime value) =>
      DateFormat('dd.MM.yyyy HH:mm').format(CompanyTime.of(value));

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

/// Строка карточки изменений: «Статус  Открыт → На рассмотрении» или
/// «Дата начала  01.11.2026 17:15 → 02.11.2026 09:00».
class RepairHistoryChange {
  final String label;

  /// Статус (код) или дата начала — от этого зависит, пилюли это или текст.
  final bool isStatus;

  /// Было. `null` — у создания и удаления: одно значение, без стрелки.
  final String? from;

  /// Стало: код статуса или дата строкой.
  final String to;

  const RepairHistoryChange.status({this.from, required this.to})
      : label = RepairHistoryStrings.changeStatus,
        isStatus = true;

  const RepairHistoryChange.startDate({
    required String this.from,
    required this.to,
  })  : label = RepairHistoryStrings.changeStartDate,
        isStatus = false;
}
