import 'package:flutter/foundation.dart';

/// Ответ на запрос с токеном [requestToken] относится к живой сессии: запрос
/// начат в текущей сессии ([requestSession] == [currentSession]), тот же
/// токен до сих пор вошёл ([currentToken]) и отказ «доступ закрыт» по нему
/// ещё не получали ([blockedToken]).
///
/// Иначе состояние доступа из этого ответа записывать нельзя: он мог
/// запоздать и затереть более свежий отказ — например, `/user/me`, начатый
/// до того, как роль сняли, вернул бы ещё активный профиль поверх
/// запомненной блокировки (`DataProviderSync.syncAccessProfile`).
///
/// Сессию сравниваем по номеру, а не только по токену: токен нового входа
/// может совпасть с прежним (время в нём — с точностью до секунды), и
/// запоздалый запрос прошлой сессии прошёл бы проверку и перезаписал
/// профиль, сохранённый входом. Номер растёт на каждом входе и выходе
/// (`DataProvider.startAccessSession`).
///
/// Отдельной чистой функцией — ради теста без Hive и `GlobalState`.
bool isLiveAccessSession({
  required String requestToken,
  required String? currentToken,
  required String? blockedToken,
  required int requestSession,
  required int currentSession,
}) =>
    requestSession == currentSession &&
    currentToken == requestToken &&
    blockedToken != requestToken;

/// Порядок ответов профиля доступа одной сессии.
///
/// Проверка сессии ([isLiveAccessSession]) защищает от ответа, пришедшего
/// после выхода или блокировки, но два запроса **одной** живой сессии она
/// пропускает оба. Летят они параллельно (фоновая синхронизация и
/// обновление по `X-Access-Version` или `access_changed`), и ответы могут
/// прийти наоборот: запоздалый старый профиль лёг бы поверх свежего и
/// вернул снятые права.
///
/// Сравнить сами профили нельзя: `access_version` у сервера непрозрачная
/// строка, порядка у неё нет. Поэтому порядок держим по запросам: каждый
/// берёт номер [begin] до отправки, и записать ответ можно, только если
/// после него не записали ответ более позднего запроса ([tryApply]).
class AccessResponseOrder {
  int _issued = 0;
  int _applied = 0;

  /// Номер запроса — брать до отправки.
  int begin() => ++_issued;

  /// Ответ запроса [ticket] можно записать — он не старше уже записанного.
  /// Возвращает `true` и запоминает его; вызывать в момент записи.
  bool tryApply(int ticket) {
    if (ticket <= _applied) return false;
    _applied = ticket;
    return true;
  }
}

/// Флаг состояния сессии, который ставят и снимают ответы на запросы, —
/// «сессия истекла» у очередей отправки (`DataProvider.authExpired`).
///
/// Запрос, ушедший до выхода, может ответить 401/403 уже после нового входа:
/// без проверки он поднял бы «Сессия истекла» над живой сессией, даже когда
/// следующий же осмотр отправлен успешно. Токен тут не поможет — у
/// повторного входа он может совпасть с прежним. Поэтому запрос запоминает
/// номер сессии до отправки, и менять флаг может только ответ текущей.
class SessionGuardedFlag {
  final ValueNotifier<bool> flag;
  final int Function() currentSession;

  SessionGuardedFlag(this.flag, this.currentSession);

  /// Ставит [value], если запрос отправлен в текущей сессии [requestSession];
  /// ответ прошлой ничего не меняет.
  void set(bool value, {required int requestSession}) {
    if (requestSession != currentSession()) return;
    flag.value = value;
  }
}
