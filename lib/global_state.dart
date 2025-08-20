import 'dart:async';
import 'dart:convert';

// import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/src/data/data_provider.dart';
import 'package:qr_machine_scanner/src/http/api.dart';
import 'package:qr_machine_scanner/src/model/user.dart';
import 'package:crypto/crypto.dart';

class GlobalState {
  static late DataProvider dataProvider;

  static late Box<User> loginBox;

  static String digest(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static set authUser(User? user) {
    if (user == null) {
      // loginBox.put('auth_user', User(passwordHash: '-', id: 0, login: ''));
      loginBox.clear();
    } else {
      loginBox.put('auth_user', user);
    }
  }

  static User? get authUser {
    return loginBox.get('auth_user');
  }

  static bool get isAuthorized {
    return loginBox.get('auth_user') != null;
  }

  static bool needTasksSync = false;

  static Future<void> syncTasks() async {
    if (needTasksSync) {
      await dataProvider.syncTasks();
      needTasksSync = false;
    }
  }

  static bool needTaskSync = false;

  static Future<void> syncTask(int machineId) async {
    if (needTaskSync) {
      await dataProvider.syncTasksForMachine(machineId);
      needTaskSync = false;
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

  static Future<void> updateDebug() async {
    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingChecks =
        dataProvider.machineCheckBox.values.length.toString();
    String db =
        "Локальные данные: (оборудование: ${dataProvider.machines.length.toString()}, пользователи: ${dataProvider.users.length.toString()}, осмотры: ${pendingChecks})";
    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.login;
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
}
