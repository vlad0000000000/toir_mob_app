import 'repair.dart';

/// Незакрытый ремонт оборудования — строка подсказки «над оборудованием уже
/// работают» (`GET /v1/company/equipment/{uuid}/unfinished-repairs`, бэкенд
/// `8a88247`).
///
/// Сервер отдаёт ремонты **всех** служб по оборудованию, а не только из
/// области обходчика, — поэтому это отдельная лёгкая модель, а не [Repair]:
/// расхода, фото и комментария в ней нет, и открыть можно не каждый
/// ([canOpen]). В Hive не хранится.
class UnfinishedRepairHint {
  final int id;
  final String uuid;

  /// `scheduled` / `open` / `under_review` ([RepairStatuses]).
  final String status;
  final DateTime startedAt;

  /// Служба (направление) ремонта.
  final String? responsibleRoleName;

  /// Ответственный. `null` — на должность, исполнителя нет.
  final String? responsibleUserFullname;

  /// Ремонт в области обходчика: его можно открыть через
  /// `GET /v1/repairs/{uuid}`. `false` — ремонт другой службы: строку
  /// показываем с замком, карточку не открываем.
  final bool canOpen;

  const UnfinishedRepairHint({
    required this.id,
    required this.uuid,
    required this.status,
    required this.startedAt,
    this.responsibleRoleName,
    this.responsibleUserFullname,
    required this.canOpen,
  });

  factory UnfinishedRepairHint.fromJson(Map<String, dynamic> json) {
    final role = json['responsible_role'];
    final user = json['responsible_user'];
    return UnfinishedRepairHint(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uuid: json['uuid'] as String? ?? '',
      status: json['status'] as String? ?? RepairStatuses.open,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      responsibleRoleName: role is Map ? role['name'] as String? : null,
      responsibleUserFullname: user is Map ? user['fullname'] as String? : null,
      // По умолчанию — нельзя: строка без перехода безопаснее карточки,
      // которая откроется с «нет доступа».
      canOpen: json['can_open'] == true,
    );
  }

  /// Подсказка по ремонту, который уже есть целиком: из офлайн-кэша или со
  /// старого сервера, у которого нового запроса нет. Такой ремонт обходчику
  /// виден — значит, его можно открыть.
  factory UnfinishedRepairHint.fromRepair(Repair repair) =>
      UnfinishedRepairHint(
        id: repair.id,
        uuid: repair.uuid,
        status: repair.status,
        startedAt: repair.startedAt,
        responsibleRoleName: repair.responsibleRoleName,
        responsibleUserFullname: repair.responsibleUserFullname,
        canOpen: true,
      );

  /// Та же подсказка, но без перехода: сервер пустил в подсказку, а карточку
  /// не отдал (ремонт ушёл из области обходчика, пока шёл запрос).
  UnfinishedRepairHint locked() => UnfinishedRepairHint(
        id: id,
        uuid: uuid,
        status: status,
        startedAt: startedAt,
        responsibleRoleName: responsibleRoleName,
        responsibleUserFullname: responsibleUserFullname,
        canOpen: false,
      );

  bool get isScheduled => status == RepairStatuses.scheduled;

  bool get isUnfinished =>
      status == RepairStatuses.scheduled ||
      status == RepairStatuses.open ||
      status == RepairStatuses.underReview;
}
