import '../../global_state.dart';
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
Future<void> signOut() async {
  // refresh_token живёт в записи логина рядом с паролем для офлайн-входа.
  // Выход его стирает: иначе после выхода сессию можно было бы продлевать
  // без пароля. Логин берём до сброса пользователя — после него его не узнать;
  // сам сброс остаётся первым действием (на это опирается `main.dart`).
  final username = GlobalState.authUser?.username;
  GlobalState.authUser = null;
  if (username != null) {
    await GlobalState.dataProvider.forgetRefreshToken(username);
  }
  GlobalState.updateDebug();
  // Запомненные фильтры — настройка прошлого пользователя.
  EquipmentListScreen.forgetFilters();
  SparePartsScreen.forgetFilter();
  RepairsListScreen.forgetFilter();
  NotificationsService.instance.onLogout();
  await PushNotificationsController.instance.stop();
}
