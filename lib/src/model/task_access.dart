import 'dart:convert';

import 'access_profile.dart';

/// Доступ к экземпляру задачи — как его видит сервер: кто исполнитель, к
/// каким направлениям экземпляр привязан и что текущему пользователю с ним
/// можно сделать.
///
/// Берётся из того же ответа `GET /v1/company/fault_inspections/`, что и
/// [Task]: поля `inspector`, `direction_scope`, `directions`,
/// `allowed_actions`. Сервер считает их по **сохранённому контексту
/// экземпляра**, а не по шаблону задачи: `periodic_task.custom_roles` у общей
/// задачи пустой, а у шаблона, переназначенного после создания экземпляра,
/// уже другой.
///
/// В Hive хранится JSON-строкой последним полем `Task` — без нового `typeId`
/// и без правки вложенных адаптеров.
class TaskAccess {
  /// Исполнитель — тот, кто взял экземпляр или записал результат. `null` —
  /// ещё никто.
  final String? inspectorUuid;

  /// `single`, `all` (общая задача компании) или `legacy_multiple`; `null` —
  /// прямой осмотр, а не экземпляр задачи.
  final String? directionScope;

  /// Действующие направления экземпляра: одно у `single`, все сохранённые у
  /// `legacy_multiple`, пусто у общей.
  final List<AccessRef> directions;

  /// Подсказка сервера, что пользователю можно: `take`, `execute`, `edit`,
  /// `review`, `reassign`. Сервер всё равно перепроверяет каждое действие.
  final List<String> allowedActions;

  const TaskAccess({
    this.inspectorUuid,
    this.directionScope,
    this.directions = const [],
    this.allowedActions = const [],
  });

  static const String scopeAll = 'all';
  static const String actionExecute = 'execute';
  static const String actionEdit = 'edit';

  /// Общая задача компании — её выполняет любой, у кого есть право.
  bool get isShared => directionScope == scopeAll;

  bool can(String action) => allowedActions.contains(action);

  factory TaskAccess.fromInspectionJson(Map<String, dynamic> json) {
    final inspector = json['inspector'];
    final uuid = inspector is Map ? inspector['uuid'] : null;
    return TaskAccess(
      inspectorUuid: uuid is String && uuid.isNotEmpty ? uuid : null,
      directionScope: json['direction_scope'] as String?,
      directions: _refs(json['directions']),
      allowedActions: [
        if (json['allowed_actions'] case final List<dynamic> raw)
          ...raw.whereType<String>(),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        if (inspectorUuid != null) 'inspector_uuid': inspectorUuid,
        if (directionScope != null) 'direction_scope': directionScope,
        'directions': [for (final ref in directions) ref.toJson()],
        'allowed_actions': allowedActions,
      };

  factory TaskAccess.fromJson(Map<String, dynamic> json) {
    return TaskAccess(
      inspectorUuid: json['inspector_uuid'] as String?,
      directionScope: json['direction_scope'] as String?,
      directions: _refs(json['directions']),
      allowedActions: [
        if (json['allowed_actions'] case final List<dynamic> raw)
          ...raw.whereType<String>(),
      ],
    );
  }

  /// `null` — строки нет (запись прошлой версии) или она не разбирается:
  /// доступ неизвестен, а не «ничего нельзя».
  static TaskAccess? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final data = jsonDecode(stored);
      return data is Map<String, dynamic> ? TaskAccess.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  static List<AccessRef> _refs(Object? raw) => [
        if (raw is List)
          for (final item in raw)
            if (AccessRef.fromJson(item) case final ref?) ref,
      ];
}
