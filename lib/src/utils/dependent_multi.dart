import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'inherited_wrapper.dart';

class DependentMulti<T> extends StatelessWidget {
  final List<ValueNotifier<T>> values;
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  const DependentMulti({Key? key, required this.builder, required this.values})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<SingleChildWidget> providers = [];
    Widget consumer = Consumer<T>(
      builder: (context, value, child) {
        Widget realChild = builder(context, value, child);
        return InheritedWrapper<T>(value, child: realChild);
      },
    );
    for (var val in values) {
      providers.add(ValueListenableProvider<T>.value(
        value: val,
      ));
    }
    return MultiProvider(providers: providers, child: consumer);
  }
}
