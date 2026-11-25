import 'dart:convert';
import 'dart:math';

import '../../global_state.dart';
import '../model/mobile_support_status.dart';
import 'session_server.dart';

// Установка приложения на сервере (бэкенд `81f644c`).
//
// У каждой установки — постоянный UUID. Приложение регистрирует его на
// сервере вместе со своей сборкой и передаёт заголовком
// `X-Mobile-Installation-ID` в ленте уведомлений, SSE и служебных методах.
// По нему сервер узнаёт версию: показывает предупреждение об окончании
// поддержки и объявление о новой версии со ссылкой на RuStore.
//
// Клиента **без** заголовка сервер считает «Версией 1.0» и сам кладёт ему
// объявления карточками в ленту. С заголовком карточек нет — объявления
// приложение показывает само. Поэтому заголовок ставится только после
// успешной регистрации в этом аккаунте на этом сервере
// (`installationRegistered`).

/// Ключ UUID установки в `stringBox`. При выходе и смене аккаунта не
/// стирается, путь Hive от версии приложения не зависит — значит, UUID
/// переживает и обновление APK. Новый — только после удаления приложения.
const String mobileInstallationIdKey = 'mobile_installation_id';

/// Как часто повторять регистрацию одной и той же сборки. Время последнего
/// подключения в статистике сервер обновляет только по ней; у клиентов 1.0
/// он отмечает подключение не чаще раза в 5 минут — держим тот же шаг.
const Duration installationRefreshInterval = Duration(minutes: 5);

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Новый UUID версии 4 из криптостойкого генератора. Пакет `uuid` ради
/// одной строки не подключаем — так же считается ключ события осмотра.
String newInstallationId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // версия 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // вариант RFC 4122
  final hex =
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// [value] — UUID в том виде, в каком его пишет [newInstallationId]. Битое
/// значение в базе считаем отсутствующим: сервер ответил бы на него 422.
bool isInstallationId(String? value) =>
    value != null && _uuidPattern.hasMatch(value);

/// Ключ отметки «установка зарегистрирована» в `stringBox`: сервер и
/// пользователь, как у остальных данных аккаунта (`pendingReadKey`).
///
/// Регистрация на сервере живёт в паре «компания + пользователь +
/// установка», поэтому у каждого обходчика и каждого сервера своя отметка.
/// При смене аккаунта отметки не стираются: вернувшемуся обходчику
/// регистрироваться заново до первого заголовка не нужно.
String installationMarkKey(String userUuid, String server) =>
    'mobile_installation@'
    '${GlobalState.digest(normalizeServerAddress(server))}:$userUuid';

/// Отметка успешной регистрации: отпечаток сборки и время.
String encodeInstallationMark(String buildSignature, DateTime at) =>
    jsonEncode({'build': buildSignature, 'at': at.toUtc().toIso8601String()});

({String build, DateTime at})? _decodeMark(String? mark) {
  if (mark == null || mark.isEmpty) return null;
  try {
    final data = jsonDecode(mark);
    if (data is! Map) return null;
    final build = data['build'];
    final at = DateTime.tryParse('${data['at']}');
    if (build is! String || build.isEmpty || at == null) return null;
    return (build: build, at: at);
  } catch (_) {
    return null;
  }
}

/// Установка уже зарегистрирована в этом аккаунте — можно ставить заголовок.
bool installationRegistered(String? mark) => _decodeMark(mark) != null;

/// Пора регистрировать установку: ещё не регистрировали, сменилась сборка
/// (обновили приложение) или прошло [interval] с прошлой регистрации.
bool needsInstallationRegistration(
  String? mark, {
  required String buildSignature,
  required DateTime now,
  Duration interval = installationRefreshInterval,
}) {
  final decoded = _decodeMark(mark);
  if (decoded == null || decoded.build != buildSignature) return true;
  final elapsed = now.toUtc().difference(decoded.at.toUtc());
  // Часы телефона перевели назад — регистрируем, а не ждём до «будущего».
  return elapsed.isNegative || elapsed >= interval;
}

/// Ключ последнего статуса поддержки версии в `stringBox` — по серверу и
/// пользователю, как [installationMarkKey]: даты поддержки задаёт сервер, а
/// без связи плашка на главной показывается по сохранённому.
String supportStatusKey(String userUuid, String server) => 'mobile_support@'
    '${GlobalState.digest(normalizeServerAddress(server))}:$userUuid';

/// Ключ сохранённого списка текущих объявлений в `stringBox` — по серверу и
/// пользователю: без связи блок в «Уведомлениях» показывается по нему.
String announcementsCacheKey(String userUuid, String server) => 'announcements@'
    '${GlobalState.digest(normalizeServerAddress(server))}:$userUuid';

/// Ключ очереди недошедших отметок «прочитано» объявлений — как у отметок
/// уведомлений (`pendingReadKey`), по серверу и пользователю.
String announcementReadsKey(String userUuid, String server) =>
    'announcement_reads@'
    '${GlobalState.digest(normalizeServerAddress(server))}:$userUuid';

/// Сохранённый статус поддержки вместе с отпечатком сборки, к которой он
/// относится ([MobileBuild.signature]).
String encodeStoredSupportStatus(
  MobileSupportStatus status,
  String buildSignature,
) =>
    jsonEncode({...status.toJson(), 'build': buildSignature});

/// Сохранённый статус поддержки — только если он про [buildSignature]: после
/// обновления приложения статус прошлой сборки (например, «работа
/// ограничена») не показываем, пока сервер не подтвердит новую (бэкенд
/// `811c4dc`: «до подтверждения не показывать блокировку по старому номеру
/// сборки»). Статус без отпечатка — тоже не наш. `null` — нечего показать.
MobileSupportStatus? decodeStoredSupportStatus(
  String? raw,
  String? buildSignature,
) {
  if (raw == null || raw.isEmpty || buildSignature == null) return null;
  try {
    final data = jsonDecode(raw);
    if (data is! Map || data['build'] != buildSignature) return null;
    return MobileSupportStatus.fromJson(data);
  } catch (_) {
    return null;
  }
}
