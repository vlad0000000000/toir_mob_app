import 'dart:async';

import 'package:flutter/material.dart';

/// самоотменяющийся таймер
/// при вызове [run] несколько раз,
/// предыдущий таймер отменяется и ставится новый
/// полезно для задержки саджестов
class SelfCancelTimer {
  Timer? _t;

  void run(Duration d, VoidCallback cb) {
    cancel();
    _t = new Timer(d, cb);
  }

  void cancel() {
    if (_t != null) {
      _t!.cancel();
    }
  }
}
