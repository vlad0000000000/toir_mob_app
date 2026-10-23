part of 'data_provider.dart';

/// Предохранитель постраничных загрузок.
///
/// Все циклы ниже выходят по неполной странице. Если сервер начнёт отдавать
/// ровно `limit` записей на каждый запрос — например перестанет учитывать
/// `skip` из-за ошибки в фильтрах, — выхода не будет: цикл продолжит копить
/// ответы в памяти, пока приложение не убьют, и со стороны это выглядит как
/// бесконечная синхронизация без единой ошибки в логе.
///
/// Порог заведомо выше любого реального справочника: он не ограничивает
/// загрузку, а только не даёт зациклиться.
const int _maxPagedItems = 100000;

/// Обрывает загрузку **ошибкой**, если порог достигнут.
///
/// Именно ошибкой, а не тихой остановкой цикла: раньше он просто выходил, и
/// неполная выгрузка дальше записывалась как полная — справочник целиком
/// заменялся урезанным, а у инкрементальных ещё и сдвигалась граница окна,
/// так что недогруженное не пришло бы уже никогда. Ошибку ловит вызывающий
/// `sync*` — и тогда не пишет ничего: остаётся прошлый снимок и прежняя
/// граница, следующий проход повторит окно. Пишет в лог: молчаливый обрыв
/// загрузки диагностировать невозможно.
void _guardPagingLimit(int loaded) {
  if (loaded < _maxPagedItems) return;
  _dataLog.severe('Paging guard: загрузка прервана на $loaded записях — '
      'похоже, сервер не учитывает skip');
  throw StateError('Paging guard: $loaded записей');
}

/// Сетевые загрузки и авторизация (через [API]).
extension DataProviderRemote on DataProvider {
  Future<List<SparePart>> loadAllSpareParts() async {
    int limit = 100;
    int offset = 0;
    List<SparePart> all = [];
    while (true) {
      List<SparePart> notAll =
          await api.getSpareParts(limit: limit, offset: offset);
      for (var sparePart in notAll) {
        all.add(sparePart);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
      _guardPagingLimit(offset);
    }
    return all;
  }

  Future<List<PeriodicityRule>> loadAllPeriodicityRules() async {
    List<PeriodicityRule> all = [];
    List<PeriodicityRule> notAll = await api.getPeriodicityRules();
    for (var periodicityRule in notAll) {
      all.add(periodicityRule);
    }
    return all;
  }

  Future<List<UsageUnit>> loadAllUsageUnitTypes() async {
    List<UsageUnit> all = [];
    List<UsageUnit> notAll = await api.getUsageUnitTypes();
    for (var usageUnit in notAll) {
      all.add(usageUnit);
    }
    return all;
  }

  /// Открытые задачи обходчика обоих видов назначения — где он ответственный
  /// и где исполнитель (см. [TaskApi.getCurrentOpenTasks]). Одна задача может
  /// попасть в оба списка — склеиваем по uuid.
  Future<List<Task>> loadAllOpenTasks() async {
    final byUuid = <String, Task>{};
    for (final byInspector in const [false, true]) {
      for (final task in await _loadOpenTasks(byInspector: byInspector)) {
        byUuid[task.uuid] = task;
      }
    }
    return byUuid.values.toList();
  }

  Future<List<Task>> _loadOpenTasks({required bool byInspector}) async {
    // 100 — верхний предел сервера. По 50 выходило вдвое больше запросов на
    // тот же объём.
    int limit = 100;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll = await api.getCurrentOpenTasks(
        limit: limit,
        offset: offset,
        byInspector: byInspector,
      );
      for (var task in notAll) {
        all.add(task);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
      _guardPagingLimit(offset);
    }
    return all;
  }

  Future<List<Task>> loadAllTasks() async {
    // 100 — верхний предел сервера. По 50 выходило вдвое больше запросов на
    // тот же объём.
    int limit = 100;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll =
          await api.getCurrentTasks(limit: limit, offset: offset);
      for (var task in notAll) {
        all.add(task);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
      _guardPagingLimit(offset);
    }
    return all;
  }

  Future<User?> login(login, password) async {
    User? currentUser = null;
    bool apiLoginFailed = false;

    try {
      // Онлайн-вход состоялся, только когда пришёл и `/user/me`: до него нет
      // ни uuid, ни профиля доступа. Поэтому ответ логина держим в своей
      // переменной и в [currentUser] кладём в самом конце. Раньше он попадал
      // туда сразу, и сбой `/me` (503, обрыв) пускал обходчика с пустым uuid
      // мимо всех проверок офлайн-входа — сохранённая блокировка роли не
      // проверялась, а локальная запись затиралась неполной. Теперь сбой
      // `/me` ведёт в обычный офлайн-вход со всеми проверками.
      final loggedIn = await api.login(login, password);
      final currentUserMe = await api.me(loggedIn.JWTToken);
      loggedIn.effectiveRole = currentUserMe.effectiveRole;
      loggedIn.customRoleId = currentUserMe.customRoleId;
      loggedIn.uuid = currentUserMe.uuid;
      loggedIn.companyId = currentUserMe.companyId;
      loggedIn.accessProfile = currentUserMe.accessProfile;
      // Роль доступа не назначена или отключена. Сервер пускает на вход и
      // отвечает на `/user/me`, но любой рабочий запрос получит 403 — не
      // пускаем сразу, с понятной причиной, как при истёкшем тарифе. Профиль
      // сохраняем: без него офлайн-вход пустил бы по локальной записи.
      //
      // Только обходчику: остальных ниже не пустит проверка типа учётной
      // записи, и причина «не обходчик» для них точнее.
      final profile = currentUserMe.accessProfile;
      final blockCode = profile?.blockCode;
      if (profile != null && blockCode != null && loggedIn.role == 'walker') {
        await saveAccessProfile(currentUserMe.uuid, profile);
        await rememberAccessBlock(currentUserMe.uuid, blockCode);
        throw NoBusinessAccessException(blockCode);
      }
      currentUser = loggedIn;
    } on InvalidCredentialsException {
      // Сервер вернул, что учетные данные неверны - не проверяем локальных пользователей
      rethrow;
    } on AccessBlockedException catch (e) {
      // Доступ закрыт: тариф или роль. Сервер ответил — значит, это не обрыв
      // связи, и пускать по локальной записи нельзя. Раньше этот ответ
      // попадал в общую ветку ниже и считался сбоем: обходчик входил «как
      // офлайн», а вся очередь потом получала 403. Тариф запоминаем на
      // компанию (роль уже записана в профиль выше) — офлайн-вход до
      // следующего удачного онлайн-входа тоже закрыт.
      if (e is SubscriptionBlockedException) {
        await subscriptionBlocks.block('$login', e.accessState);
      }
      rethrow;
    } on NoConnectionException {
      // Нет соединения с сервером - пробуем локальных пользователей
      apiLoginFailed = true;
    } on SocketException catch (_) {
      // Ошибка соединения с сервером - пробуем локальных пользователей
      apiLoginFailed = true;
    } on HttpException catch (_) {
      // Ошибка HTTP соединения - пробуем локальных пользователей
      apiLoginFailed = true;
    } on Exception catch (e) {
      // Сервер дошёл и отказал в данных пользователя (`/user/me`): учётную
      // запись отключили, токен не принят. Это не обрыв связи — по локальной
      // записи пускать нельзя. Сбой самого сервера (5xx) по-прежнему
      // считается недоступностью: проверить вход нечем, офлайн-вход уместен.
      if (e is AuthExpiredException ||
          (e is ServerFailureException && !e.isTransient)) {
        rethrow;
      }
      // Проверяем, не является ли это ошибкой соединения
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('Timeout')) {
        // Ошибка соединения - пробуем локальных пользователей
        apiLoginFailed = true;
      } else {
        // Для других исключений пробуем локальных пользователей
        apiLoginFailed = true;
      }
    }

    // Если API логин не удался из-за отсутствия соединения, пробуем локальных пользователей
    if (apiLoginFailed && currentUser == null) {
      // Последний ответ сервера для этого обходчика — «доступ компании
      // закрыт». Без связи проверить, продлили ли тариф, нельзя, а пустить по
      // локальной записи значило бы обойти блокировку, просто выключив сеть.
      final blockedState = subscriptionBlocks.isBlocked('$login');
      if (blockedState != null) {
        throw SubscriptionBlockedException(blockedState);
      }
      for (var user in users) {
        if (user.username == login && user.password == password) {
          currentUser = user;
          break;
        }
      }

      // Если не нашли локального пользователя, выбрасываем соответствующее исключение
      if (currentUser == null) {
        // Если была ошибка соединения, выбрасываем NoConnectionException
        // так как мы не можем проверить учетные данные на сервере
        throw NoConnectionException();
      }

      // Последний ответ сервера — «роль не назначена» или «роль отключена».
      // Как и с тарифом: без связи не проверить, вернули ли роль, а пустить
      // по локальной записи значило бы обойти блокировку, выключив сеть.
      final blockCode = storedAccessBlock(currentUser.uuid);
      if (blockCode != null && currentUser.role == 'walker') {
        throw NoBusinessAccessException(blockCode);
      }
    }

    // Проверка на роль walker должна быть после успешного логина
    if (currentUser != null) {
      // only walkers allowed
      if (currentUser.role != 'walker') {
        throw WalkerOnlyException();
      }
    }

    if (currentUser != null) {
      // Вошёл другой обходчик — выбрасываем кэш прошлого аккаунта до того,
      // как экраны его увидят, и до первой синхронизации: она должна
      // наполнять уже пустые боксы.
      //
      // Очереди отправки при этом остаются. В них лежит несделанная работа
      // прошлого обходчика, и молча стирать её при чужом входе нельзя.
      // Обратная сторона известна: пока очередь не разобрана, фоновый цикл
      // отправит её под токеном нового пользователя, и сервер запишет осмотры
      // на него. Правильное решение — не пускать чужие записи в отправку, а
      // не удалять их; сделано отдельной задачей.
      final switched = await ensureAccountScope(currentUser.uuid);
      if (switched) {
        _dataLog.info('Сменился аккаунт — кэш справочников сброшен');
      }

      // Онлайн-вход прошёл — сервер доступ подтвердил: запоминаем компанию
      // логина и снимаем блокировку всей компании (тариф продлили). При
      // офлайн-входе сюда приходим только без блокировки, снимать нечего.
      final companyId = currentUser.companyId;
      if (!apiLoginFailed && companyId != null) {
        await subscriptionBlocks.rememberCompany('$login', companyId);
        await subscriptionBlocks.clearCompany('$login', companyId);
      }
      // Новая сессия — с чистого листа: необработанный сигнал блокировки
      // прошлой сессии к ней не относится, а признак «эту сессию уже
      // обработали» сбрасываем — иначе вход того же пользователя в ту же
      // секунду (токен совпадёт: время в нём с точностью до секунды) оставил
      // бы следующую блокировку без реакции.
      pendingAccessNotice = null;
      _blockedSessionToken = null;
      // И ответы профиля, запрошенные прежней сессией, — тоже к ней: ни один
      // не должен лечь поверх профиля, который вход сохранит ниже, даже при
      // совпавшем токене. Сеттер `GlobalState.authUser` сдвинет номер ещё
      // раз, но позже — уже после сохранения.
      startAccessSession();

      // Свежий профиль доступа — до смены пользователя: сеттер
      // `GlobalState.authUser` берёт его отсюда. Офлайн-вход профиль не
      // трогает, остаётся последний известный.
      // Сервер пустил онлайн — запомненная блокировка роли больше не
      // действует (роль вернули).
      if (!apiLoginFailed) await clearAccessBlock(currentUser.uuid);
      final freshProfile = currentUser.accessProfile;
      if (!apiLoginFailed && freshProfile != null) {
        final before = storedAccessProfile(currentUser.uuid);
        await saveAccessProfile(currentUser.uuid, freshProfile);
        // Доступ поменялся с прошлого входа — отклонённое за «нет прав»
        // пробуем отправить заново; фоновая синхронизация этого уже не
        // заметит: она сравнит со свежесохранённым.
        if (before != null &&
            before.accessVersion != freshProfile.accessVersion) {
          await retryNoRightsRejections();
        }
      }

      // Сохраняем данные логина только при успешном завершении
      await addUser(currentUser);
      GlobalState.authUser = currentUser;
    }
    return currentUser;
  }
}
