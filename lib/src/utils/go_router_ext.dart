import 'package:go_router/go_router.dart';

extension GoRouterExtension on GoRouter {
  /// Переход со сбросом стека: всё открытое закрывается, [location] становится
  /// новым корнем.
  ///
  /// Только для «сбросов», после которых возвращаться некуда и не нужно: вход,
  /// выход, шаги онбординга, отправка осмотра. Для обычных переходов вглубь
  /// используй `push` — тогда «назад» вернёт на предыдущий экран сам.
  void clearStackAndNavigate(String location, {Object? extra}) {
    while (canPop()) {
      pop();
    }
    pushReplacement(location, extra: extra);
  }

  /// Возврат на предыдущий экран, а если возвращаться некуда — уход на
  /// [fallback].
  ///
  /// Пустой стек — штатная ситуация, а не сбой: на экран можно попасть тапом
  /// по пуш-уведомлению или сразу после сброса. Без запасного адреса обходчик
  /// в таком случае застрял бы — кнопка «назад» не делала бы ничего.
  void backOr(String fallback) {
    if (canPop()) {
      pop();
    } else {
      clearStackAndNavigate(fallback);
    }
  }
}
