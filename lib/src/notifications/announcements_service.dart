import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../global_state.dart';
import '../data/mobile_installation.dart';
import '../exceptions/app_exceptions.dart';
import '../http/api.dart';
import '../model/announcement.dart';
import '../utils/offline_error.dart';

/// Отладочный показ объявления о новой версии — посмотреть карточку и окно
/// снизу без настоящего релиза в RuStore. Настоящее сервер покажет только
/// продовому пакету со сборкой старше опубликованной, а локальная сборка и
/// стенд этому не отвечают. Включается при запуске:
/// `flutter run --dart-define=PREVIEW_RELEASE_ANNOUNCEMENT=true`. В
/// релизной сборке выключено всегда (`kDebugMode`).
const bool previewReleaseAnnouncementEnabled =
    kDebugMode && bool.fromEnvironment('PREVIEW_RELEASE_ANNOUNCEMENT');

/// Uuid отладочного объявления: «прочитано» по нему на сервер не уходит.
const String previewReleaseAnnouncementUuid = 'preview-release-announcement';

/// Отладочное объявление о новой версии ([previewReleaseAnnouncementEnabled]):
/// заголовок и текст — те, что суперадминка подставляет при создании такого
/// объявления; ссылка — карточка приложения в RuStore.
Announcement previewReleaseAnnouncement(DateTime shownAt, {DateTime? readAt}) =>
    Announcement(
      uuid: previewReleaseAnnouncementUuid,
      title: 'Вышла новая версия 1.1.0',
      body: 'Обновите приложение до версии 1.1.0, чтобы получить '
          'исправления и новые возможности.',
      kind: 'release',
      visibleFrom: shownAt,
      visibleUntil: shownAt.add(const Duration(days: 7)),
      targetVersion: '1.1.0',
      updateUrl: 'https://www.rustore.ru/catalog/app/pakgroup.qr.scanner.prod',
      readAt: readAt,
    );

/// Сервисные объявления в приложении (бэкенд `81f644c`).
///
/// SSE — только сигнал, источник правды REST: список перечитывается при
/// входе и открытии главной ([bootstrap]), возврате в приложение, по сигналу
/// `announcements_changed`, по таймеру ближайшей границы показа
/// (`next_change_at`) и после восстановления связи ([refreshIfStale]).
///
/// Только с зарегистрированной установкой: без неё сервер кладёт объявления
/// карточками 1.0 в обычную ленту, и второй блок их бы задвоил.
///
/// Последний список и недошедшие отметки «прочитано» хранятся по серверу и
/// пользователю: без связи блок показывается по сохранённому, а отметки
/// уходят, когда связь вернётся.
class AnnouncementsService {
  AnnouncementsService._();

  static final AnnouncementsService instance = AnnouncementsService._();

  /// Текущие объявления в порядке показа ([sortAnnouncements]).
  final ValueNotifier<List<Announcement>> current =
      ValueNotifier<List<Announcement>>(const []);

  /// Непрочитанные текущие — прибавляются к значку уведомлений на главной.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  final API _api = API();

  /// Последний ответ сервера целиком — фильтр по сроку показа применяется к
  /// нему при каждой публикации ([_publish]).
  List<Announcement> _items = const [];
  final Set<String> _pendingRead = <String>{};

  /// Прочитанные на телефоне в этой сессии — uuid → когда. Держатся, пока
  /// сервер сам не вернёт их прочитанными ([withLocalReads]).
  final Map<String, DateTime> _readLocally = <String, DateTime>{};

  /// Пересчёт видимости на ближайшей границе показа ([_publish]).
  Timer? _boundaryTimer;

  Timer? _timer;
  DateTime? _fetchedAt;

  /// Последняя попытка не удалась — перечитать при появлении связи.
  bool _stale = true;
  bool _inFlight = false;
  bool _queued = false;

  /// Растёт при выходе: ответ, пришедший после него, отбрасывается.
  int _session = 0;
  bool _loaded = false;

  ({String user, String server})? get _scope {
    final uuid = GlobalState.authUser?.uuid;
    if (uuid == null || uuid.isEmpty) return null;
    return (user: uuid, server: API.baseUrl);
  }

  /// Сохранённое и перечитка — при входе и открытии главной.
  Future<void> bootstrap() async {
    if (!_loaded) {
      _loaded = true;
      _restore();
    }
    await refresh();
  }

  void _restore() {
    final scope = _scope;
    if (scope == null) return;
    final box = GlobalState.dataProvider.stringBox;
    try {
      final reads = box.get(announcementReadsKey(scope.user, scope.server));
      if (reads != null && reads.isNotEmpty) {
        final data = jsonDecode(reads);
        if (data is List) _pendingRead.addAll(data.whereType<String>());
      }
    } catch (_) {
      // Битая очередь — отметки потеряны, сервис работает дальше.
    }
    try {
      final raw = box.get(announcementsCacheKey(scope.user, scope.server));
      if (raw != null && raw.isNotEmpty) {
        _items = parseAnnouncements(jsonDecode(raw));
      }
    } catch (_) {
      _items = const [];
    }
    _publish();
  }

  /// Перечитывает текущие объявления. [maxAge] — не ходить, если список
  /// свежее (возврат в приложение бывает часто). Повторный вызов, пока идёт
  /// загрузка, не плодит запросов: загрузка повторится один раз следом.
  Future<void> refresh({Duration maxAge = Duration.zero}) async {
    if (!GlobalState.isAuthorized) return;
    if (!_loaded) {
      _loaded = true;
      _restore();
    }
    final fetched = _fetchedAt;
    if (maxAge > Duration.zero &&
        fetched != null &&
        DateTime.now().difference(fetched) < maxAge) {
      return;
    }
    if (_inFlight) {
      _queued = true;
      return;
    }
    _inFlight = true;
    try {
      do {
        _queued = false;
        await _refreshOnce();
      } while (_queued);
    } finally {
      _inFlight = false;
    }
  }

  /// Перечитать, если прошлая попытка не удалась или список старше
  /// 15 минут, — из прохода синхронизации, то есть и после появления связи.
  Future<void> refreshIfStale() async {
    final fetched = _fetchedAt;
    if (_stale ||
        fetched == null ||
        DateTime.now().difference(fetched) > const Duration(minutes: 15)) {
      await refresh();
    }
  }

  Future<void> _refreshOnce() async {
    final scope = _scope;
    final id = GlobalState.dataProvider.installationHeaderId;
    if (scope == null) return;
    if (id == null) {
      // Установка не зарегистрирована — объявления придут карточками 1.0.
      _items = const [];
      _publish();
      return;
    }
    final session = _session;
    await _flushReads(id, session);
    if (session != _session) return;
    try {
      final data = await _api.getAnnouncements(id);
      if (session != _session) return;
      final fromServer = parseAnnouncements(data['items']);
      // Подтверждённые сервером и пропавшие из списка — больше не держим
      // ([pruneLocalReads]).
      pruneLocalReads(_readLocally, fromServer);
      _items = withLocalReads(fromServer, _readLocally);
      _fetchedAt = DateTime.now();
      _stale = false;
      _save(scope);
      _publish();
      _schedule(announcementRefreshDelay(
        DateTime.tryParse('${data['next_change_at'] ?? ''}'),
        DateTime.now(),
      ));
    } catch (error) {
      if (session != _session) return;
      _stale = true;
      // Срок показа мог выйти, пока нет связи, — пересчитываем видимое.
      _publish();
      // Область доступа поменялась посреди загрузки — сервер просит
      // перечитать позже.
      if (error is ServerFailureException && error.statusCode == 409) {
        _schedule(const Duration(seconds: 3));
      }
      debugPrint('Failed to load announcements: $error');
    }
  }

  void _schedule(Duration? delay) {
    _timer?.cancel();
    _timer = delay == null ? null : Timer(delay, () => unawaited(refresh()));
  }

  void _save(({String user, String server}) scope) {
    unawaited(GlobalState.dataProvider.stringBox.put(
      announcementsCacheKey(scope.user, scope.server),
      jsonEncode([for (final a in _items) a.toJson()]),
    ));
  }

  void _persistReads() {
    final scope = _scope;
    if (scope == null) return;
    final box = GlobalState.dataProvider.stringBox;
    final key = announcementReadsKey(scope.user, scope.server);
    unawaited(_pendingRead.isEmpty
        ? box.delete(key)
        : box.put(key, jsonEncode(_pendingRead.toList())));
  }

  /// Когда показали отладочное объявление и когда его «прочитали» — только
  /// в памяти ([previewReleaseAnnouncementEnabled]).
  DateTime? _previewShownAt;
  DateTime? _previewReadAt;

  void _publish() {
    final now = DateTime.now();
    final shown = sortAnnouncements([
      for (final a in visibleAnnouncements(_items, now))
        _pendingRead.contains(a.uuid) ? a.markedRead(now) : a,
      if (previewReleaseAnnouncementEnabled)
        previewReleaseAnnouncement(
          _previewShownAt ??= now,
          readAt: _previewReadAt,
        ),
    ]);
    current.value = shown;
    unreadCount.value = shown.where((a) => !a.isRead).length;
    // Ближайшая граница показа — пересчитать видимость, даже без связи:
    // таймер перечитки с сервера ставится только после удачной загрузки.
    _boundaryTimer?.cancel();
    final delay = announcementRefreshDelay(
      nextVisibilityBoundary(_items, now),
      now,
    );
    _boundaryTimer = delay == null ? null : Timer(delay, _publish);
  }

  /// Отмечает объявление прочитанным: на экране — сразу, на сервере — следом.
  /// Не дошла — повторится при следующей перечитке.
  Future<void> markRead(String uuid) async {
    if (!GlobalState.isAuthorized) return;
    // Отладочное объявление сервер не знает — «прочитано» только на экране.
    if (uuid == previewReleaseAnnouncementUuid) {
      _previewReadAt ??= DateTime.now();
      _publish();
      return;
    }
    final index = _items.indexWhere((a) => a.uuid == uuid);
    if (index < 0 || _items[index].isRead) return;
    final now = DateTime.now();
    _items = [..._items]..[index] = _items[index].markedRead(now);
    _readLocally[uuid] = now;
    if (_pendingRead.add(uuid)) _persistReads();
    final scope = _scope;
    if (scope != null) _save(scope);
    _publish();
    final id = GlobalState.dataProvider.installationHeaderId;
    if (id != null) await _flushReads(id, _session);
  }

  bool _flushing = false;

  Future<void> _flushReads(String installationId, int session) async {
    if (_pendingRead.isEmpty || _flushing) return;
    _flushing = true;
    try {
      for (final uuid in _pendingRead.toList()) {
        if (session != _session) return;
        try {
          await _api.markAnnouncementRead(installationId, uuid);
        } catch (error) {
          if (session != _session) return;
          // Нет связи или сбой сервера — остальные ждали бы того же.
          if (_isRetryable(error)) return;
          // Отказ по существу (объявления больше нет — 404): повтор даст то
          // же, отметку убираем.
        }
        if (session != _session) return;
        _pendingRead.remove(uuid);
        _persistReads();
      }
    } finally {
      _flushing = false;
    }
  }

  static bool _isRetryable(Object e) =>
      e is TimeoutException ||
      e is AuthExpiredException ||
      isOfflineError(e) ||
      (e is ServerFailureException && e.isTransient);

  /// Выход: список и очередь — того, кто вышел; на диске они остаются и
  /// вернутся при его следующем входе.
  void onLogout() {
    _session++;
    _timer?.cancel();
    _timer = null;
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    _readLocally.clear();
    _items = const [];
    _pendingRead.clear();
    _fetchedAt = null;
    _stale = true;
    _loaded = false;
    current.value = const [];
    unreadCount.value = 0;
  }
}
