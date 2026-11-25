import 'dart:async';

import '../../global_state.dart';
import '../http/api.dart';
import '../notifications/notifications_service.dart';
import '../notifications/push/push_notifications_controller.dart';
import '../repairs/repairs_list_screen.dart';
import '../spare_parts/spare_parts_screen.dart';
import '../tasks/equipment_list_screen.dart';

/// Выход из аккаунта: без пользователя, без уведомлений и push-сервиса.
///
/// Одно место для двух путей — кнопки «Выйти» и принудительного выхода, когда
/// сервер закрыл доступ компании (тариф истёк). Разойдись они, при
/// блокировке остался бы, например, работающий push-сервис со старым
/// токеном.
///
/// Локальные данные и очереди отправки не трогает: неотправленное уйдёт, когда
/// обходчик войдёт снова. Переход на экран входа — за вызывающим: у кнопки
/// есть `context`, у принудительного выхода — только роутер.
///
/// [revokeSession] — отозвать сессию и на сервере (`DELETE /v1/auth/logout/`,
/// бэкенд `8b547e8`): «Выйти» и выход по закрытому доступу. Не нужно и
/// нельзя при «Сессия истекла» (токен уже не действует) и при смене сервера:
/// токен прежнего сервера ушёл бы на чужой. Запрос — фоном: выход не ждёт
/// сети, без связи сессия не отзывается и доживает свой срок (решение 18.11).
Future<void> signOut({bool revokeSession = false}) async {
  // refresh_token живёт в записи логина рядом с паролем для офлайн-входа.
  // Выход его стирает: иначе после выхода сессию можно было бы продлевать
  // без пароля. Логин и токены берём до сброса пользователя — после него их
  // не узнать; сам сброс остаётся первым действием (на это опирается
  // `main.dart`).
  final user = GlobalState.authUser;
  final username = user?.username;
  final refreshToken = user?.refreshToken;
  final accessToken = user?.JWTToken;
  GlobalState.authUser = null;
  if (username != null) {
    await GlobalState.dataProvider.forgetRefreshToken(username);
  }
  if (revokeSession) {
    unawaited(_revokeQuietly(refreshToken, accessToken));
  }
  GlobalState.updateDebug();
  // Запомненные фильтры — настройка прошлого пользователя.
  EquipmentListScreen.forgetFilters();
  SparePartsScreen.forgetFilter();
  RepairsListScreen.forgetFilter();
  NotificationsService.instance.onLogout();
  await PushNotificationsController.instance.stop();
}

/// Отзыв сессии на сервере, ошибки глушатся: выход уже случился, а без связи
/// или при сбое сервера сессия просто доживёт свой срок.
Future<void> _revokeQuietly(String? refreshToken, String? accessToken) async {
  try {
    await GlobalState.dataProvider.api.revokeSession(
      refreshToken: refreshToken,
      accessToken: accessToken,
    );
  } catch (_) {
    // Нет связи или сервер прошлой версии — повторять не будем.
  }
}
