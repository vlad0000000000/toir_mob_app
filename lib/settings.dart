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

  static set onboardingCompleted(bool value) {
    dataProvider.stringBox.put('onboardingCompleted', value ? "1" : "0");
  }

  static bool get onboardingCompleted {
    var v = dataProvider.stringBox.get('onboardingCompleted');
    return v != null && v == "1";
  }

  static set onboardingInProgress(bool value) {
    dataProvider.stringBox.put('onboardingInProgress', value ? "1" : "0");
  }

  static bool get onboardingInProgress {
    var v = dataProvider.stringBox.get('onboardingInProgress');
    return v != null && v == "1";
  }

  static set onboardingStep(int value) {
    dataProvider.stringBox.put('onboardingStep', value.toString());
  }

  static int get onboardingStep {
    var v = dataProvider.stringBox.get('onboardingStep');
    return v != null ? int.tryParse(v) ?? 0 : 0;
  }

  static void resetOnboarding() {
    onboardingCompleted = false;
    onboardingInProgress = false;
    onboardingStep = 0;
  }
}
