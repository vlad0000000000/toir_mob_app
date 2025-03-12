import 'package:flutter/cupertino.dart';

abstract class KeyValueStorage {

  @protected
  Map<String, dynamic>? _map;

  dynamic get(String key) {
    return _map![key];
  }

  bool? set(String key, dynamic value) {
    _map![key] = value;
    sync();
    return true;
  }

  bool? delete(String key) {
    _map!.remove(key);
    sync();
    return null;
  }

  Future<bool?> sync() async {
    return null;
  }
}
