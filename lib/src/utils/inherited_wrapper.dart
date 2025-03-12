import 'package:flutter/material.dart';

/// позволяем независимым друд от друга виджетам обновлятся от общего значения
class InheritedWrapper<T> extends InheritedWidget {
  final T value;

  InheritedWrapper(this.value, {required Widget child}) : super(child: child);

  @override
  bool updateShouldNotify(covariant InheritedWrapper oldWidget) {
    return oldWidget.value != value;
  }
}
