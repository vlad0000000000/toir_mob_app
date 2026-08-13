part of 'data_provider.dart';

/// Сетевые загрузки и авторизация (через [API]).
extension DataProviderRemote on DataProvider {
  Future<List<InventoryRecord>> loadAllInventory() async {
    int limit = 100;
    int offset = 0;
    List<InventoryRecord> all = [];
    while (true) {
      List<InventoryRecord> notAll =
          // await api.getInventoryRecords(limit: limit, offset: offset);
          await api.getEquipment(limit: limit, offset: offset);
      for (var inventoryRecord in notAll) {
        all.add(inventoryRecord);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
    }
    return all;
  }

  Future<List<TypicalProblem>> loadAllTypicalProblems() async {
    // 100 — верхний предел сервера. По 50 выходило вдвое больше запросов на
    // тот же объём.
    int limit = 100;
    int offset = 0;
    List<TypicalProblem> all = [];
    while (true) {
      List<TypicalProblem> notAll =
          await api.getTypicalProblems(limit: limit, offset: offset);
      for (var typicalProblem in notAll) {
        all.add(typicalProblem);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
    }
    return all;
  }

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
    }
    return all;
  }

  /// Все активные ремонты обходчика. Сервер сам сужает выдачу по
  /// ответственному и должности, дополнительный фильтр не нужен.
  Future<List<Repair>> loadAllActiveRepairs() async {
    int limit = 100;
    int offset = 0;
    List<Repair> all = [];
    while (true) {
      List<Repair> notAll = await api.getRepairs(
        statuses: [RepairStatuses.open, RepairStatuses.underReview],
        limit: limit,
        offset: offset,
      );
      for (var repair in notAll) {
        all.add(repair);
      }
      // Выходим на неполной странице, а не на пустой: иначе цикл всегда
      // делает ещё один — заведомо пустой — запрос просто чтобы узнать, что
      // данные кончились. На шести справочниках это шесть лишних round-trip
      // за каждую синхронизацию.
      if (notAll.length < limit) {
        break;
      }
      offset += limit;
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

  Future<List<Task>> loadAllOpenTasks() async {
    // 100 — верхний предел сервера. По 50 выходило вдвое больше запросов на
    // тот же объём.
    int limit = 100;
    int offset = 0;
    List<Task> all = [];
    while (true) {
      List<Task> notAll =
          await api.getCurrentOpenTasks(limit: limit, offset: offset);
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
    }
    return all;
  }

  Future<User?> login(login, password) async {
    User? currentUser = null;
    bool apiLoginFailed = false;

    try {
      currentUser = await api.login(login, password);
      final currentUserMe = await api.me(currentUser.JWTToken);
      currentUser.effectiveRole = currentUserMe.effectiveRole;
      currentUser.customRoleId = currentUserMe.customRoleId;
      currentUser.uuid = currentUserMe.uuid;
    } on InvalidCredentialsException {
      // Сервер вернул, что учетные данные неверны - не проверяем локальных пользователей
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
    }

    // Проверка на роль walker должна быть после успешного логина
    if (currentUser != null) {
      // only walkers allowed
      if (currentUser.role != 'walker') {
        throw WalkerOnlyException();
      }
    }

    if (currentUser != null) {
      // Сохраняем данные логина только при успешном завершении
      await addUser(currentUser);
      GlobalState.authUser = currentUser;
    }
    return currentUser;
  }
}
