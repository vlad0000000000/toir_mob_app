import 'dart:typed_data';

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Время по поясу компании (`company.timezone` в `/user/me`, бэкенд `71e3243`).
///
/// Решение продукта: обходчик видит и вводит время компании — как в вебе и в
/// текстах уведомлений, которые сервер форматирует сам. По часам телефона одно
/// и то же время начала ремонта выглядело бы в вебе и на телефоне по-разному.
///
/// Всё сравнение и отправка идут моментами времени, пояс на них не влияет:
/// помощник нужен только там, где момент превращается в цифры на экране и
/// обратно. Пояс неизвестен (сервер прошлой версии, ещё не было синхронизации,
/// имени нет в базе поясов) — как раньше, время телефона.
class CompanyTime {
  CompanyTime._();

  static tz.Location? _location;
  static bool _databaseReady = false;

  /// Пояс, заданный [configure] и ещё не найденный в базе. `null` — искать
  /// нечего: пояс найден (или не найден) или его нет вовсе.
  static String? _pending;

  /// Москва — пояс по умолчанию у сервера. Подпись «МСК» только для него:
  /// у другого пояса с тем же смещением (Стамбул) она была бы неправдой.
  static const String moscow = 'Europe/Moscow';

  /// Имя текущего пояса. `null` — показываем время телефона.
  static String? get zoneName => _current?.name;

  /// Задаёт пояс компании; `null` — вернуться ко времени телефона.
  ///
  /// Сам пояс здесь не ищется — только запоминается. База поясов полная
  /// (`latest_all`: сервер отдаёт и устаревшие имена вроде `Europe/Kiev`, а
  /// урезанные базы их не знают) и разбирается заметное время, а
  /// [configure] зовут из `main` до первого кадра. Разбор — при первом
  /// обращении ко времени ([_current]), один раз за запуск.
  static void configure(String? zoneName) {
    _location = null;
    _pending = zoneName == null || zoneName.isEmpty ? null : zoneName;
  }

  /// Свежая база поясов, положенная в приложение отдельным файлом.
  ///
  /// Встроенная в пакет `timezone 0.9.4` база — IANA 2024a: в ней нет
  /// правил, принятых позже (Парагвай с осени 2024 живёт в UTC−3 постоянно,
  /// и введённые 09:00 уходили бы на час позже). Поднять пакет нельзя:
  /// `flutter_local_notifications 17` держит `timezone ^0.9.0`. Формат базы у
  /// пакетов общий, поэтому кладём файл из свежего `timezone`
  /// (`lib/data/latest_all.tzf`) и обновляем его при новых правилах IANA.
  static const String bundledDatabase = 'assets/timezone/latest_all.tzf';

  /// Байты [bundledDatabase], прочитанные на старте. `null` — файла нет или
  /// не прочитался: тогда встроенная база.
  static List<int>? _bundled;

  /// Читает [bundledDatabase] через [load] (`rootBundle.load`) — только
  /// байты, без разбора: разбирается база лениво, при первом обращении ко
  /// времени. Не вышло — останется встроенная база.
  static Future<void> loadBundledDatabase(
    Future<ByteData> Function(String key) load,
  ) async {
    try {
      final data = await load(bundledDatabase);
      _bundled =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      _bundled = null;
    }
  }

  /// Разбирает базу: свежую из файла, а не вышло — встроенную.
  static void _initDatabase() {
    final bundled = _bundled;
    if (bundled != null) {
      try {
        tz.initializeDatabase(bundled);
        return;
      } catch (_) {
        // Файл битый или другого формата — встроенная база лучше, чем ничего.
      }
    }
    tz_data.initializeTimeZones();
  }

  /// Пояс компании; база разбирается и пояс ищется при первом обращении.
  static tz.Location? get _current {
    final name = _pending;
    if (name != null) {
      _pending = null;
      if (!_databaseReady) {
        _initDatabase();
        _databaseReady = true;
      }
      try {
        _location = tz.getLocation(name);
      } on tz.LocationNotFoundException {
        _location = null;
      }
    }
    return _location;
  }

  /// Момент [instant] с цифрами по поясу компании — для показа. Подходит
  /// `DateFormat` и чтение `.hour`, `.day`; сравнения остаются верными.
  static DateTime of(DateTime instant) {
    final location = _current;
    return location == null
        ? instant.toLocal()
        : tz.TZDateTime.from(instant, location);
  }

  /// Текущее время компании.
  static DateTime now() => of(DateTime.now());

  /// Момент по цифрам времени компании — обратно к [of], для ввода даты и
  /// времени. Несуществующее время (перевод часов) пакет сдвигает сам.
  static DateTime fromFields(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
  ]) {
    final location = _current;
    return location == null
        ? DateTime(year, month, day, hour, minute)
        : tz.TZDateTime(location, year, month, day, hour, minute);
  }

  /// Тот же момент обычным [DateTime]. Для всего, что уходит из формы: Hive
  /// умеет хранить только его.
  static DateTime plain(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(value.millisecondsSinceEpoch);
}
