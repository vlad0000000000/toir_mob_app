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

class Settings {
  static late DataProvider dataProvider;

  static set qrResultShowTasksFirst(bool value) {
    dataProvider.stringBox.put('qrResultShowTasksFirst', value ? "1" : "0");
  }

  static bool get qrResultShowTasksFirst {
    var v = dataProvider.stringBox.get('qrResultShowTasksFirst');
    return v != null && v == "1";
  }

  static set qrResultShowSimplifiedView(bool value) {
    dataProvider.stringBox.put('qrResultShowSimplifiedView', value ? "1" : "0");
  }

  static bool get qrResultShowSimplifiedView {
    var v = dataProvider.stringBox.get('qrResultShowSimplifiedView');
    return v != null && v == "1";
  }
}
