import 'package:flutter/material.dart';

import '../../strings.dart';

class Priority {
  final value;
  final name;
  final Color color;

  Priority({required this.value, required this.name, required this.color}) {}
}

class Priorities {
  static var LOW =
      Priority(name: Strings.low, value: "low", color: Colors.yellow);
  static var MEDIUM =
      Priority(name: Strings.medium, value: "medium", color: Colors.orange);
  static var HIGH =
      Priority(name: Strings.high, value: "high", color: Colors.red);
  static var ALL = [LOW, MEDIUM, HIGH];

  Priority? findByName(String name) {
    var found = ALL.where((element) => element.name == name).toList();
    if (found.length == 0) {
      return null;
    }
    return found[0];
  }
}
