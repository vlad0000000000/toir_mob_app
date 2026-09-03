# Архитектура

## Стиль

**Layer-first внутри одного пакета, без слоя домена.** Никакой Clean
Architecture, use-case и репозиториев на фичу. Папки — частично по слою
(`http/`, `data/`, `model/`, `design/`, `widgets/`, `utils/`), частично по фиче
(`qr/`, `tasks/`, `repairs/`, `spare_parts/`, `notifications/`, …).

Переезд на feature-first обсуждался и **не сделан**. Не начинай его мимоходом;
пиши в текущей структуре.

## Дерево `lib/`

```
main.dart              точка входа, GoRouter (22 маршрута), MyApp, отладочная полоса
global_state.dart      статики: dataProvider, authUser, debug, hasConnectionToServer
settings.dart          пользовательские настройки поверх stringBox
strings.dart           Strings + 8 классов строк по фичам (Repair*, Conflict*,
                       SparePart*, InspectionConsumption*, ScanQueue*, UsageQueue*, ScanConflict*)
src/
  feature_flags.dart   FeatureFlags.pprEnabled (PPR_ENABLED из .env)
  app_bar/             MyAppBar.build(context) — один AppBar на большинство экранов
  app_lifecycle/       AppLifecycleObserver (resume → ensureRunning push)
  data/                data_provider.dart + part-файлы remote/sync/outbox
                       hive_storage_location.dart, repair_photo_files.dart
  design/              app_constants.dart (токены), app_theme.dart (2 схемы)
                       theme_extensions.dart — МЁРТВЫЙ, 0 импортов
  exceptions/          7 исключений: 3 про логин, AuthExpired, NoConnection,
                       ServerFailure (несёт код ответа), InsufficientStock (+ shortages)
  http/                api.dart (общий _client, окно недоступности) + 8 part-файлов
  model/               27 файлов, 29 рукописных TypeAdapter (следующий typeId — 30)
  notifications/       сервис, экран, карточка, SSE-парсер, push/ (второй изолят)
  qr/                  qa_actions (хаб), qr_screen (сканер), qr_result_screen (ядро),
                       scan_conflict_screen (разбор отклонённого осмотра)
  repairs/             список, карточка (2.5k строк), создание, конфликт, пикер,
                       repair_clipboard, repair_delete_dialog, repair_error_messages
  spare_parts/         справочник ЗИП + карточка позиции с историей
  tasks/               список оборудования, карточка задач (+ контроллер),
                       ppr_list_screen, periodic_task_card, фильтр (выключен)
  style/               snack_bar.dart; my_transition.dart и palette.dart — МЁРТВЫЕ
  update_manager.dart  ОТКЛЮЧЁН флагом enabled = false
  utils/               AnyController, Dialogs, go_router_ext, isOfflineError, Dependent
  widgets/             переиспользуемые виджеты (в т.ч. spare_part_consumption)
  login/ splash/ knowledge_base/ onboarding/
```

## Ответственность слоёв

| Слой | Что делает | Чего не делает |
|---|---|---|
| Экран | Вся UI-логика, валидация, диалоги, навигация. Читает данные напрямую через `GlobalState.dataProvider` | Не изолирован от Hive и API |
| `DataProvider` | Владеет боксами и in-memory кэшем, справочники, синхронизация, очереди, login | Не знает про UI. Ошибки **глотает**, кроме `updateEquipmentState` и `login` |
| `API` | HTTP: заголовки, таймауты, UTF-8, разбор JSON, multipart | Не кэширует, не ретраит, не знает про Hive |
| `model/` | Данные + `fromJson` + иногда `toJson` + рукописный адаптер | Бизнес-логики нет, кроме мелких геттеров |
| `design/` | Токены и тема | Виджетов не содержит |

Цикл `GlobalState ↔ DataProvider` намеренный, но легаси: новый код в
`DataProvider` должен использовать поля инстанса, а не `GlobalState.dataProvider`.

## Управление состоянием

Доминирует **`ValueNotifier` + `ValueListenableBuilder`**:

- `NotificationsService.instance.*` — шесть нотифаеров списка уведомлений;
- `AppTheme.activeThemeId` — перестраивает весь `MaterialApp`;
- `GlobalState.debug` — отладочная полоса;
- `DataProvider.activeRepairsCount` — счётчик на плитке «Ремонты» (активные +
  неотправленные черновики); заведён нотифаером, потому что сам `DataProvider`
  не реактивный, пересчитывается из каждого места, где меняется список или
  очередь;
- `DataProvider.authExpired` — токен протух, очередь встала;
- `DataProvider.rejectedScansCount` / `rejectedUsageCount` — полосы «сервер
  отказался принять» на главном хабе; изменение счётчика осмотров ещё и
  открывает разбор конфликта, если обходчик сейчас на главной;
- `AnyController<T>` — значение формы.

Дальше: `setState` в `State`; `provider` — ровно один `Provider` (`DataProvider`);
глобальные статики (`GlobalState`, `Settings`, `API.simulateOffline`).

Нет: BLoC, Riverpod, GetX, MobX, `freezed`, кодогенерации в `lib/`.

## Внедрение зависимостей

DI-контейнера нет. По убыванию частоты: статик, проставленный в `main()`
(`GlobalState.dataProvider`); синглтон через приватный конструктор
(`NotificationsService.instance`); `Provider` в дереве; конструктор — для
контроллеров форм.

## Навигация

`go_router` **7.1.1** — устаревшая мажорная версия. `GoRouter.location` удалён в
8.x и используется в `app_bar.dart` и `qr_result_screen.dart`; апгрейд сломает
их.

Один роутер, объявлен статически в `MyApp._router`. Плоский список из
**22 `GoRoute`**, вложенных маршрутов и `ShellRoute` нет.
`navigatorKey: PushNotificationRouter.navigatorKey` — чтобы фоновый изолят мог
навигировать.

**Единственный гвард — `redirect`:** не авторизован + защищённый маршрут →
`/login`; авторизован + `/login` → `/actions` (или `/onboarding`); отложенный
тап по пушу → `/notifications`. Публичные маршруты: `/login*` и
`/knowledge_base`.

### Три вида переходов

| Вид | Чем | Где |
|---|---|---|
| **Вглубь** | `push` | хаб → раздел → карточка, сканер → результат, карточка оборудования → форма ремонта |
| **Замена экрана** | `pushReplacement` | форма создания ремонта → карточка созданного или список |
| **Сброс** | `clearStackAndNavigate` (`pop()` до дна + `pushReplacement`) | вход, выход, splash, шаги онбординга |
| **Назад** | `backOr(fallback)` — `pop()`, а если стек пуст, сброс на запасной адрес | все кнопки «назад» |

Запасной адрес у `backOr` обязателен: на экран попадают тапом по
пуш-уведомлению или сразу после сброса, и возвращаться бывает некуда.

Оба помощника — в `utils/go_router_ext.dart`.

**Анимации переходов нет** — все маршруты отдают `NoTransitionPage`.

**Передача данных** — через `state.extra` типизированным объектом и
`state.pathParameters`. Передавай объект, если он уже есть на руках: карточка
нарисуется сразу, не дожидаясь сервера (для закрытых ремонтов это единственный
источник — в Hive их нет).

### Таблица маршрутов

| Путь | Экран | Примечание |
|---|---|---|
| `/` | `SplashScreen` | редиректит на `/login` |
| `/login` | `LoginScreen` | публичный; единственный не-`const` `NoTransitionPage` |
| `/onboarding`, `/onboarding_video` | онбординг | видео по `Settings.onboardingStep` |
| `/actions` | `QRActions` | главный хаб |
| `/tasks`, `/problems` | `EquipmentListScreen` | второй — вход без QR |
| `/ppr` | `PprListScreen` | за флагом `PPR_ENABLED`; переход к оборудованию — `?from=ppr` |
| `/details/:index` | `EquipmentDetailScreen` | `index` = `InventoryRecord.id` |
| `/qr_scanner` | `QRScreen` | |
| `/qr_result`, `/qr_result_problems`, `/qr_result_demo` | `QRResultScreen` | `extra: InventoryRecord` |
| `/repairs` | `RepairsListScreen` | |
| `/repairs/:uuid` | `RepairDetailScreen` | `extra: Repair` (необязателен) |
| `/repair_draft/:localId` | `RepairDetailScreen` | режим локального черновика |
| `/repair_create` | `CreateRepairScreen` | `extra: InventoryRecord` |
| `/spare_parts`, `/spare_parts/:uuid` | справочник ЗИП | |
| `/notifications`, `/notifications_settings` | центр уведомлений | |
| `/knowledge_base` | `KnowledgeBaseScreen` | публичный |

`MyAppBar.build` ветвится **по строке `location`** — добавление маршрута требует
правки `app_bar.dart`. Исключение: экраны, у которых заголовок зависит от данных
(карточки ремонта, ЗИП, уведомлений), строят собственный `AppBar`, и веток для
них намеренно нет.

## Поток данных

**Чтение.** Триггеры (`mainSync`): фоновый цикл 60 с, логин, вход в «Задачи»,
«ППР», «Сканер», «Осмотр оборудования», после отправки осмотра. Десять
справочников качаются параллельно, каждый — полная перезапись бокса, ошибка
глотается в `Logger`. Исключений два: пара «ППР → задачи» идёт последовательно
(`syncTasks` догружает осмотры по составу ППР, поэтому `syncPpr` обязан
завершиться раньше) и каталог ЗИП, который качается **инкрементально** — окном
`updated_since` со списком удалённых. UI читает **из Hive**, а не из результата
запроса.

**Каталог ЗИП вернулся в `mainSync`** после перевода на инкрементальный проход:
в устоявшемся состоянии это один запрос с пустым ответом, зато остатки на складе
перестали отставать. Полным проход бывает только на первом заходе и после
оборванной записи. `ensureSparePartsLoaded()` остался — им экраны ЗИП, ремонтов
и расхода добирают каталог, если кэш ещё пуст. Подробности —
`data-and-integrations.md`.

Пока стоит отметка недоступности сервера (`API.isServerKnownUnreachable`),
`mainSync` не начинается вовсе: десять параллельных проходов к мёртвому серверу —
самый дорогой способ ничего не узнать.

**Запись.** Две схемы очереди — без побочного эффекта (пара боксов + возврат из
pending через 120 с) и с побочным эффектом (один бокс + `Idempotency-Key`,
пошаговая фиксация прогресса). Выбор схемы и детали — `data-and-integrations.md`.

## Поток ошибок

| Уровень | Поведение |
|---|---|
| `API` | `throw Exception('Failed to …: код')`; 401 → `AuthExpiredException`; 409 с `insufficient_stock` → `InsufficientStockException`; прочий отказ с русским `detail` → `ServerFailureException` (несёт код ответа) |
| `DataProvider.sync*` | `catch (e) { _syncLog.warning(...) }` — ошибка глотается, экран о ней не узнаёт |
| `DataProvider.login` | Различает неверные данные и сетевой сбой (фолбэк на локальных пользователей) |
| `updateEquipmentState` | Пробрасывает — UI показывает снекбар |
| Очереди осмотров и ремонтов | Различают отказ / сбой шлюза (`ServerFailureException.isTransient`) / нет связи / протух токен |
| Экран | `try/catch` + `Dialogs.notify` или снекбар |

Детект офлайна — **общий помощник `isOfflineError` в `utils/offline_error.dart`**.
Своих копий не заводить: раньше их было три, и каждая ошибалась по-своему.
Разбор идёт и по типам (`http.ClientException`, `SocketException`,
`HttpException`), и по тексту — часть ошибок доезжает завёрнутой в `Exception`.

## Конфигурация

Один источник — `.env` в корне. Флейворов нет, `--dart-define` не используется.
Читается двумя независимыми путями: `flutter_dotenv` в Dart и
`java.util.Properties` в Gradle — формат должен быть валиден для обоих, **без
кавычек вокруг значений**.

`.env` в `.gitignore` и вне индекса git, но объявлен ассетом и попадает в APK.

## Кодогенерация

В `lib/` её **нет**. `hive_ce_generator` числится в `dev_dependencies`, но
`build_runner` не подключён, `*.g.dart` отсутствуют. Не запускай `build_runner` —
он перезапишет рукописные адаптеры и сломает данные пользователей.

## Образцы для подражания

| Что делаешь | Смотри на |
|---|---|
| Новый HTTP-метод | `http/equipment_api.dart` |
| Метод с разбором `detail` и идемпотентностью | `http/repair_api.dart` |
| Метод, собирающий данные из двух эндпоинтов | `http/ppr_api.dart` |
| Новый справочник в синхронизацию | `syncUsageUnitTypes` + вызов в `mainSync()` |
| Разбор отказа сервера на экране-тупике | `qr/scan_conflict_screen.dart` |
| Очередь без побочных эффектов | `syncPeriodicTasks` |
| Очередь с побочным эффектом на сервере | `syncPendingRepairs` |
| Экран-список | `tasks/equipment_list_screen.dart` |
| Экран с офлайном и очередью | `repairs/repairs_list_screen.dart` |
| Экран-форма | `qr/qr_result_screen.dart` + `result_controls.dart` |
| Сервис с реактивным состоянием | `notifications/notifications_service.dart` |
| Перевод ошибки сервера в текст | `repairs/repair_error_messages.dart` |
| Диалог подтверждения | `Dialogs.areYouSure` |
| Нижний лист | `showAppModalSheet` |

## Легаси — не тиражировать

| Что | Статус |
|---|---|
| `design/theme_extensions.dart` | 0 импортов |
| `style/my_transition.dart`, `style/palette.dart` | 0 ссылок — остатки удалённой анимации переходов |
| `select_*_button`, `button_with_select_dialog` | 0 внешних ссылок, кроме `select_task_button` и `select_image_button` (их использует `result_controls.dart`) |
| `scanned_barcode_label`, `dependent_multi`, `self_cancel_timer` | 0 ссылок |
| `UpdateManager` | Отключён флагом `enabled = false`; вызовы из 4 экранов ничего не делают |
| `getInventoryRecords()` | Не вызывается, заменён `getEquipment()` |
| `flutter_screenutil` | `ScreenUtilInit` обёрнут вокруг всего, но `.sw/.sp` использованы один раз |
| `Dependent<T>` | Один потребитель; для нового кода — штатный `ValueListenableBuilder` |
| Вечные циклы `while(true)` вместо таймеров | `data_provider_sync.dart`, `main.dart` |
| `GlobalState.hasConnectionToServer2` | Дубль без кэша, не используется |
