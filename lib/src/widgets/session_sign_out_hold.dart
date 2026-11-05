import 'package:flutter/widgets.dart';

import '../../global_state.dart';

/// Экран-форма: пока он открыт, выход на вход по истёкшей сессии ждёт.
///
/// Сервер перестал принимать токен — обходчика выводят на экран входа
/// (`main.dart`, правило `shouldSignOutExpiredSession`). Посреди осмотра или
/// ремонта это стёрло бы введённое, поэтому форма держит выход, пока она в
/// дереве: ушёл с неё — выход сработает сам. Подмешивать в `State` экранов,
/// где обходчик что-то вводит.
mixin HoldsSessionSignOut<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    GlobalState.dataProvider.sessionSignOutHolds.value++;
  }

  @override
  void dispose() {
    GlobalState.dataProvider.sessionSignOutHolds.value--;
    super.dispose();
  }
}
