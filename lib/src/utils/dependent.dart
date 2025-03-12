import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inherited_wrapper.dart';

class Dependent<T> extends StatelessWidget {
  final ValueNotifier<T> value;
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  const Dependent({Key? key, required this.value, required this.builder})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableProvider<T>.value(
        value: value,
        child: Consumer<T>(
          builder: (context, value, child) {
            Widget realChild = builder(context, value, child);
            return InheritedWrapper<T>(value, child: realChild);
          },
        ));
  }
}
