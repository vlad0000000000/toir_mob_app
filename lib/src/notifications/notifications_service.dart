import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../global_state.dart';
// Импорт нужен ради `syncMyRepairs`: метод объявлен в extension
// `DataProviderSync`, а extension-методы видны только при прямом импорте
// библиотеки, где они объявлены, — через `global_state.dart` не подтягиваются.
import '../data/data_provider.dart';
import '../exceptions/app_exceptions.dart';
import '../http/api.dart';
import '../model/notification.dart';
import '../model/notification_settings.dart';
import '../utils/offline_error.dart';
import 'push/push_notifications_controller.dart';
import 'sse_line_parser.dart';

class NotificationsService {
  NotificationsService._();

  static final NotificationsService instance = NotificationsService._();

  static const int pageSize = 30;

  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final ValueNotifier<NotificationSettings> settings =
      ValueNotifier<NotificationSettings>(NotificationSettings.defaults());
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLoadingMore = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hasMore = ValueNotifier<bool>(true);

  /// `true` после того, как первый refreshList завершился (успешно или с
  /// ошибкой). Нужен экрану: пока false — показывает spinner, не EmptyState,
  /// иначе на холодном старте мелькает «Уведомлений пока нет», пока ответ
  /// сервера ещё в полёте.
  final ValueNotifier<bool> hasLoadedOnce = ValueNotifier<bool>(false);

  final API _api = API();

  StreamedResponseHandle? _streamHandle;
  StreamSubscription<String>? _streamSubscription;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  DateTime _lastSseActivity = DateTime.now();
  static const Duration _silentDropThreshold = Duration(minutes: 3);
  static const Duration _keepaliveCheckInterval = Duration(seconds: 60);

  bool _disposed = false;

  /// Координация перечитываний списка. Список перечитывают сразу несколько
  /// источников: in-app SSE, foreground-сервис (через sendDataToMain),
  /// pull-to-refresh, апдейт настроек. Без сериализации параллельные
  /// `GET /mobile` завершаются в произвольном порядке, и последний
  /// долетевший ответ перетирает актуальный → счётчик «N новых» скачет и
  /// список «прыгает». [_refreshInFlight] не даёт запускать одновременные
  /// запросы (повторный триггер просто ставит [_refreshQueued]), а
  /// [_refreshSeq] позволяет [markRead] аннулировать уже летящий ответ,
  /// чтобы он не вернул только что прочитанное обратно в «непрочитано».
  int _refreshSeq = 0;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  /// UUID'ы, помеченные прочитанными локально (по тапу), но которые сервер
  /// мог ещё не успеть отразить в `GET /mobile` (реплика/кэш отстают на
  /// доли секунды). Пока сервер не подтвердит `is_read = true`, мы
  /// реконсилим его ответ: держим элемент прочитанным и не считаем его в
  /// `unread_count`. Иначе перечитывание, прилетевшее сразу после markRead
  /// (его триггерит SSE-upsert от самой же пометки), вернуло бы прежний
  /// счётчик — «N новых» подскакивал вверх и тут же возвращался к верному.
  final Set<String> _locallyRead = <String>{};

  Future<void> bootstrap() async {
    _disposed = false;
    _attachForegroundListener();
    // Недошедшие отметки прошлых запусков этого пользователя — досылка в
    // первом же refreshList ниже.
    _restorePendingReads();
    // Сразу включаем флаг загрузки — иначе первая отрисовка экрана видит
    // isLoading=false + пустой список и моргает EmptyState'ом до того, как
    // запрос успеет долететь до сервера.
    isLoading.value = true;
    try {
      final s = await _api.getNotificationSettings();
      settings.value = s;
    } catch (e) {
      debugPrint('Failed to load notification settings: $e');
    }
    await refreshList();
    if (settings.value.realtimeEnabled && settings.value.notificationsEnabled) {
      _connectStream();
    }
  }

  void _attachForegroundListener() {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_foregroundAttached) return;
    _foregroundAttached = true;
    FlutterForegroundTask.addTaskDataCallback(_onForegroundData);
  }

  void _detachForegroundListener() {
    if (!_foregroundAttached) return;
    _foregroundAttached = false;
    try {
      FlutterForegroundTask.removeTaskDataCallback(_onForegroundData);
    } catch (_) {}
  }

  bool _foregroundAttached = false;

  void _onForegroundData(Object data) {
    if (data is Map && data['type'] == 'sse_event') {
      refreshList();
    }
    if (data is Map && data['type'] == 'repair_changed') {
      _syncRepairsOnSignal();
    }
    // Тот же сигнал «доступ изменился», пойманный потоком foreground-сервиса:
    // когда приложение открыто, его поток в главном изоляте может быть и не
    // поднят.
    if (data is Map && data['type'] == 'access_changed') {
      if (GlobalState.isAuthorized) GlobalState.dataProvider.refreshAccess();
      refreshList();
    }
    // Тап по пушу (`type == 'push_tap'`) обрабатывается отдельной
    // подпиской в PushNotificationRouter — независимо от того, был ли
    // позван bootstrap.
  }

  Future<void> refreshList() async {
    if (!GlobalState.isAuthorized) return;
    // Уже идёт перечитывание — не плодим параллельные запросы. Помечаем, что
    // нужно ещё раз, и текущий цикл перезапросит сам после завершения.
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    isLoading.value = true;
    try {
      do {
        _refreshQueued = false;
        // Ошибка — на круг, а не на весь цикл. Раньше `catch` стоял снаружи,
        // и сбой одного круга (503 от запроса прошлого аккаунта, обрыв связи)
        // выбрасывал из цикла: перечитывание, вставшее в [_refreshQueued],
        // пока круг шёл, терялось, и список нового пользователя оставался
        // пустым до следующего события.
        try {
          await _refreshOnce();
        } catch (e) {
          debugPrint('Failed to load notifications: $e');
        }
      } while (_refreshQueued);
    } finally {
      _refreshInFlight = false;
      isLoading.value = false;
      hasLoadedOnce.value = true;
    }
  }

  /// Один круг [refreshList]: досылка отметок и перечитывание первой
  /// страницы.
  Future<void> _refreshOnce() async {
    // Сессия — на каждый круг. Вышел пользователь, пока круг шёл, — его
    // результат отбрасываем: `onLogout` только что очистил список и
    // счётчик, и ответ прошлого аккаунта вернул бы их. Перечитывание
    // нового пользователя при этом не теряется: оно уже стоит в
    // [_refreshQueued] и пойдёт следующим кругом, со своей сессией.
    final session = _readSession;
    // Сначала досылаем недошедшие отметки — тогда список и счётчик
    // придут уже с ними.
    await _flushPendingReads(session);
    if (session != _readSession) return;
    final seq = ++_refreshSeq;
    // Сохраняем уже загруженный объём: realtime-перечитывание не должно
    // схлопывать пролистанный список обратно к первой странице.
    // Сервер ограничивает limit сотней (см. api.md §7.1) — не превышаем.
    final loaded = notifications.value.length;
    final wanted =
        loaded <= pageSize ? pageSize : (loaded > 100 ? 100 : loaded);
    final result = await _api.getNotifications(skip: 0, limit: wanted);
    if (session != _readSession) return;
    // markRead() во время полёта запроса инкрементит _refreshSeq — значит
    // наш снапшот уже устарел и его применять нельзя (иначе вернём
    // прочитанное обратно в «непрочитано»).
    if (seq != _refreshSeq) {
      // Отбросить мало — нужен свежий ответ, иначе на первой загрузке список
      // так и остался бы пустым. Перезапрашиваем следующим кругом: он уже
      // учтёт отметку, а [_locallyRead] удержит карточку прочитанной.
      _refreshQueued = true;
      return;
    }
    var items = result.items;
    var unread = result.unreadCount;
    // Реконсиляция со свежими локальными пометками — см. [_locallyRead].
    if (_locallyRead.isNotEmpty) {
      final out = <AppNotification>[];
      for (final n in items) {
        if (_locallyRead.contains(n.uuid)) {
          if (n.isRead) {
            // Сервер догнал — снимаем локальную пометку.
            _locallyRead.remove(n.uuid);
            out.add(n);
          } else {
            // Сервер ещё отдаёт элемент непрочитанным — держим свою
            // пометку и не учитываем его в счётчике.
            unread = unread > 0 ? unread - 1 : 0;
            out.add(_asRead(n));
          }
        } else {
          out.add(n);
        }
      }
      items = out;
    }
    notifications.value = _sortNotifications(items);
    unreadCount.value = unread;
    hasMore.value = result.items.length >= wanted;
  }

  Future<void> loadMore() async {
    if (!GlobalState.isAuthorized) return;
    if (isLoadingMore.value || isLoading.value) return;
    if (!hasMore.value) return;
    isLoadingMore.value = true;
    // Как и у [refreshList]: страница, запрошенная до выхода, не должна лечь
    // в список следующего пользователя.
    final session = _readSession;
    try {
      final result = await _api.getNotifications(
        skip: notifications.value.length,
        limit: pageSize,
      );
      if (session != _readSession) return;
      if (result.items.isEmpty) {
        hasMore.value = false;
      } else {
        final existing = notifications.value;
        final existingUuids = existing.map((e) => e.uuid).toSet();
        final newOnes = result.items
            .where((e) => !existingUuids.contains(e.uuid))
            .map((e) =>
                _locallyRead.contains(e.uuid) && !e.isRead ? _asRead(e) : e)
            .toList();
        final merged = [...existing, ...newOnes];
        notifications.value = _sortNotifications(merged);
        // НЕ трогаем unreadCount: пагинация подгружает старые элементы и не
        // меняет общее число непрочитанных. Авторитетные источники счётчика —
        // refreshList (полное перечитывание по SSE) и markRead (дельта с
        // сервера). Иначе ответ loadMore, долетевший после markRead, вернул бы
        // прежний (больший) счётчик → «N новых» скачет вверх.
        hasMore.value = result.items.length >= pageSize;
      }
    } catch (e) {
      debugPrint('Failed to load more notifications: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  List<AppNotification> _sortNotifications(List<AppNotification> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final byCreated = b.createdAt.compareTo(a.createdAt);
      if (byCreated != 0) return byCreated;
      // Тай-брейк по uuid: при совпадающем createdAt (пачка/сводка приходят
      // одним timestamp) сортировка Dart нестабильна и переставляет равные
      // элементы на каждом пере-сорте — карточки «прыгают», прочитанные то
      // выше, то ниже. Детерминированный ключ это убирает.
      return a.uuid.compareTo(b.uuid);
    });
    return sorted;
  }

  /// Отметки прочтения, которые не дошли до сервера из-за связи или его
  /// временного сбоя. Повторяются при следующем перечитывании списка
  /// ([refreshList]): его запускают открытие экрана, «потянуть вниз», поток
  /// событий и вход, — и сразу после любой дошедшей отметки.
  ///
  /// Раньше неудачная отметка просто терялась: карточка оставалась «Новой»
  /// и после повторного открытия, хотя обходчик её уже прочитал.
  ///
  /// Дублируется на диск ([_persistPendingReads]) под логином пользователя:
  /// закрой обходчик приложение до появления связи — отметки пропали бы.
  /// После выхода очередь в памяти очищается, а на диске остаётся и
  /// вернётся, когда войдёт тот же пользователь ([_restorePendingReads]).
  final Set<String> _pendingRead = <String>{};

  static const String _pendingReadKeyPrefix = 'notifications_pending_read:';

  /// Ключ очереди отметок текущего пользователя. `null` — никто не вошёл.
  String? get _pendingReadKey {
    final login = GlobalState.authUser?.username;
    return login == null || login.isEmpty
        ? null
        : '$_pendingReadKeyPrefix$login';
  }

  /// Поднимает с диска недошедшие отметки текущего пользователя. Они же —
  /// в [_locallyRead]: карточки должны выглядеть прочитанными сразу, ещё до
  /// досылки.
  void _restorePendingReads() {
    final key = _pendingReadKey;
    if (key == null) return;
    final raw = GlobalState.dataProvider.stringBox.get(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return;
      for (final item in data) {
        if (item is String && item.isNotEmpty) {
          _pendingRead.add(item);
          _locallyRead.add(item);
        }
      }
    } catch (_) {
      // Битая запись — отметки потеряны, но сервис работает дальше.
    }
  }

  /// Сохраняет очередь на диск. Зовётся только в своей сессии — после
  /// проверки [_readSession], поэтому ключ — того же пользователя.
  void _persistPendingReads() {
    final key = _pendingReadKey;
    if (key == null) return;
    final box = GlobalState.dataProvider.stringBox;
    unawaited(_pendingRead.isEmpty
        ? box.delete(key)
        : box.put(key, jsonEncode(_pendingRead.toList())));
  }

  bool _flushingReads = false;

  /// Номер сессии для отметок: растёт при выходе ([onLogout]). Отметка
  /// запоминает его перед отправкой, и результат запроса, завершившегося
  /// уже после выхода, отбрасывается. Иначе ошибка запоздавшего запроса
  /// вернула бы уведомление прошлого пользователя в очищенную очередь, и
  /// повтор ушёл бы с токеном следующего, а успешный ответ записал бы в
  /// счётчик число прошлого аккаунта.
  int _readSession = 0;

  /// Хвост очереди отметок: отправляются строго по одной. Параллельные
  /// ответы приходили в любом порядке, и запоздавший `unread_count = 1`
  /// перетирал свежий `0` — обе карточки прочитаны, а счётчик показывал
  /// одно новое.
  Future<void> _readTail = Future<void>.value();

  /// Отметок в очереди, включая отправляемую сейчас.
  int _readsQueued = 0;

  /// Отмечает уведомление прочитанным — по тапу в списке или по пушу.
  ///
  /// На экране — сразу, не дожидаясь сервера: тап не должен ждать сети, а
  /// без связи отметка иначе не появилась бы вовсе. Сервер получает её
  /// следом; не дошла — повторим (см. [_pendingRead]). `true` — сервер
  /// подтвердил.
  Future<bool> markRead(String uuid) async {
    // Без входа отмечать нечего и некому: уведомление принадлежало
    // вышедшему пользователю. И локально не помечаем — иначе карточка
    // выглядела бы прочитанной, а сервер об этом так и не узнал бы.
    if (!GlobalState.isAuthorized) return false;
    _markLocally(uuid);
    return await _sendRead(uuid) == true;
  }

  void _markLocally(String uuid) {
    // Запоминаем локальную пометку: refreshList, прилетевший до того как
    // сервер отразит чтение, не должен вернуть карточку в «непрочитано»
    // и подбросить счётчик. Снимется, когда сервер подтвердит is_read.
    _locallyRead.add(uuid);
    final items = notifications.value;
    final index = items.indexWhere((n) => n.uuid == uuid && !n.isRead);
    if (index >= 0) {
      notifications.value = [...items]..[index] = _asRead(items[index]);
      if (unreadCount.value > 0) unreadCount.value--;
    }
    // Аннулируем уже летящий refreshList (если он стартовал до пометки):
    // его устаревший снапшот вернул бы карточку обратно в «непрочитано» и
    // дёрнул бы счётчик вверх.
    _refreshSeq++;
  }

  /// Ставит отметку в очередь отправки ([_readTail]). `true` — принята,
  /// `false` — сервер отказал по существу (уведомления больше нет или оно
  /// вне области) и повторять незачем, либо пользователь за это время
  /// вышел; `null` — не дошла, оставлена в [_pendingRead].
  ///
  /// [session] — сессия, от имени которой отправляем; по умолчанию текущая.
  Future<bool?> _sendRead(String uuid, {int? session}) {
    final owner = session ?? _readSession;
    _readsQueued++;
    final previous = _readTail;
    final done = Completer<void>();
    _readTail = done.future;
    return previous.then((_) => _sendReadNow(uuid, owner)).whenComplete(() {
      _readsQueued--;
      done.complete();
    });
  }

  Future<bool?> _sendReadNow(String uuid, int session) async {
    // Встала в очередь до выхода — отправлять уже не от кого.
    if (session != _readSession) return false;
    try {
      final newUnread = await _api.markNotificationRead(uuid);
      if (session != _readSession) return false;
      if (_pendingRead.remove(uuid)) _persistPendingReads();
      // Число сервера учитывает все отметки, дошедшие до этой. Принимаем
      // его, только если за ней в очереди никого и недошедших нет: иначе
      // сервер ещё считает их непрочитанными, и счётчик подскочил бы. Своё,
      // уже уменьшенное, точное — с ближайшим перечитыванием.
      if (_readsQueued == 1 && _pendingRead.isEmpty) {
        unreadCount.value = newUnread;
      }
      _refreshSeq++;
      // Отметка дошла — связь есть: досылаем накопленные, не дожидаясь
      // обновления списка (без потока событий и захода в уведомления его
      // можно ждать долго). Идущий проход досылки сюда не попадёт —
      // [_flushPendingReads] не запускается дважды.
      if (_pendingRead.isNotEmpty) unawaited(_flushPendingReads(session));
      return true;
    } catch (e) {
      if (session != _readSession) return false;
      if (_isRetryableReadError(e)) {
        if (_pendingRead.add(uuid)) _persistPendingReads();
        debugPrint('Mark read deferred: $e');
        return null;
      }
      // Сервер ответил отказом — повтор дал бы то же. Локальную пометку
      // снимаем: перечитывание покажет, как есть на самом деле.
      if (_pendingRead.remove(uuid)) _persistPendingReads();
      _locallyRead.remove(uuid);
      debugPrint('Failed to mark read: $e');
      return false;
    }
  }

  /// Отметка не дошла, но дойдёт повтором: нет связи, таймаут, протух
  /// токен (после входа заново), временный сбой сервера.
  static bool _isRetryableReadError(Object e) =>
      e is TimeoutException ||
      e is AuthExpiredException ||
      isOfflineError(e) ||
      (e is ServerFailureException && e.isTransient);

  /// Досылает недошедшие отметки сессии [session]. Первая же недошедшая
  /// останавливает проход: связи, скорее всего, нет, и остальные ждали бы
  /// таймаута зря.
  ///
  /// Сессия — одна на весь проход, а не своя у каждой отправки: проход
  /// идёт по копии очереди, и если пользователь вышел, пока уходила первая
  /// отметка, следующая иначе запомнила бы уже новую сессию и ушла бы с
  /// токеном другого пользователя.
  Future<void> _flushPendingReads(int session) async {
    if (_pendingRead.isEmpty || _flushingReads) return;
    _flushingReads = true;
    try {
      for (final uuid in _pendingRead.toList()) {
        if (session != _readSession) break;
        if (await _sendRead(uuid, session: session) == null) break;
      }
    } finally {
      _flushingReads = false;
    }
  }

  /// Копия уведомления, помеченная прочитанной. Статус `new` → `viewed`
  /// (как у других прочитанных), прочие статусы сохраняются.
  AppNotification _asRead(AppNotification n) {
    return AppNotification(
      uuid: n.uuid,
      notificationType: n.notificationType,
      title: n.title,
      description: n.description,
      status: n.status == NotificationStatuses.newStatus
          ? NotificationStatuses.viewed
          : n.status,
      isRead: true,
      readAt: n.readAt ?? DateTime.now().toUtc(),
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
      priority: n.priority,
      priorityDisplay: n.priorityDisplay,
      equipmentUuid: n.equipmentUuid,
      equipmentName: n.equipmentName,
      inspectionUuid: n.inspectionUuid,
      responsibleUserUuid: n.responsibleUserUuid,
      responsibleUserFullname: n.responsibleUserFullname,
      targetScope: n.targetScope,
      canOpenTarget: n.canOpenTarget,
      payload: n.payload,
    );
  }

  Future<void> updateSettings(Map<String, dynamic> partial) async {
    try {
      final s = await _api.patchNotificationSettings(partial);
      settings.value = s;
      if (s.realtimeEnabled && s.notificationsEnabled) {
        _connectStream();
      } else {
        _disconnectStream();
      }
      await refreshList();
    } catch (e) {
      debugPrint('Failed to update settings: $e');
      rethrow;
    }
  }

  void _connectStream() {
    if (_streamHandle != null) return;
    _api.openNotificationStream().then((handle) {
      if (_disposed) {
        handle.close();
        return;
      }
      _streamHandle = handle;
      _lastSseActivity = DateTime.now();
      _ensureKeepalive();
      _streamSubscription = handle.response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _lastSseActivity = DateTime.now();
          _sseParser.handleLine(line, _dispatchSseEvent);
        },
        onError: (Object e) {
          debugPrint('SSE error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('SSE done');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    }).catchError((Object e) {
      debugPrint('Failed to open SSE: $e');
      _scheduleReconnect();
    });
  }

  /// Watchdog: SSE-сокет может «тихо умереть» — ни onError, ни onDone.
  /// Раз в минуту проверяем активность; если тихо больше 3 минут — рвём
  /// и переподключаемся. См. аналог в NotificationsTaskHandler.
  void _ensureKeepalive() {
    if (_keepaliveTimer != null) return;
    _keepaliveTimer = Timer.periodic(_keepaliveCheckInterval, (_) {
      if (_disposed) return;
      final silentFor = DateTime.now().difference(_lastSseActivity);
      if (silentFor > _silentDropThreshold) {
        debugPrint('SSE silent for ${silentFor.inSeconds}s — force reconnect');
        _scheduleReconnect();
      }
    });
  }

  final SseLineParser _sseParser = SseLineParser();

  void _dispatchSseEvent(String event, String dataStr) {
    if (event == 'ping') return;
    // `repair_changed` — технический сигнал «перечитай ремонты», а не запись в
    // центре уведомлений. Раньше сервер слал его под именем `notification`, и
    // он попадал сюда же; теперь у него собственное имя, и без этой ветки
    // сигнал терялся бы целиком.
    if (event == 'repair_changed') {
      _syncRepairsOnSignal();
      return;
    }
    if (event != 'notification') return;
    // Доступ обходчика поменяли: сервер шлёт `notification` с
    // `action: access_changed` и закрывает поток. Кроме центра уведомлений
    // (видимые уведомления тоже могли поменяться) перечитываем доступ и
    // справочники. Поток переподключится сам — уже с новой областью.
    if (_isAccessChanged(dataStr)) {
      GlobalState.dataProvider.refreshAccess();
    }
    refreshList();
  }

  /// Событие — «доступ изменился» (`action: access_changed`).
  static bool _isAccessChanged(String dataStr) {
    try {
      final data = jsonDecode(dataStr);
      return data is Map && data['action'] == 'access_changed';
    } catch (_) {
      return false;
    }
  }

  Timer? _repairSyncDebounce;

  /// SSE — только сигнал, источник правды REST (см.
  /// `docs/mobile_notifications_flow.md`), поэтому перечитываем список
  /// ремонтов целиком. Ошибку глушим: нет связи — фоновый цикл догонит через
  /// минуту.
  void _syncRepairsOnSignal() {
    if (!GlobalState.isAuthorized) return;
    // Сигнал рассылается всей компании и на каждое изменение ремонта. Правка
    // нескольких ремонтов в админке подряд — это очередь событий, и без
    // склейки телефон отправил бы столько же запросов списка. Секунды тишины
    // достаточно, чтобы серия схлопнулась в один.
    _repairSyncDebounce?.cancel();
    _repairSyncDebounce = Timer(const Duration(seconds: 1), () async {
      try {
        await GlobalState.dataProvider.syncMyRepairs();
      } catch (e) {
        debugPrint('Failed to sync repairs on SSE signal: $e');
      }
    });
  }

  void _scheduleReconnect() {
    _disconnectStream();
    if (_disposed) return;
    if (!settings.value.realtimeEnabled ||
        !settings.value.notificationsEnabled) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectStream();
    });
  }

  void _disconnectStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamHandle?.close();
    _streamHandle = null;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    // Иначе отложенная синхронизация сработала бы уже после выхода из учётной
    // записи — с чужим (или снятым) токеном.
    _repairSyncDebounce?.cancel();
    _repairSyncDebounce = null;
    _disconnectStream();
    _detachForegroundListener();
  }

  void onLogout() {
    dispose();
    notifications.value = const [];
    unreadCount.value = 0;
    _locallyRead.clear();
    // Недошедшие отметки — прошлого пользователя; новому они чужие. Запросы,
    // ещё летящие, свой результат отбросят — см. [_readSession]. На диске
    // очередь остаётся под его логином и вернётся при его входе.
    _pendingRead.clear();
    _readSession++;
    hasMore.value = true;
    settings.value = NotificationSettings.defaults();
    PushNotificationsController.instance.stop();
  }
}
