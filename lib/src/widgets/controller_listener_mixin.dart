import 'package:flutter/widgets.dart';

/// Подписка на [Listenable] контроллера (обычно `controller.valueNotifier`)
/// с автоматической отпиской в `dispose`. Убирает повторяющийся boilerplate
/// `initState`/`dispose`/listener в `select_*`-виджетах.
///
/// Использование:
/// ```dart
/// class _State extends State<Foo> with ControllerListenerMixin {
///   @override
///   Listenable get controllerListenable => widget.controller.valueNotifier;
///   // при необходимости переопределить onControllerChanged()
/// }
/// ```
mixin ControllerListenerMixin<W extends StatefulWidget> on State<W> {
  Listenable get controllerListenable;

  /// Реакция на изменение контроллера. По умолчанию — простой rebuild.
  void onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    controllerListenable.addListener(onControllerChanged);
  }

  @override
  void dispose() {
    controllerListenable.removeListener(onControllerChanged);
    super.dispose();
  }
}
