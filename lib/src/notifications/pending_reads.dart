import 'dart:convert';

import '../../global_state.dart';
import '../data/session_server.dart';

/// Префикс очереди отметок прочтения прошлой версии: ключ без сервера,
/// `notifications_pending_read:<логин>`.
const String legacyPendingReadKeyPrefix = 'notifications_pending_read:';

/// Ключ очереди недошедших отметок прочтения уведомлений в `stringBox`:
/// сервер и логин — как у остальных офлайн-данных (коммит `73f87bf`).
///
/// Раньше ключом был один логин. Если тот же логин есть на двух серверах
/// (стенд и копия его базы), отметки, не дошедшие до одного, после смены
/// сервера ушли бы на другой. Сервер — отпечатком адреса, как в
/// `pendingRepairUpdateKey`, и стоит **до** логина: логин может содержать
/// `@` и `:`, отпечаток — нет, и новый ключ не спутать со старым.
String pendingReadKey(String login, String server) =>
    'notifications_pending_read@'
    '${GlobalState.digest(normalizeServerAddress(server))}:$login';

/// Логин из ключа очереди прошлой версии (без сервера). `null` — ключ не
/// очереди отметок или уже с сервером.
String? legacyPendingReadLogin(Object? key) {
  if (key is! String || !key.startsWith(legacyPendingReadKeyPrefix)) {
    return null;
  }
  final login = key.substring(legacyPendingReadKeyPrefix.length);
  return login.isEmpty ? null : login;
}

/// Объединяет две сохранённые очереди (JSON-списки uuid) без повторов.
/// Битая запись — как пустая. `null` — объединять нечего.
String? mergePendingReads(String? first, String? second) {
  final merged = <String>{
    ..._decodePendingReads(first),
    ..._decodePendingReads(second),
  };
  return merged.isEmpty ? null : jsonEncode(merged.toList());
}

List<String> _decodePendingReads(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is String && item.isNotEmpty) item,
    ];
  } catch (_) {
    return const [];
  }
}
