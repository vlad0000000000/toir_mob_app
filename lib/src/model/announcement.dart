/// Сервисное объявление (бэкенд `81f644c`): `GET /v1/system/announcements`.
///
/// Публикует суперадминка: произвольный текст (`custom`) или «Вышла новая
/// версия» (`release`) со ссылкой на RuStore. Аудиторию — компании и версии —
/// фильтрует сервер, приложение показывает всё, что пришло.
class Announcement {
  final String uuid;
  final String title;
  final String body;

  /// `normal` или `important`.
  final String importance;

  /// `custom` или `release`.
  final String kind;
  final DateTime? visibleFrom;
  final DateTime? visibleUntil;

  /// Название новой версии у объявления `release`.
  final String? targetVersion;
  final String? updateUrl;
  final DateTime? readAt;

  const Announcement({
    required this.uuid,
    required this.title,
    required this.body,
    this.importance = 'normal',
    this.kind = 'custom',
    this.visibleFrom,
    this.visibleUntil,
    this.targetVersion,
    this.updateUrl,
    this.readAt,
  });

  bool get isImportant => importance == 'important';
  bool get isRelease => kind == 'release';
  bool get isRead => readAt != null;

  /// Ссылка на RuStore, если её можно открыть: только `https` — адрес
  /// приходит с сервера.
  Uri? get safeUpdateUri {
    final raw = updateUrl;
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  /// `null` — без uuid или заголовка: показать нечего.
  static Announcement? fromJson(Object? json) {
    if (json is! Map) return null;
    final uuid = json['announcement_uuid'];
    final title = json['title'];
    if (uuid is! String || uuid.isEmpty || title is! String) return null;
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    final target = json['target_release'];
    return Announcement(
      uuid: uuid,
      title: title,
      body: json['body'] is String ? json['body'] as String : '',
      importance: text(json['importance']) ?? 'normal',
      kind: text(json['kind']) ?? 'custom',
      visibleFrom: DateTime.tryParse('${json['visible_from'] ?? ''}'),
      visibleUntil: DateTime.tryParse('${json['visible_until'] ?? ''}'),
      targetVersion: target is Map ? text(target['version_name']) : null,
      updateUrl: text(json['update_url']),
      readAt: DateTime.tryParse('${json['read_at'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'announcement_uuid': uuid,
        'title': title,
        'body': body,
        'importance': importance,
        'kind': kind,
        'visible_from': visibleFrom?.toUtc().toIso8601String(),
        'visible_until': visibleUntil?.toUtc().toIso8601String(),
        if (targetVersion != null)
          'target_release': {'version_name': targetVersion},
        'update_url': updateUrl,
        'read_at': readAt?.toUtc().toIso8601String(),
      };

  Announcement markedRead(DateTime at) => Announcement(
        uuid: uuid,
        title: title,
        body: body,
        importance: importance,
        kind: kind,
        visibleFrom: visibleFrom,
        visibleUntil: visibleUntil,
        targetVersion: targetVersion,
        updateUrl: updateUrl,
        readAt: readAt ?? at,
      );
}

/// Список объявлений из ответа: `items[]` без битых записей.
List<Announcement> parseAnnouncements(Object? items) => [
      if (items is List)
        for (final item in items)
          if (Announcement.fromJson(item) case final parsed?) parsed,
    ];

/// Порядок показа: важные первыми, внутри — непрочитанные, затем свежие.
List<Announcement> sortAnnouncements(Iterable<Announcement> items) {
  final sorted = items.toList();
  int rank(Announcement a) => (a.isImportant ? 0 : 2) + (a.isRead ? 1 : 0);
  sorted.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final aFrom = a.visibleFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bFrom = b.visibleFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bFrom.compareTo(aFrom);
  });
  return sorted;
}

/// Объявления, видимые в [now]: срок показа мог кончиться, пока телефон без
/// связи, — такое из сохранённого списка не показываем.
List<Announcement> visibleAnnouncements(
  Iterable<Announcement> items,
  DateTime now,
) =>
    [
      for (final a in items)
        if ((a.visibleUntil == null || now.isBefore(a.visibleUntil!)) &&
            (a.visibleFrom == null || !now.isBefore(a.visibleFrom!)))
          a,
    ];

/// Ближайшая после [now] граница показа — начало или конец показа любого из
/// [items]. На ней видимость пересчитывается и без связи: иначе
/// восстановленное из кэша объявление висело бы после окончания срока.
/// `null` — будущих границ нет.
DateTime? nextVisibilityBoundary(Iterable<Announcement> items, DateTime now) {
  DateTime? next;
  for (final a in items) {
    for (final at in [a.visibleFrom, a.visibleUntil]) {
      if (at == null || !at.isAfter(now)) continue;
      if (next == null || at.isBefore(next)) next = at;
    }
  }
  return next;
}

/// Ответ сервера [items] с прочтениями, сделанными на телефоне
/// ([readLocally]: uuid → когда прочитали). Загрузка, начатая до прочтения,
/// может вернуться после того, как отметка уже ушла, — с `read_at: null`; без
/// этого прочитанное снова стало бы новым.
List<Announcement> withLocalReads(
  List<Announcement> items,
  Map<String, DateTime> readLocally,
) =>
    [
      for (final a in items)
        if (!a.isRead && readLocally[a.uuid] != null)
          a.markedRead(readLocally[a.uuid]!)
        else
          a,
    ];

/// Убирает из [readLocally] прочтения, которые больше не нужно держать:
/// сервер уже вернул объявление прочитанным или его нет в ответе [fromServer].
/// Остаются только те, что сервер пока отдаёт непрочитанными, — их и
/// накладывает [withLocalReads].
void pruneLocalReads(
  Map<String, DateTime> readLocally,
  List<Announcement> fromServer,
) {
  final stillUnreadOnServer = {
    for (final a in fromServer)
      if (!a.isRead) a.uuid,
  };
  readLocally.removeWhere((uuid, _) => !stillUnreadOnServer.contains(uuid));
}

/// Через сколько перечитать список по `next_change_at` сервера (ближайшая
/// граница показа): не раньше 1 с и не позже суток. `null` — границы нет.
Duration? announcementRefreshDelay(DateTime? nextChangeAt, DateTime now) {
  if (nextChangeAt == null) return null;
  final delay = nextChangeAt.difference(now);
  if (delay < const Duration(seconds: 1)) return const Duration(seconds: 1);
  if (delay > const Duration(days: 1)) return const Duration(days: 1);
  return delay;
}

/// Важные непрочитанные объявления из ответа `items`, о которых ещё не было
/// локального пуша ([pushed] — uuid уже показанных). Для фонового сервиса:
/// при закрытом приложении сервер системного пуша не шлёт.
List<Announcement> announcementsToPush(Object? items, Set<String> pushed) => [
      for (final a in parseAnnouncements(items))
        if (a.isImportant && !a.isRead && !pushed.contains(a.uuid)) a,
    ];
