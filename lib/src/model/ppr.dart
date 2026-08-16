/// ППР — планово-предупредительный ремонт со своим набором периодических
/// задач. Мобильному клиенту нужны актуальные
/// (незакрытые) ППР: по ним показывается кнопка «ППР» на главном экране,
/// группа «ППР» в списке задач оборудования и экран задач ППР.
class Ppr {
  final String uuid;

  /// Название ППР. Необязательное — ППР могут создавать без имени.
  final String? title;

  /// Статус с сервера: `QUEUED`, `IN_PROGRESS` и т. д. (`PprStatus`).
  final String status;

  /// UUID периодических задач с активным членством в этом ППР.
  final Set<String> periodicTaskUuids;

  /// UUID незакрытых осмотров задач этого ППР. Их подгружаем поштучно:
  /// в общей выборке задач осмотр может отсутствовать, если у него вышел
  /// срок, а задача ППР актуальна, пока ППР не закрыт.
  final Set<String> inspectionUuids;

  /// UUID осмотров уже выполненных задач ППР. Нужны, чтобы посчитать, сколько
  /// задач ППР закрыл лично пользователь: в списках таких задач уже нет.
  final Set<String> completedInspectionUuids;

  /// Счётчики с сервера — прогресс ППР целиком, по всем ролям сразу.
  /// Обходчику показываем прогресс по его задачам (см. `DataProvider`),
  /// эти счётчики остаются для отладки и возможных общих экранов.
  final int tasksCount;
  final int completedTasksCount;

  const Ppr({
    required this.uuid,
    required this.title,
    required this.status,
    required this.periodicTaskUuids,
    this.inspectionUuids = const {},
    this.completedInspectionUuids = const {},
    this.tasksCount = 0,
    this.completedTasksCount = 0,
  });

  static const String statusQueued = 'QUEUED';
  static const String statusInProgress = 'IN_PROGRESS';

  bool get isInProgress => status == statusInProgress;

  /// Заголовок для UI: имя ППР, а если его нет — просто «ППР».
  String get displayTitle {
    final t = title?.trim() ?? '';
    return t.isEmpty ? 'ППР' : t;
  }

  /// Заголовок группы «ППР» в списке задач оборудования: «ППР» для ППР без
  /// имени и «ППР · Название» — для именованного.
  String get groupTitle {
    final t = title?.trim() ?? '';
    return t.isEmpty ? 'ППР' : 'ППР · $t';
  }

  String get statusLabel {
    switch (status) {
      case statusInProgress:
        return 'В работе';
      case statusQueued:
        return 'В очереди';
      default:
        return '';
    }
  }

  /// Разбор ответа `/v1/company/ppr/` (список) вместе с уже собранными из
  /// детального ответа UUID периодических задач.
  factory Ppr.fromListJson(
    Map<String, dynamic> json,
    Set<String> periodicTaskUuids,
    Set<String> inspectionUuids,
    Set<String> completedInspectionUuids,
  ) {
    return Ppr(
      uuid: json['uuid'] as String,
      title: json['title'] as String?,
      status: (json['status'] as String?) ?? '',
      periodicTaskUuids: periodicTaskUuids,
      inspectionUuids: inspectionUuids,
      completedInspectionUuids: completedInspectionUuids,
      tasksCount: (json['tasks_count'] as int?) ?? 0,
      completedTasksCount: (json['completed_tasks_count'] as int?) ?? 0,
    );
  }

  /// Кэш в `stringBox` хранится обычным JSON — отдельный Hive-адаптер ради
  /// пары полей заводить незачем.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'title': title,
        'status': status,
        'periodic_task_uuids': periodicTaskUuids.toList(),
        'inspection_uuids': inspectionUuids.toList(),
        'completed_inspection_uuids': completedInspectionUuids.toList(),
        'tasks_count': tasksCount,
        'completed_tasks_count': completedTasksCount,
      };

  factory Ppr.fromJson(Map<String, dynamic> json) {
    return Ppr(
      uuid: json['uuid'] as String,
      title: json['title'] as String?,
      status: (json['status'] as String?) ?? '',
      periodicTaskUuids:
          ((json['periodic_task_uuids'] as List<dynamic>?) ?? const [])
              .map((e) => e as String)
              .toSet(),
      inspectionUuids:
          ((json['inspection_uuids'] as List<dynamic>?) ?? const [])
              .map((e) => e as String)
              .toSet(),
      completedInspectionUuids:
          ((json['completed_inspection_uuids'] as List<dynamic>?) ?? const [])
              .map((e) => e as String)
              .toSet(),
      tasksCount: (json['tasks_count'] as int?) ?? 0,
      completedTasksCount: (json['completed_tasks_count'] as int?) ?? 0,
    );
  }
}
