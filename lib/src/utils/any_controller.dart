import 'package:flutter/material.dart';

class AnyController<T> {
  final ValueNotifier<T?> _valueNotifier = ValueNotifier(null);

  ValueNotifier<T?> get valueNotifier => _valueNotifier;

  T? get value => _valueNotifier.value;

  set value(T? newValue) {
    _valueNotifier.value = newValue;
  }

  void dispose() {
    _valueNotifier.dispose();
  }
}
