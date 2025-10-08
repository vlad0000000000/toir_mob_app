import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
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
  }

  static User? get authUser {
    return dataProvider.userBox.get('auth_user');
  }

  static bool get isAuthorized {
    return dataProvider.userBox.get('auth_user') != null;
  }

  static bool needTasksSync = false;

  static Future<void> syncTasks() async {
    if (needTasksSync) {
      await dataProvider.syncTasks();
      needTasksSync = false;
    }
  }

  static int get now => (DateTime.now().millisecondsSinceEpoch / 1000).round();

  static ValueNotifier<String> debug = ValueNotifier('');

  // static Future<bool> get hasConnectionToNetwork async {
  //   final connectivityResult = await Connectivity().checkConnectivity();
  //   if (connectivityResult != ConnectivityResult.none) {
  //     return true;
  //   }
  //   return false;
  // }

  static Future<void> updateDebugInventory() async {
    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingChecks = dataProvider.scanBox.values.length.toString();
    String db =
        "Локальные данные: (активы: ${dataProvider.inventoryRecords.length.toString()}, осмотры: ${pendingChecks})";
    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.username;
    }

    try {
      await dataProvider.syncCurrentSession();
    } catch (_) {}
    String sessionStatus = 'завершена';
    if (dataProvider.currentSession != null &&
        dataProvider.currentSession!.isActive()) {
      // Then somewhere in your code:
      String date = await initializeDateFormatting('ru_RU', null).then((_) {
        final dateTime =
            DateTime.parse(dataProvider.currentSession!.startTime + 'Z')
                .toLocal();
        return DateFormat('dd MMMM yyyy в HH:mm', 'ru_RU').format(dateTime);
      });
      sessionStatus = 'активна (от ' + date + ')';
    }

    GlobalState.debug.value =
        "Сервер: ${serverAccess}  |  ${db}\nПользователь: ${loggedUser}  |  Инвентаризация: ${sessionStatus}";
  }

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
    String pendingChecks = dataProvider.scanBox.length.toString();
    // String problems = dataProvider.typicalProblemBox.length.toString();
    String inventory = dataProvider.inventoryRecords.length.toString();

    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.username;
    }

    var lastSyncDate = dataProvider.getLastSyncDate();

    return """
## Информация

- **Сервер**: ${serverAccess}
- **Осмотров не отправлено**: ${pendingChecks}
- **ТМЦ/Обрудование**: ${inventory}
- **Пользователь**: ${loggedUser}
- **Дата последней синхронизации**: ${lastSyncDate}
---

- **appName**: ${appName}
- **packageName**: ${packageName}
- **version**: ${version}
- **buildNumber**: ${buildNumber}
    """;
  }

  static Future<void> updateDebug() async {
    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingChecks = dataProvider.scanBox.length.toString();
    String problems = dataProvider.typicalProblemBox.length.toString();
    String inventory = dataProvider.inventoryRecords.length.toString();
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
