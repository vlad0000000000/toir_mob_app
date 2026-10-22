import 'dart:convert';

/// Коды прав роли доступа, которые нужны мобильному приложению.
///
/// Источник — каталог бэкенда (`backend/security/permissions.py`). Здесь не
/// весь каталог, а только то, по чему приложение что-то решает: остальные
/// права — административные, обходчику в приложении не нужны.
class Perm {
  Perm._();

  static const String tasksView = 'tasks.view';
  static const String tasksExecute = 'tasks.execute';
  static const String inspectionView = 'inspection.view';
  static const String inspectionCreate = 'inspection.create';
  static const String equipmentView = 'equipment.view';
  static const String equipmentEdit = 'equipment.edit';
  static const String usageParametersEdit = 'usage_parameters.edit';
  static const String pprView = 'ppr.view';
  static const String repairView = 'repair.view';
  static const String repairCreate = 'repair.create';
  static const String repairExecute = 'repair.execute';
  static const String sparePartsView = 'spare_parts.view';
  static const String notificationsView = 'notifications.view';
  static const String companyView = 'company.view';
  static const String scopeAllDirections = 'scope.all_directions';
  static const String scopeAllDivisions = 'scope.all_divisions';
}

/// Ссылка на направление или подразделение — как их отдаёт сервер:
/// `{id, uuid, name}`.
class AccessRef {
  final int? id;
  final String uuid;
  final String name;

  const AccessRef({this.id, required this.uuid, required this.name});

  /// `null` — ссылки нет или она без uuid: такая ни с чем не сопоставится.
  static AccessRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final uuid = json['uuid'];
    if (uuid is! String || uuid.isEmpty) return null;
    final id = json['id'];
    final name = json['name'];
    return AccessRef(
      id: id is int ? id : null,
      uuid: uuid,
      name: name is String ? name : '',
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'uuid': uuid,
        'name': name,
      };
}

/// Что обходчику можно в приложении: роль доступа, её права, направление и
/// подразделения — как их видит сервер (`GET /v1/user/me`).
///
/// Права проверяет сервер на каждом запросе; профиль нужен приложению, чтобы
/// заранее показать доступное и не копить в очереди то, что сервер
/// заведомо отклонит. Источник правды — сервер: профиль перечитывается при
/// входе и при каждой синхронизации справочников.
///
/// Хранится JSON-строкой в `stringBox` под uuid пользователя
/// ([DataProvider.storedAccessProfile]) — не в Hive-адаптере `User`: так
/// формат можно менять без миграции, и профиль переживает перезапуск без
/// сети. Привязка к пользователю нужна и офлайн-входу: без роли он закрыт.
class AccessProfile {
  /// Коды прав роли. Сервер отдаёт их и у отключённой роли, поэтому
  /// проверять право нужно через [can], а не по этому набору напрямую.
  final Set<String> permissions;

  /// Роль доступа. `null` — роль не назначена.
  final AccessRef? role;

  /// Роль назначена, но отключена администратором компании.
  final bool roleActive;

  /// Направление роли. `null` — роль без направления: видны только общие
  /// задачи и ремонты, если нет права «Все направления».
  final AccessRef? direction;

  final List<AccessRef> divisions;

  /// Компания пользователя. `null` — учётная запись не привязана к компании.
  final String? companyId;

  /// Непрозрачная версия доступа: меняется при любом изменении роли, прав,
  /// направления или подразделений. Сервер присылает её и в заголовке
  /// `X-Access-Version` каждого ответа.
  final String? accessVersion;

  const AccessProfile({
    required this.permissions,
    this.role,
    this.roleActive = false,
    this.direction,
    this.divisions = const [],
    this.companyId,
    this.accessVersion,
  });

  /// Коды, при которых сервер закрывает бизнес-доступ
  /// (`AccessContext.ensure_business_access`).
  static const String codeCompanyMissing = 'company_missing';
  static const String codeRoleMissing = 'access_role_missing';
  static const String codeRoleInactive = 'access_role_inactive';

  /// Работать нельзя — и почему, тем же кодом, что прислал бы сервер на
  /// любой бизнес-запрос. `null` — доступ есть.
  ///
  /// Порядок проверок тот же, что у сервера: компания, роль, активность роли.
  String? get blockCode {
    if (companyId == null) return codeCompanyMissing;
    if (role == null) return codeRoleMissing;
    if (!roleActive) return codeRoleInactive;
    return null;
  }

  bool get hasBusinessAccess => blockCode == null;

  /// Есть ли у роли право [code]. Повторяет `AccessContext.has` сервера: без
  /// бизнес-доступа (нет роли, роль отключена) права нет никакого, даже если
  /// код в наборе.
  bool can(String code) => hasBusinessAccess && permissions.contains(code);

  bool get allDirections => can(Perm.scopeAllDirections);

  bool get allDivisions => can(Perm.scopeAllDivisions);

  /// Разбирает ответ `GET /v1/user/me`.
  ///
  /// Каждое поле — с запасным значением: сервер отдаёт роль, направление и
  /// компанию как `null`, когда их нет, и падать на этом нельзя — вход
  /// обходчика без направления раньше рушился именно так, на
  /// `custom_role_id: null`.
  factory AccessProfile.fromMeJson(Map<String, dynamic> json) {
    final role = json['user_role'];
    final scope = json['access_scope'];
    final companyId = scope is Map ? scope['company_id'] : null;
    return AccessProfile(
      permissions: _codes(json['permissions']),
      role: AccessRef.fromJson(role),
      roleActive: role is Map && role['is_active'] == true,
      direction: AccessRef.fromJson(json['direction']),
      divisions: _refs(json['divisions']),
      companyId: companyId == null ? null : '$companyId',
      accessVersion: json['access_version'] as String?,
    );
  }

  /// Профиль из ответа `/v1/user/me` — или `null`, если сервер ролей доступа
  /// не знает (прошлая версия бэкенда: в ответе нет `access_scope`).
  ///
  /// `null`, а не пустой профиль намеренно: пустой означал бы «нет компании,
  /// нет роли», и обходчика не пустили бы на сервере, где ролей просто ещё
  /// нет. Неизвестный профиль ничего не запирает (`SectionAccess`).
  static AccessProfile? fromServer(Map<String, dynamic> json) =>
      json['access_scope'] is Map ? AccessProfile.fromMeJson(json) : null;

  /// Тот же профиль, но с блокировкой, о которой сообщил сервер отказом 403
  /// ([codeRoleMissing], [codeRoleInactive], [codeCompanyMissing]).
  ///
  /// Нужен офлайн-входу: роль сняли во время работы — пока обходчик не войдёт
  /// онлайн и сервер не скажет иное, без сети пускать нельзя. Неизвестный код
  /// профиль не меняет.
  AccessProfile blockedBy(String code) {
    return AccessProfile(
      permissions: permissions,
      role: code == codeRoleMissing ? null : role,
      roleActive: code == codeRoleInactive ? false : roleActive,
      direction: direction,
      divisions: divisions,
      companyId: code == codeCompanyMissing ? null : companyId,
      accessVersion: accessVersion,
    );
  }

  /// Формат хранения в `stringBox` — свой, а не ответ сервера: разбор не
  /// должен зависеть от того, как сервер когда-нибудь переименует поля.
  Map<String, dynamic> toJson() => {
        'permissions': permissions.toList()..sort(),
        if (role != null) 'role': role!.toJson(),
        'role_active': roleActive,
        if (direction != null) 'direction': direction!.toJson(),
        'divisions': [for (final division in divisions) division.toJson()],
        if (companyId != null) 'company_id': companyId,
        if (accessVersion != null) 'access_version': accessVersion,
      };

  factory AccessProfile.fromJson(Map<String, dynamic> json) {
    return AccessProfile(
      permissions: _codes(json['permissions']),
      role: AccessRef.fromJson(json['role']),
      roleActive: json['role_active'] == true,
      direction: AccessRef.fromJson(json['direction']),
      divisions: _refs(json['divisions']),
      companyId: json['company_id'] as String?,
      accessVersion: json['access_version'] as String?,
    );
  }

  /// `null` — строки нет или она не разбирается: профиль считаем
  /// неизвестным, а не «без прав».
  static AccessProfile? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final data = jsonDecode(stored);
      return data is Map<String, dynamic> ? AccessProfile.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  static Set<String> _codes(Object? raw) =>
      {if (raw is List) ...raw.whereType<String>()};

  static List<AccessRef> _refs(Object? raw) => [
        if (raw is List)
          for (final item in raw)
            if (AccessRef.fromJson(item) case final ref?) ref,
      ];

  /// Сравнение по содержимому: профиль перечитывается раз в минуту, и
  /// [ValueNotifier] без этого будил бы слушателей на каждый одинаковый ответ.
  @override
  bool operator ==(Object other) =>
      other is AccessProfile && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
