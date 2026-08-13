# Данные и интеграции

## Бэкенд

Единственный внешний API — **Sampo Smart backend** (FastAPI, репозиторий
`sampo_smart_backend` в том же workspace). Базовый URL берётся из `.env`
(`API_ENDPOINT`) один раз при старте: `API.baseUrl = dotenv.env["API_ENDPOINT"]!`
(`lib/src/http/api.dart:34`). Смена адреса требует перезапуска приложения.

HTTP-клиент — **`package:http`**. `dio` присутствует в `pubspec.yaml`, но
**не импортируется нигде**. Не начинай его использовать.

### Организация клиента

```
lib/src/http/api.dart          класс API: baseUrl, basicAuth, jwtToken,
                               таймауты, _guardOffline(), isAlive(),
                               StreamedResponseHandle
  part auth_api.dart           extension AuthApi
  part equipment_api.dart      extension EquipmentApi
  part task_api.dart           extension TaskApi
  part scan_api.dart           extension ScanApi
  part notifications_api.dart  extension NotificationsApi
  part repair_api.dart         extension RepairApi
  part spare_part_api.dart     extension SparePartApi
```
`API` — фактически stateless: всё состояние в статиках (`baseUrl`, `jwtToken`
через `GlobalState.authUser`, `currentSession`, `simulateOffline`). Инстансы
создаются свободно: `API()`.

### Полный список эндпоинтов

| Метод | Путь | Dart-метод | Файл:строка |
|---|---|---|---|
| GET | `/docs` | `isAlive()` — ping доступности | `api.dart:71-87` |
| POST | `/v1/auth/login` | `login(username, password)` | `auth_api.dart:71` |
| GET | `/v1/user/me` | `me(token)` | `auth_api.dart:4` |
| GET | `/v1/company/me` | `getCompany()` | `auth_api.dart:27` |
| GET | `/v1/walker/list` | `getUsers()` — **не вызывается** | `auth_api.dart:50` |
| GET | `/v1/session/` | `getCurrentSession()` | `auth_api.dart:124` |
| GET | `/v1/company/equipment?limit&skip` | `getEquipment()` | `equipment_api.dart:4` |
| GET | `/v1/inventory_record/list?limit&offset` | `getInventoryRecords()` — **мёртвый** | `equipment_api.dart:28` |
| GET | `/v1/company/equipment/states` | `getEquipmentStates()` | `equipment_api.dart:53` |
| GET | `/v1/company/equipment/usage-unit-types` | `getUsageUnitTypes()` | `equipment_api.dart:79` |
| PATCH | `/v1/company/equipment/{uuid}/usage-parameters/{uuid}` | `updateUsageParameter()` | `equipment_api.dart:107` |
| PATCH | `/v1/company/equipment/{uuid}` (multipart, поле `state`) | `updateEquipmentState()` | `equipment_api.dart:140` |
| GET | `/v1/company/fault_inspections/?limit&skip&status=open` | `getCurrentOpenTasks()` | `task_api.dart:4` |
| GET | `/v1/company/fault_inspections/?limit&skip&status=scheduled` | `getCurrentTasks()` | `task_api.dart:38` |
| GET | `/v1/company/eq_fault/?limit&skip` | `getTypicalProblems()` | `task_api.dart:115` |
| GET | `/v1/company/periodic_task/periodicity-rules` | `getPeriodicityRules()` | `task_api.dart:143` |
| POST | `/v1/company/periodic_task/` | `createPeriodicTask()` | `task_api.dart:171` |
| POST | `/v1/company/periodic_task/{uuid}/photos` (multipart) | внутри `createPeriodicTask` | `task_api.dart:199-234` |
| POST | `/v1/company/fault_inspections/` (multipart) | `sendScan()` — новый осмотр | `scan_api.dart:16-19` |
| PATCH | `/v1/company/fault_inspections/{taskUuid}` (multipart) | `sendScan()` — закрытие задачи | `scan_api.dart:20-26` |
| GET | `/v1/company/notifications/mobile/settings` | `getNotificationSettings()` | `notifications_api.dart:4` |
| PATCH | `/v1/company/notifications/mobile/settings` | `patchNotificationSettings()` | `notifications_api.dart:28` |
| GET | `/v1/company/notifications/mobile?skip&limit&…` | `getNotifications()` | `notifications_api.dart:55` |
| POST | `/v1/company/notifications/mobile/{uuid}/read` | `markNotificationRead()` | `notifications_api.dart:113` |
| GET | `/v1/company/notifications/mobile/stream` (SSE) | `openNotificationStream()` | `notifications_api.dart:138` |
| GET | `/v1/repairs/?limit&skip&status` | `getRepairs()` | `repair_api.dart:10` |
| GET | `/v1/repairs/recent-closed` | `getRecentClosedRepairs()` | `repair_api.dart:50` |
| GET | `/v1/repairs/{uuid}` | `getRepair()` | `repair_api.dart:352` |
| POST | `/v1/repairs/` | `createRepair()` — заголовок `Idempotency-Key` | `repair_api.dart:123` |
| PATCH | `/v1/repairs/{uuid}` | `updateRepair()` — комментарий, расход, статус | `repair_api.dart:303` |
| PATCH | `/v1/repairs/{uuid}` | `claimRepair()` — взять ролевой ремонт на себя | `repair_api.dart:267` |
| POST | `/v1/repairs/{uuid}/photos` (multipart) | `uploadRepairPhotos()` — `Idempotency-Key` | `repair_api.dart:179` |
| DELETE | `/v1/repairs/{uuid}/photos/{uuid}` | `deleteRepairPhoto()` | `repair_api.dart:235` |
| GET | `/v1/company/consumption_norms/?equipment_uuid&usage_type` | `getConsumptionNorms()` | `repair_api.dart:78` |
| GET | `/v1/company/spare_parts?limit&skip` | `getSpareParts()` | `spare_part_api.dart:12` |
| GET | `/v1/company/spare_parts/{uuid}` | `getSparePart()` | `spare_part_api.dart:43` |
| GET | `/v1/company/spare_parts/history` | `getStockHistory()` | `spare_part_api.dart:70` |

**Публичные пути менять нельзя** без согласования с бэкендом.

### Что сервер делает за клиента (ремонты)

Три вещи, которые легко попытаться реализовать в приложении заново:

1. **Сужение выдачи.** `GET /v1/repairs/` для роли `walker` уже отдаёт только
   ремонты, где пользователь ответственный **или** где ремонт назначен на его
   должность. Параметр «мои» передавать не нужно и его нет.
2. **Состояние оборудования.** При создании ремонта сервер сам переводит
   оборудование в `in_repair`, при закрытии — возвращает прежнее. Приложение
   состояние **не трогает**: выбор «В ремонте» в карточке скана открывает
   форму создания ремонта, а не шлёт `PATCH` состояния.
3. **Белый список полей.** В `PATCH /v1/repairs/{uuid}` роли `walker`
   разрешены ровно `status`, `comment`, `actual_consumptions` — любое лишнее
   поле даёт 403. Исключение — захват свободного ролевого ремонта: там
   допускается одиночный `responsible_user_uuid` со своим uuid.

### Идемпотентность

`createRepair` и `uploadRepairPhotos` принимают заголовок `Idempotency-Key`;
сервер помнит пару «компания + ключ» и на повтор возвращает уже созданную
сущность с кодом 200 вместо 201. Это то, на чём держится офлайн-очередь
ремонтов — см. `architecture.md`, «Вторая очередь — ремонты». Пустую строку
сервер считает ошибкой, поэтому заголовок ставится только при непустом ключе.

### Параметр пагинации называется `skip`

Все списковые GET принимают `limit` + **`skip`**, при том что аргумент Dart-метода
называется `offset`. Единственное исключение — мёртвый `getInventoryRecords`,
который шлёт `offset`. Не перепутай.

Загрузка «всего» реализована циклом до пустой страницы
(`data_provider_remote.dart:5-22`): `limit = 100` для оборудования,
`limit = 50` для задач и типовых проблем.

### Заголовки

- `Authorization: Bearer {jwt}` — все методы, кроме `login` и `isAlive`.
- `Authorization: Basic base64(API_USER:API_PASSWORD)` — только `isAlive()`.
  Basic Auth фактически нужен лишь для того, чтобы `API()` не упал на
  `dotenv.env["API_USER"]!` при старте; бэкенд его не проверяет.
- `Content-Type: application/json` — для POST/PATCH с телом.
- `accept: application/json` — для multipart.
- `Accept: text/event-stream` + `Cache-Control: no-cache` — для SSE.

### Таймауты

```dart
static const Duration _readTimeout   = Duration(seconds: 15);  // GET и мелкие записи + login
static const Duration _uploadTimeout = Duration(seconds: 60);  // multipart с фото
static const Duration _aliveTimeout  = Duration(seconds:  5);  // ping isAlive
```
(`api.dart:50-55`). Ретраев на уровне HTTP нет — повторы делает очередь.

### Кодировка

Каждый GET декодируется вручную:
```dart
const utf8Decoder = Utf8Decoder(allowMalformed: true);
final decodedBytes = utf8Decoder.convert(response.bodyBytes);
final data = jsonDecode(decodedBytes);
```
Это защита от битой кириллицы в ответах. Не заменяй на `response.body` —
коммит `2ec64b3 fix: cyrillic text corruption` появился именно из-за этого.

### Multipart

Четыре места: `sendScan`, `updateEquipmentState`, загрузка фото периодической
задачи и `uploadRepairPhotos`. Фото передаются в методы API **base64-строками**
и перед отправкой декодируются:
```dart
final cleanBase64 = base64Image.contains(',') ? base64Image.split(',').last : base64Image;
final bytes = base64Decode(cleanBase64);
request.files.add(http.MultipartFile.fromBytes('files', bytes,
    filename: 'image_$i.jpg', contentType: MediaType('image', 'jpeg')));
```
(`scan_api.dart:38-59`). Ошибка декодирования конкретного фото логируется и
пропускается — отправка не срывается.

**Исключение — снимки ремонта.** В очереди они лежат **файлами на диске**
(`lib/src/data/repair_photo_files.dart`), а не base64 в Hive: черновик может
ждать связи сутками. В `uploadRepairPhotos` они попадают уже прочитанными в
base64, и уходят **по одному запросу на кадр** — сервер принимает список, но
при обрыве на середине узнать, какие снимки сохранились, было бы неоткуда.
Принятый путь сразу вычёркивается из очереди, а файл удаляется.

`sendScan` дополнительно фильтрует поля: в `request.fields` попадают только
непустые строковые значения, кроме `files` (`scan_api.dart:31-36`). Из-за этого
`null` и пустые строки на сервер не уходят.

### Успех

Успехом считается `statusCode == 200 || statusCode == 201` — везде. Для методов,
возвращающих `bool`, дополнительно проверяется наличие ключа `uuid` в ответе
(`equipment_api.dart:133`, `scan_api.dart:73`, `task_api.dart:198`).

---

## Аутентификация

**Схема — JWT Bearer.**

1. `POST /v1/auth/login` с `{username, password}` → `{access_token, role}`.
2. `GET /v1/user/me` с новым токеном → `{effective_role, custom_role_id, uuid}`.
3. `User` кладётся в Hive-бокс `users` под ключом `username`,
   плюс отдельно под ключом `auth_user` — это и есть «текущий пользователь»
   (`global_state.dart:22-36`).
4. `API.jwtToken` — геттер, читающий `GlobalState.authUser!.JWTToken`
   (`api.dart:40-45`). Отдельного хранилища токена нет.

**Refresh-токенов нет.** Клиент не умеет обновлять токен; срок жизни задаётся
бэкендом (`JWT_ACCESS_TOKEN_EXPIRES` в его конфиге) и на практике достаточно
велик, чтобы проблема почти не проявлялась.

**Частичная обработка 401 всё же есть** — ради очереди ремонтов.
`_throwServerError` (`api.dart:96-105`) выделяет 401 в `AuthExpiredException`,
и очередь отличает «сервер отказал по существу» от «протух токен»: во втором
случае черновик не помечается отклонённым, вместо этого поднимается флаг
`DataProvider.authExpired`, список ремонтов показывает баннер, а отправка
продолжается сама после повторного входа. На автоматический выход из
приложения или переход на `/login` это не влияет — такого поведения нет.
Остальные методы API по-прежнему превращают 401 в обычный `Exception`,
который `sync*` проглотит.

**Офлайн-вход.** При сетевом сбое `DataProvider.login` перебирает локально
сохранённых пользователей и сравнивает `user.password == password`
(`data_provider_remote.dart:134-148`). **Пароль хранится в Hive в открытом
виде** (`user.dart:5`, пишется адаптером на строке 46). Это осознанный
компромисс ради работы без сети; шифрования Hive (`HiveAesCipher`) нет.

**Авторизация внутри приложения.** Роль `walker` — единственный допуск
(`data_provider_remote.dart:151-156`). `effectiveRole` и `customRoleId`
используются только для фильтрации задач и параметров наработки, экранов не
ограничивают.

**Выход** очищает `auth_user`, но **не чистит** остальные боксы — данные
предыдущего пользователя остаются на устройстве.

---

## Локальное хранилище — Hive (`hive_ce`)

### Расположение

Считает `HiveStorageLocation.resolve(packageInfo)`
(`lib/src/data/hive_storage_location.dart`), вызов — `main.dart:110-115`.

```dart
final stableName = GlobalState.digest([appName, packageName].join('|'));
```

**Версия в состав пути не входит**, поэтому обновление приложения базу не
обнуляет. Прежняя схема включала `version|buildNumber`, и каждый выпуск
открывал пустую базу — неотправленные осмотры оставались в каталоге старой
версии и для обходчика исчезали. `resolve` при первом запуске переносит
`*.hive` из каталога прошлой схемы (имя — 32 hex-символа) и ставит внутри
маркер `.migrated`; `.lock` не переносится, он создаётся заново. Маркер
пишется **только после полного успеха** — прерванный перенос повторится
целиком, `File.copy` перезаписывает и повтор безопасен.

На web — `Hive.initFlutter()` без пути. Шифрования нет.

### 20 боксов

| Бокс | Тип | Ключ | Содержимое |
|---|---|---|---|
| `users` | `User` | `username` + `'auth_user'` | Пользователи, включая текущего |
| `inventory` | `InventoryRecord` | авто (`addAll`) | Оборудование/ТМЦ |
| `scans` | `Scan` | `scan.key()` (md5) | **Очередь** осмотров к отправке |
| `pending_scans` | `Scan` | `scan.key()` | Осмотры «в полёте» |
| `usage_scans` | `UsageUpdate` | `key()` | Очередь наработок |
| `pending_usage_scans` | `UsageUpdate` | `key()` | Наработки «в полёте» |
| `periodic_tasks` | `PeriodicTaskRequest` | `key()` | Очередь ad-hoc задач |
| `pending_periodic_tasks` | `PeriodicTaskRequest` | `key()` | Задачи «в полёте» |
| `sessions` | `Session` | `'current_session'` | Активная инвентаризация |
| `tasks` | `Task` | `task.uuid` | Кэш задач |
| `typical_problems` | `TypicalProblem` | авто | Справочник неисправностей |
| `periodicity_rules` | `PeriodicityRule` | авто | Справочник периодичностей |
| `usage_units` | `UsageUnit` | авто | Справочник единиц наработки |
| `company` | `Company` | `'company'` | Компания + фича-флаг |
| `equipment_states` | `EquipmentState` | `'equipment_state'` | Словарь состояний |
| `spare_parts` | `SparePart` | авто | Справочник ЗИП (нужен офлайн для ввода расхода) |
| `repairs` | `Repair` | `repair.uuid` | Кэш **активных** ремонтов; закрытые сюда не попадают |
| `pending_repairs` | `PendingRepair` | `draft.localId` | **Очередь** черновиков ремонта; ключ = `Idempotency-Key` |
| `pending_repair_updates` | `PendingRepairUpdate` | `repairUuid` | Отложенная правка существующего ремонта, одна на ремонт (перезаписывается) |
| `strings` | `String` | разные | **Универсальная свалка** (см. ниже) |

### `stringBox` — общий key-value

Ключи, которые в нём живут:

| Ключ | Кто пишет | Смысл |
|---|---|---|
| `themeId` | `Settings.themeId` | `fresh` / `industrial` |
| `qrResultShowTasksFirst`, `qrResultShowSimplifiedView`, `notificationsHideRead` | `Settings` | `"1"` / `"0"` |
| `onboardingCompleted`, `onboardingInProgress`, `onboardingStep` | `Settings` | флаги и номер шага |
| `last_sync_date` | `DataProvider.saveLastSyncDate` | `dd-MM-yyyy HH:mm:ss` |
| `scan_pending_<key>` | `syncScans` | timestamp попытки отправки (мс) |
| `periodic_task_pending_<key>` | `syncPeriodicTasks` | то же для ad-hoc задач |
| `maintenance_task_<taskUuid>` | `DataProvider.addScan` | `"1"` — «это задача ТО, ждать наработку» |

`stringBox` — для одиночных значений и флагов. Коллекция сущности заслуживает
своего типизированного бокса: так сделаны ЗИП и ремонты. Исходный план
(`ПЛАН_РЕМОНТЫ_ЗИП.md`, п. 1.4) требовал обратного — хранить новые сущности
здесь сериализованным текстом, — но реализация пошла другим путём и завела
`typeId` 22–28. Правда за кодом.

### Адаптеры и `typeId`

28 адаптеров, все рукописные, регистрируются в `main.dart:117-144`.
Занятые `typeId`: 0–4 и 6–28. `typeId = 5` освобождён удалением
`inventory_scan.dart` (`REFACTORING_CHECKLIST.md`, Phase 1), но
**переиспользовать его нельзя** — на старых устройствах могут лежать записи со
старым форматом.

Распределение свежих номеров: 22 — `SparePart`, 23 — `Repair`,
24 — `RepairConsumption`, 25 — `RepairPhoto`, 26 — `RepairNormItem`,
27 — `PendingRepair`, 28 — `PendingRepairUpdate`. Следующий свободный — 29.

`RepairAdapter` — рабочий образец безопасного расширения модели: поле
`normItems` добавлено позже остальных, поэтому пишется последним и читается
через `_readTrailingList` с `try/catch`, возвращающим пустой список для
записей, сохранённых до его появления (`repair.dart:271-283`).

Правила изменения — см. `code-conventions.md`, раздел «Модели». Кратко:
порядок `read` == порядок `write`; новое поле только в конец + `try/catch` при
чтении; тип существующего поля не менять.

### Кэш в памяти

`DataProvider` при конструировании поднимает часть боксов в списки
(`data_provider.dart:65-73`): `_users`, `_inventoryRecords`, `_typicalProblems`,
`_periodicityRules`, `_usageUnits`, `_company`, `_currentSession`,
`_equipmentState`. UI читает **эти** поля, а не боксы напрямую. После записи в
бокс нужно синхронизировать кэш — например `updateInventoryRecords()`
(`data_provider.dart:153-155`). Забыть об этом — типичная ошибка: данные в Hive
обновились, а экран показывает старое.

Отдельно: `static Map<String, String> DataProvider.closedTasks` — in-memory
множество задач, закрытых в текущей сессии; сбрасывается на каждый
`didChangeAppLifecycleState` (`app_lifecycle.dart:52`).

---

## Стратегия кэширования и синхронизации

**Модель — «сервер перезаписывает справочники, клиент владеет очередью».**

| Направление | Стратегия |
|---|---|
| Справочники (оборудование, задачи, проблемы, периодичности, единицы, состояния, компания, ЗИП) | Полная перезапись: `box.clear()` + `box.addAll()`. Инкрементальных обновлений и ETag нет |
| Осмотры, наработки, ad-hoc задачи | Очередь в Hive с ретраями до успеха |
| Черновики и правки ремонтов | Очередь в Hive, но с `Idempotency-Key` вместо таймаута возврата (`architecture.md`) |
| Активные ремонты | Кэшируются в `repairs` через `syncMyRepairs()` — карточку можно открыть и править без сети |
| Закрытые ремонты | **Не кэшируются** — отдельный эндпоинт, последние 10, только в памяти экрана |
| История движения ЗИП | **Не кэшируется** — только по запросу с карточки позиции |
| Уведомления | **Не кэшируются** — только в памяти `NotificationsService.notifications` |
| Состояние оборудования | Отправляется сразу, в очередь не ставится. Офлайн = не сохранится. Исключение — перевод «В ремонте»: он идёт через создание ремонта и потому переживает офлайн |

**Триггеры полной синхронизации (`mainSync`):**
- вечный цикл каждые 60 секунд, если есть связь (`data_provider_sync.dart:151-161`);
- после успешного логина (`login_screen.dart:57`);
- при нажатии «Сканер» и «Осмотр оборудования» на хабе (`qa_actions.dart:45,51`);
- при входе на `/tasks` — единожды, через `GlobalState.syncMainOnce()`;
- после отправки осмотра (`qr_result_screen.dart:329`);
- кнопкой «Синхронизировать данные» → `syncDataAndScans()`.

**Триггеры отправки очереди:** вечный цикл каждые 5 секунд
(`startScanSyncing`) — отправляет осмотры, наработки, ad-hoc задачи, черновики
ремонтов и отложенные правки ремонтов — плюс ручная кнопка
(`syncDataAndScans`) и pull-to-refresh на списке ремонтов. В списке ремонтов
порядок обратный обычному: сначала уходит очередь, потом перечитывается
список, иначе `syncMyRepairs` затёр бы только что отправленное старым ответом.

**Проверка связи** — `GlobalState.hasConnectionToServer`
(`global_state.dart:176-196`): `API().isAlive()` (GET `/docs`, таймаут 5 с)
с кэшем результата на 10 секунд. `connectivity_plus` в зависимостях есть, но
код, который его использовал, закомментирован (`global_state.dart:6,59-65`) —
доступность определяется **только** пингом сервера, не состоянием сети.

### Механика очереди (детально)

```
scanBox ──► (переложить) ──► scanPendingBox + stringBox['scan_pending_<key>'] = now
                                    │
                              api.sendScan()
                                    │
                    ┌───────────────┴───────────────┐
                 успех                          не успех / исключение
                    │                                │
   удалить из pending + удалить timestamp     остаётся в pending
   + удалить maintenance_task_<uuid>                 │
                                     через ≥120 с следующий проход
                                     вернёт запись обратно в scanBox
```

Тонкости, которые легко сломать:
- **Порог возврата — 120 секунд**, хотя комментарии в коде говорят «60 секунд»
  (`data_provider_outbox.dart:45,55-58,107`). Верь коду.
- `_isSyncingScans` — единственная защита от двойной отправки при одновременном
  срабатывании цикла и ручной кнопки.
- Задача ТО не уходит, пока по её оборудованию есть непустая очередь наработки
  (`data_provider_outbox.dart:69-88`). Порядок важен: сервер пересчитывает
  следующее ТО от значения счётчика.
- `syncUsageScans` устроена иначе — без timestamp, просто перекладывает и при
  неуспехе возвращает сразу.
- На старте приложения `pending_scans` целиком возвращается в `scans`
  (`main.dart:155-158`) — иначе убитое приложение потеряло бы «зависшие» записи.

---

## SSE (realtime-уведомления)

**Контракт:** SSE — только сигнал, источник правды — REST. На событие
`notification` клиент делает полный `refreshList()`. Событие `ping`
игнорируется. Так же описано в `sampo_smart_backend/docs/mobile_notifications_flow.md`.

**Два независимых потребителя одного стрима:**

| Изолят | Класс | Что делает при событии |
|---|---|---|
| main | `NotificationsService` | `refreshList()` — обновляет список на экране и `unreadCount` |
| фоновый (foreground-service) | `NotificationsTaskHandler` | Показывает локальное уведомление + шлёт `{'type': 'sse_event'}` в main через `sendDataToMain` |

Парсинг строк общий — `SseLineParser` (`lib/src/notifications/sse_line_parser.dart`):
накапливает `event:` и `data:`, на пустой строке вызывает колбэк, игнорирует
комментарии `:`.

**Надёжность (обе реализации):**
- реконнект через 5 секунд после `onError` / `onDone`;
- watchdog: если по стриму тишина дольше 3 минут — принудительный реконнект
  (`_silentDropThreshold`, проверка раз в 60 секунд);
- в фоновом изоляте — дедуп по `notification_uuid`, окно `LinkedHashSet` на 200
  элементов (`notifications_task_handler.dart:65-66`).

**Стрим закрывается** через `StreamedResponseHandle.close()` (`api.dart:90-101`),
который закрывает `http.Client` — иначе соединение течёт.

---

## Push-уведомления

Реализованы **без FCM** — через `flutter_foreground_task` + локальные уведомления.

| Компонент | Файл |
|---|---|
| Управление сервисом, разрешения, watchdog | `notifications/push/push_notifications_controller.dart` |
| Изолят сервиса: SSE + показ уведомлений | `notifications/push/notifications_task_handler.dart` |
| Роутинг тапа | `notifications/push/notification_router.dart` |

**Передача данных в изолят** — через `FlutterForegroundTask.saveData`:
ключи `sse_base_url`, `sse_jwt`, `push_tap_pending`. Это фактический IPC.

**Обратно в main** — `FlutterForegroundTask.sendDataToMain` с картами
`{'type': 'sse_event'}` и `{'type': 'push_tap'}`; подписчики:
`NotificationsService._onForegroundData` и `PushNotificationRouter._onTaskData`.

**Android-манифест** (`android/app/src/main/AndroidManifest.xml`) содержит:
`POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`,
`WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `MANAGE_EXTERNAL_STORAGE`, `INTERNET`,
плюс объявление сервиса
`com.pravera.flutter_foreground_task.service.ForegroundService` с
`foregroundServiceType="dataSync"` и `stopWithTask="false"`.

**Каналы уведомлений:** `notifications_sse_service` (сам сервис,
importance `MIN` — уходит в «Тихие») и `notifications_events` (реальные события).

Остатки Firebase (`ios/Runner/GoogleService-Info.plist`,
`ios/firebase_app_id_file.json`) — от шаблона, ни одного Firebase-пакета в
`pubspec.yaml` нет.

---

## Прочие интеграции

| Интеграция | Пакет | Где |
|---|---|---|
| Сканирование QR | `mobile_scanner` 7.0.0-beta.7 | `qr/qr_screen.dart` |
| Камера / галерея | `image_picker` | `widgets/select_image_button.dart`, `qr/result_controls.dart` |
| WebView базы знаний | `flutter_inappwebview` | `knowledge_base/knowledge_base_screen.dart` |
| Открыть ссылку в браузере | `url_launcher` | `knowledge_base/knowledge_base_utils.dart` |
| Видео онбординга | `video_player` | `onboarding/onboarding_video_player.dart` |
| Разрешения | `permission_handler` | `update_manager.dart` (код отключён) |
| Установка APK | `open_file` | `update_manager.dart` (код отключён) |
| Code push | Shorebird | `shorebird.yaml`, `app_id` публичный |
| SVG | `flutter_svg` | `widgets/help_link.dart` |
| Markdown | `flutter_markdown` | `utils/dialogs.dart`, паспорт оборудования |
| Диалоги | `awesome_dialog` | `utils/dialogs.dart`, `widgets/button_with_select_dialog.dart` (мёртв) |
| Overlay-лоадер | `flutter_easyloading` | подключён в `main.dart:413`, методы `EasyLoading.show/dismiss` **не вызываются** |
| Хэширование ключей очереди | `crypto` (`md5`) | `global_state.dart:18-20` |

**`crypto` используется, но отсутствует в `pubspec.yaml`** — приходит транзитивно.
Формально это риск: пропадёт из транзитивных зависимостей — сломается сборка.

### Неиспользуемые зависимости

`infinite_scroll_pagination`, `cached_network_image`, `flutter_cache_manager`,
`cherry_toast`, `dio`, `qr_code_scanner_plus`, `file_picker`,
`gallery_saver_plus`, `flutter_pdfview`, `shared_preferences`, `mime`, `themed`,
`connectivity_plus` (только в закомментированном коде), `flutter_screenutil`
(один вызов `.sw`).

Не удаляй их мимоходом — но и не используй как «уже есть, возьму».
Появление нового пакета в задаче — повод спросить, а не поставить.

---

## Аналитика, логирование, крашрепортинг

- **Аналитики нет.** Ни одного пакета и ни одного вызова трекинга.
- **Крашрепортинга нет.** Ни Sentry, ни Crashlytics, ни `runZonedGuarded`,
  ни `FlutterError.onError`.
- **Логирование** — `debugPrint` (37), `print` (19), `package:logging` (2).
  В release `Logger.root.level = Level.WARNING`, но `debugPrint`/`print`
  никак не приглушаются. Подробнее — `code-conventions.md`, «Логирование».
- Единственный «мониторинг» — отладочная полоса внизу экрана и карточка
  «Информация» (`GlobalState.buildInfo()`).

## Deep links, платежи, карты

Отсутствуют. `AndroidManifest` не объявляет ни одного `intent-filter` кроме
`MAIN`/`LAUNCHER`; `<queries>` объявлен только для открытия `https`-ссылок.
Единственный «внутренний deep link» — `FlutterForegroundTask.launchApp('/notifications')`
из фонового изолята.

---

## Границы безопасности

Фиксируем как есть, без оценок:

| Что | Состояние |
|---|---|
| JWT | В Hive, без шифрования, в составе объекта `User` |
| Пароль пользователя | В Hive **в открытом виде** — нужен для офлайн-входа |
| Basic Auth (`API_USER`/`API_PASSWORD`) | В `.env`, который **включён в assets** и попадает в APK |
| Ключи подписи | Пути и пароли в `.env`. Сам keystore в git **не попадает** — `android/.gitignore:12` игнорирует `**/*.keystore` и `**/*.jks`. Файл `android/app/debug.keystore` существует локально и создаётся разработчиком через `keytool` |
| Шифрование Hive | Не используется |
| Certificate pinning | Нет |
| `android:allowBackup` | `false` (`AndroidManifest.xml:29`) — данные не уходят в облачный бэкап |
| `MANAGE_EXTERNAL_STORAGE` | Запрошено ради самообновления APK, которое сейчас отключено |
| Логи | `debugPrint` печатает статусы, но токены и пароли в логи не выводятся |

**Никогда не выводи значения из `.env`, JWT или пароли в код, документацию,
сообщения об ошибках или коммиты.**
