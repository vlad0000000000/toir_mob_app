/// Разбор поля «Горизонт показа задач» в настройках уведомлений.
///
/// Пусто — без ограничения (`null`). Иначе целое число дней от 0 до
/// [maxFutureDaysLimit]: сервер принимает `max_future_days >= 0`
/// (`NotificationSettingsUpdate` в `backend/schemas/notification.py`), а
/// верхняя граница — защита от опечатки вроде «300000», которую сервер принял
/// бы как есть.
///
/// Раньше неверный ввод («abc», «-5») молча уходил как `null` — то есть
/// «без ограничения»: обходчик хотел поправить горизонт, а сбрасывал его.
/// Теперь такой ввод не сохраняется, и поле подсвечивает ошибку.
const int maxFutureDaysLimit = 3650;

/// `valid: false` — ввод неверный, сохранять нельзя. Иначе [value] —
/// что отправить серверу (`null` — без ограничения).
({bool valid, int? value}) parseMaxFutureDays(String input) {
  final text = input.trim();
  if (text.isEmpty) return (valid: true, value: null);
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0 || parsed > maxFutureDaysLimit) {
    return (valid: false, value: null);
  }
  return (valid: true, value: parsed);
}
