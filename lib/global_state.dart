import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  static int get now => (DateTime.now().millisecondsSinceEpoch / 1000).round();

  static ValueNotifier<String> debug = ValueNotifier('');

  static Future<bool> get hasConnectionToNetwork async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      return true;
    }
    return false;
  }

  static Future<void> updateDebug() async {

    String serverAccess = "доступен";
    if (!(await GlobalState.hasConnectionToServer)) {
      serverAccess = "не доступен";
    }
    String pendingChecks =
        dataProvider.machineCheckBox.values.length.toString();
    String db = "Локальные данные: (станки: ${dataProvider.machines.length.toString()}, пользователи: ${dataProvider.users.length.toString()}, осмотры: ${pendingChecks})";
    String loggedUser = "";
    if (GlobalState.isAuthorized) {
      loggedUser = GlobalState.authUser!.login;
    }

    GlobalState.debug.value =
        "Сервер: ${serverAccess}  |  ${db}   |  Пользователь: ${loggedUser}";
  }

  static Future<bool> get hasConnectionToServer async {
    return API().isAlive();
  }
}
