import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../src/data/data_provider.dart';
import '../../src/http/api.dart';
import '../../src/model/user.dart';

class GlobalState {
  static late DataProvider dataProvider;

  static String digest(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static set authUser(User? user) {
    if (user == null) {
      dataProvider.userBox.delete('auth_user');
    } else {
      dataProvider.userBox.put('auth_user', user);
    }
    // Вход или выход снимает пометку «сессия истекла»: очередь поднимет её
    // снова, если новый токен окажется таким же негодным.
    dataProvider.authExpired.value = false;
  }

  static User? get authUser {
    return dataProvider.userBox.get('auth_user');
  }

  static bool get isAuthorized {
    return dataProvider.userBox.get('auth_user') != null;
  }

  static bool allowSyncMainOnce = false;

  static Future<void> syncMainOnce() async {
    if (allowSyncMainOnce) {
      await dataProvider.mainSync();
      allowSyncMainOnce = false;
    }
  }

  static int get nowLocal =>
      (DateTime.now().millisecondsSinceEpoch / 1000).round();

  static int get nowUTC =>
      (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

  static String get nowUTCDate => DateTime.now().toUtc().toIso8601String();

  static String get nowLocalDate => DateTime.now().toIso8601String();

  static ValueNotifier<String> debug = ValueNotifier('');

  // static Future<bool> get hasConnectionToNetwork async {
  //   final connectivityResult = await Connectivity().checkConnectivity();
  //   if (connectivityResult != ConnectivityResult.none) {
  //     return true;
  //   }
  //   return false;
  // }

  static Future<String> buildInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    String appName = packageInfo.appName;
    String packageName = packageInfo.packageName;
    String version = packageInfo.version;
    String buildNumber = packageInfo.buildNumber;

    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingScans =
        (dataProvider.scanBox.length + dataProvider.scanPendingBox.length)
            .toString();
    String pendingUsageUpdates = dataProvider.scanUsageBox.length.toString();
    // String problems = dataProvider.typicalProblemBox.length.toString();
    String inventory = dataProvider.inventoryRecords.length.toString();

    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.username;
    }

    var lastSyncDate = dataProvider.getLastSyncDate();

    // Ремонты: черновики создания и неотправленные правки. Очередь работает в
    // фоне, поэтому «Сервис» — единственное место, где видно её состояние
    // целиком, включая истёкший токен.
    String pendingRepairs = dataProvider.pendingRepairBox.length.toString();
    String pendingRepairEdits =
        dataProvider.pendingRepairUpdateBox.length.toString();
    String authState = dataProvider.authExpired.value
        ? "сессия истекла, нужно войти заново"
        : "в порядке";

    return """
## Информация

- **Сервер**: ${serverAccess}
- **Осмотров не отправлено**: ${pendingScans}
- **Наработок не отправлено**: ${pendingUsageUpdates}
- **Ремонтов не отправлено**: ${pendingRepairs}
- **Правок ремонтов не отправлено**: ${pendingRepairEdits}
- **Авторизация**: ${authState}
- **ТМЦ/Оборудование**: ${inventory}
- **Пользователь**: ${loggedUser}
- **Дата последней синхронизации**: ${lastSyncDate}

---

- **appName**: ${appName}
- **packageName**: ${packageName}
- **version**: ${version}
- **buildNumber**: ${buildNumber}

---

- **Time UTC**: ${nowUTCDate}
- **Time local**: ${DateTime.now().toIso8601String()}

    """;
  }

  static Future<void> updateDebug() async {
    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingChecks =
        (dataProvider.scanBox.length + dataProvider.scanPendingBox.length)
            .toString();
    // String db =
    //     "Локальные данные: (оборудование: ${dataProvider.inventoryBox.length.toString()}, пользователи: ${dataProvider.users.length.toString()}, осмотры: ${pendingChecks}, проблемы: ${problems})";
    String db = "Осмотров не отправлено: ${pendingChecks}";

    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.username;
    }

    GlobalState.debug.value =
        "Сервер: ${serverAccess}  |  ${db}  |  Пользователь: ${loggedUser}";
  }

  static bool? _cachedResult;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(seconds: 10);

  static Future<bool> get hasConnectionToServer async {
    // Имитация офлайна — отвечаем мгновенно, минуя кэш
    if (API.simulateOffline) {
      return false;
    }
    // Проверяем, есть ли актуальный кэш
    if (_cachedResult != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedResult!;
      }
    }

    // Если кэш устарел или отсутствует — делаем запрос
    final result = await API().isAlive();

    // Обновляем кэш
    _cachedResult = result;
    _cacheTime = DateTime.now();

    return result;
  }

  static Future<bool> get hasConnectionToServer2 async {
    return API().isAlive();
  }
}
