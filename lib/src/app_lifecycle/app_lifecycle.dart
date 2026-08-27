import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../notifications/push/push_notifications_controller.dart';

class AppLifecycleObserver extends StatefulWidget {
  final Widget child;

  const AppLifecycleObserver({required this.child, super.key});

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  static final _log = Logger('AppLifecycleObserver');

  final ValueNotifier<AppLifecycleState> lifecycleListenable =
      ValueNotifier(AppLifecycleState.inactive);

  @override
  Widget build(BuildContext context) {
    // Using InheritedProvider because we don't want to use Consumer
    // or context.watch or anything like that to listen to this. We want
    // to manually add listeners. We're interested in the _events_ of lifecycle
    // state changes, and not so much in the state itself. (For example,
    // we want to stop sound when the app goes into the background, and
    // restart sound again when the app goes back into focus. We're not
    // rebuilding any widgets.)
    //
    // Provider, by default, throws when one
    // is trying to provide a Listenable (such as ValueNotifier) without using
    // something like ValueListenableProvider. InheritedProvider is more
    // low-level and doesn't have this problem.

    return InheritedProvider<ValueNotifier<AppLifecycleState>>.value(
      value: lifecycleListenable,
      child: widget.child,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.info(() => 'didChangeAppLifecycleState: $state');
    lifecycleListenable.value = state;
    // GlobalState.dataProvider.syncInventory();
    // GlobalState.dataProvider.syncScans();
    GlobalState.updateDebug();
    // Здесь стоял безусловный сброс отметок о закрытых задачах
    // (`DataProvider.closedTasks = {}`). Он срабатывал на любое состояние —
    // `inactive`, `paused`, `hidden`, — то есть на блокировку экрана и на
    // открытие камеры. После этого закрытая задача снова появлялась в списке,
    // и обходчик выполнял её второй раз. Теперь отметки живут в Hive и
    // снимаются там, где это осмысленно: когда сервер перестал отдавать
    // задачу (см. `DataProvider.pruneClosedTasks`).
    if (state == AppLifecycleState.resumed) {
      PushNotificationsController.instance.ensureRunning();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _log.info('Subscribed to app lifecycle updates');
  }
}
