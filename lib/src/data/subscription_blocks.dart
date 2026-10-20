/// Блокировки доступа по тарифу на этом телефоне — чтобы офлайн-вход не
/// обходил их.
///
/// Блокируется **компания**, а не логин: на одном телефоне обычно работают
/// несколько обходчиков одной компании, и блокировка по логину пускала бы
/// без сети любого другого из них. Поэтому:
///
/// * удачный онлайн-вход запоминает компанию логина ([rememberCompany]) и
///   момент, когда сервер подтвердил её доступ ([clearCompany]);
/// * блокировка пишется на компанию; если компания логина ещё неизвестна
///   (входил до появления этой связи), — на сам логин. Вместе с моментом
///   записи;
/// * офлайн-вход закрыт ([isBlocked]), если заблокирована компания логина,
///   или есть блокировка логина той же или неизвестной компании, **свежее**
///   последнего подтверждения доступа компании входящего, или компания
///   самого входящего неизвестна, а хоть одна блокировка есть. Неизвестное
///   считаем заблокированным: обойти блокировку важнее, чем пустить офлайн
///   сотрудника другой компании на том же телефоне;
/// * удачный онлайн-вход снимает блокировку своей компании ([clearCompany]):
///   сервер подтвердил, что доступ есть.
///
/// Почему время. Блокировка логина с неизвестной компанией иначе держала бы
/// всех, пока этот самый логин не войдёт онлайн: онлайн-вход другого
/// сотрудника её не снимает — неизвестно, его ли это компания. Но для
/// входящего с известной компанией блокировка, записанная **до**
/// подтверждения доступа его компании, ничего не значит в любом случае: была
/// она той же компании — её перекрыло более позднее подтверждение; была
/// другой — к нему не относится.
///
/// Хранилище — функции над строковым key-value (`stringBox`), время — [now]:
/// так правило проверяется тестом без Hive.
class SubscriptionBlocks {
  final String? Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<void> Function(String key) delete;
  final Iterable<String> Function() keys;
  final DateTime Function() now;

  SubscriptionBlocks({
    required this.read,
    required this.write,
    required this.delete,
    required this.keys,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  static const String _companyOfLogin = 'account_company:';
  static const String _companyConfirmedAt = 'account_company_ok:';
  static const String _blockedCompany = 'subscription_blocked_company:';
  static const String _blockedLogin = 'subscription_blocked:';

  /// Компания логина по последнему онлайн-входу. `null` — не входил онлайн с
  /// тех пор, как эта связь появилась.
  String? companyOf(String login) => read('$_companyOfLogin$login');

  Future<void> rememberCompany(String login, String companyId) =>
      write('$_companyOfLogin$login', companyId);

  /// Записывает блокировку [accessState] для логина: на его компанию, а если
  /// она неизвестна — на сам логин.
  Future<void> block(String login, String accessState) async {
    final value = '$accessState|${now().millisecondsSinceEpoch}';
    final company = companyOf(login);
    if (company != null) {
      await write('$_blockedCompany$company', value);
    } else {
      await write('$_blockedLogin$login', value);
    }
  }

  /// Состояние блокировки для офлайн-входа логина. `null` — вход открыт.
  String? isBlocked(String login) {
    final company = companyOf(login);
    final confirmedAt = company == null
        ? null
        : int.tryParse(read('$_companyConfirmedAt$company') ?? '');
    if (company != null) {
      final entry = _entry(read('$_blockedCompany$company'));
      if (entry != null) return entry.state;
    }
    String? any;
    for (final key in keys().toList()) {
      if (key.startsWith(_blockedLogin)) {
        final entry = _entry(read(key));
        if (entry == null) continue;
        final blockedLogin = key.substring(_blockedLogin.length);
        final blockedCompany = companyOf(blockedLogin);
        // Блокировку логина с неизвестной компанией считаем блокировкой
        // любой компании: это мог быть сотрудник той же. Кроме записанных до
        // последнего подтверждения доступа компании входящего — см. класс.
        final relevant = blockedLogin == login ||
            blockedCompany == null ||
            blockedCompany == company;
        final stale = confirmedAt != null && entry.at <= confirmedAt;
        if (relevant && !stale) return entry.state;
        any ??= entry.state;
      } else if (key.startsWith(_blockedCompany)) {
        any ??= _entry(read(key))?.state;
      }
    }
    // Компания самого логина неизвестна — любая блокировка на телефоне
    // может оказаться его.
    return company == null ? any : null;
  }

  /// Удачный онлайн-вход логина компании [companyId]: доступ подтверждён.
  /// Запоминает момент подтверждения и снимает блокировку компании, самого
  /// логина и логинов этой компании.
  Future<void> clearCompany(String login, String companyId) async {
    await write(
      '$_companyConfirmedAt$companyId',
      '${now().millisecondsSinceEpoch}',
    );
    await delete('$_blockedCompany$companyId');
    await delete('$_blockedLogin$login');
    for (final key in keys().toList()) {
      if (!key.startsWith(_blockedLogin)) continue;
      final blockedLogin = key.substring(_blockedLogin.length);
      if (companyOf(blockedLogin) == companyId) await delete(key);
    }
  }

  /// `состояние|мс`. Без времени (записи прежнего формата) — самые старые.
  static ({String state, int at})? _entry(String? value) {
    if (value == null || value.isEmpty) return null;
    final separator = value.lastIndexOf('|');
    if (separator < 0) return (state: value, at: 0);
    return (
      state: value.substring(0, separator),
      at: int.tryParse(value.substring(separator + 1)) ?? 0,
    );
  }
}
