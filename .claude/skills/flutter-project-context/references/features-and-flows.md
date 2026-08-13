# Фичи, экраны и пользовательские потоки

## Иерархия навигации

Плоская. `SplashScreen` мгновенно уводит на `/login`, дальше всё вращается вокруг
хаба `/actions`.

```
/                       (splash, мгновенный редирект)
└── /login                                    ← публичный, HelpLink в углу
    ├── /knowledge_base                       ← публичный, доступен до входа
    ├── /onboarding → /onboarding_video → …   ← если Settings.onboardingCompleted == false
    └── /actions                              ← ГЛАВНЫЙ ХАБ
        ├── /qr_scanner → /qr_result          ← основной рабочий путь
        │                 └── /repair_create → /repairs/:uuid
        ├── /tasks → /details/:index          ← задачи по оборудованию
        ├── /problems → /qr_result_problems   ← только если company.allowRequestsWithoutQr
        ├── /repairs → /repairs/:uuid         ← ремонты обходчика
        │           └→ /repair_draft/:localId ← неотправленный черновик
        ├── /spare_parts → /spare_parts/:uuid ← справочник ЗИП
        ├── /notifications → /notifications_settings
        └── /knowledge_base
```

Навигация построена на **настоящем стеке**: вглубь идут `push`, назад —
`backOr(fallback)`, то есть обычный `pop()` с запасным адресом на случай
пустого стека. Поэтому системная кнопка «назад» и кнопка в `AppBar` ведут себя
одинаково и возвращают на предыдущий экран.

Стек очищают только сбросы — вход, выход, splash и шаги онбординга. После них
корнем становится `/actions` (или `/login`), и всё остальное ложится сверху.

При добавлении экрана: **новый маршрут надо прописать в `app_bar.dart`**, если
его заголовок выводится из строки маршрута.

---

## Инвентарь экранов

| Маршрут | Виджет | Файл | AppBar |
|---|---|---|---|
| `/` | `SplashScreen` | `lib/src/splash/splash_screen.dart` | нет |
| `/login` | `LoginScreen` | `lib/src/login/login_screen.dart` | нет (свой `Positioned` HelpLink) |
| `/onboarding` | `OnboardingWelcomeScreen` | `lib/src/onboarding/onboarding_welcome_screen.dart` | нет |
| `/onboarding_video` | `OnboardingVideoPlayer` | `lib/src/onboarding/onboarding_video_player.dart` | нет (оверлей «Пропустить») |
| `/actions` | `QRActions` | `lib/src/qr/qa_actions.dart` | `MyAppBar` (HelpLink + имя + «Выйти») |
| `/qr_scanner` | `QRScreen` → `BarcodeScannerWithController` | `lib/src/qr/qr_screen.dart` | `MyAppBar` (тёмный) |
| `/qr_result`, `/qr_result_problems`, `/qr_result_demo` | `QRResultScreen` | `lib/src/qr/qr_result_screen.dart` | `MyAppBar` (только `BackButton`) |
| `/tasks`, `/problems` | `EquipmentListScreen` | `lib/src/tasks/equipment_list_screen.dart` | `MyAppBar` («Оборудование») |
| `/details/:index` | `EquipmentDetailScreen` | `lib/src/tasks/equipment_detail_screen.dart` | `MyAppBar` («Задачи») |
| `/notifications` | `NotificationsScreen` | `lib/src/notifications/notifications_screen.dart` | **собственный** `AppBar` |
| `/notifications_settings` | `NotificationsSettingsScreen` | `lib/src/notifications/notifications_settings_screen.dart` | собственный |
| `/knowledge_base` | `KnowledgeBaseScreen` | `lib/src/knowledge_base/knowledge_base_screen.dart` | `MyAppBar` («Помощь») |
| `/repairs` | `RepairsListScreen` | `lib/src/repairs/repairs_list_screen.dart` | `MyAppBar` («Ремонты») |
| `/repairs/:uuid`, `/repair_draft/:localId` | `RepairDetailScreen` | `lib/src/repairs/repair_detail_screen.dart` | **собственный** (номер + пилюля статуса) |
| `/repair_create` | `CreateRepairScreen` | `lib/src/repairs/create_repair_screen.dart` | собственный («Новый ремонт», крестик) |
| `/spare_parts` | `SparePartsScreen` | `lib/src/spare_parts/spare_parts_screen.dart` | `MyAppBar` («ЗИП») |
| `/spare_parts/:uuid` | `SparePartDetailScreen` | `lib/src/spare_parts/spare_part_detail_screen.dart` | собственный |

Плюс не-экранные оверлеи: `_SettingsSheet` (`qa_actions.dart`),
`ScannerDemoModal` (`onboarding/scanner_demo_modal.dart`), фильтр задач
(`tasks/tasks_filter_sheet.dart`, **выключен** флагом), пикер ЗИП
(`repairs/spare_part_picker_sheet.dart`), фильтр справочника ЗИП и
`date_range_sheet.dart` (диапазон дат для истории движения),
`RepairConflictScreen` — открывается как полноэкранный маршрут через
`Navigator.push`, а не `GoRoute`.

---

## Фича: Аутентификация

**Назначение.** Пустить внутрь только обходчика, при этом дать работать без сети.

**Экран.** `/login` — `lib/src/login/login_screen.dart`.

**Поток.**
1. Пользователь вводит логин/пароль → `doLogin()` (`login_screen.dart:50`).
2. `_busy = true` — поля блокируются (`enabled: !_busy`), CTA превращается в
   `CircularProgressIndicator` 22×22.
3. `dataProvider.login(...)` (`data_provider_remote.dart:96`):
   - `api.login()` → `POST /v1/auth/login` → `access_token` + `role`;
   - `api.me(token)` → `GET /v1/user/me` → `effective_role`, `custom_role_id`, `uuid`;
   - при сетевом сбое — фолбэк: искать пару логин/пароль среди `users` в Hive
     (пароль хранится в открытом виде в `UserAdapter`);
   - если ни того ни другого — `NoConnectionException`;
   - если `role != 'walker'` — `WalkerOnlyException`.
4. Успех → `addUser()` + `GlobalState.authUser = currentUser` →
   `mainSync()` → `syncCompany()` → `updateDebug()` →
   `NotificationsService.instance.bootstrap()` →
   `PushNotificationsController.instance.start()`.
5. Навигация: `/onboarding`, если `!Settings.onboardingCompleted`, иначе `/actions`.

**Обработка ошибок (образец для подражания).** Четыре отдельных `on`-ветки, каждая
показывает свой `Dialogs.notify` с парой строк из `Strings`
(`login_screen.dart:73-92`).

**Выход.** `MyAppBar._logout` (`app_bar.dart:21-36`): `Dialogs.areYouSure` →
`authUser = null` → `NotificationsService.instance.onLogout()` →
`PushNotificationsController.instance.stop()` → `clearStackAndNavigate('/login')`.
Локальные данные Hive при выходе **не чистятся**.

**Известные особенности.**
- Пароль пользователя хранится на устройстве в открытом виде (`user.dart:5,46`) —
  осознанная плата за офлайн-вход.
- `Form` на экране есть, но `GlobalKey<FormState>` нет — `validator` у полей
  объявлены, но никогда не вызываются, потому что `validate()` не дёргается.
  Валидация фактически отсутствует.

---

## Фича: Онбординг

**Назначение.** Провести нового обходчика по основному сценарию на демо-данных.

**Экраны.** `/onboarding` (приветствие «Привет, я – Лиза»), `/onboarding_video`
(видеоплеер), демо-модалка поверх сканера, `/qr_result_demo`.

**Машина состояний** живёт в `Settings.onboardingStep` (Hive `stringBox`) и
`Settings.onboardingInProgress` / `onboardingCompleted`:

| Шаг | Что происходит | Кто выставляет следующий |
|---|---|---|
| 1 | видео `assets/onboarding/1.mp4` → `/actions` | `onboarding_video_player.dart:79-82` |
| 2 | пользователь жмёт «Сканер» → на `/qr_scanner` показывается `ScannerDemoModal`, сканирование заблокировано (`qr_screen.dart:104`) | `qr_screen.dart:56-58` ставит шаг 3 |
| 3 | видео `2.mp4` → `/qr_result_demo` с `DemoEquipment.conveyorBelt` | `onboarding_video_player.dart:83-88` |
| 4 | на демо-экране результата «Отправить» не отправляет, а ведёт на видео `3.mp4` (`qr_result_screen.dart:313-318`) → `/actions` | шаг 5 |
| 5 | раскрытие секции «Сервис» на `/actions` → видео `4.mp4` (`qa_actions.dart:154-160`) | шаг 6 + `onboardingCompleted = true` |

**Демо-данные.** `lib/src/onboarding/demo_equipment.dart` — `demoUuid =
'demo-onboarding-conveyor'`. Этот uuid специально распознаётся в
`DataProvider.getTasksForMachine` (`data_provider.dart:187-214`, возвращает две
захардкоженные задачи) и в `QRResultScreen._onStateChanged` /`_submit`
(`qr_result_screen.dart:101-105, 313`). При работе с этими местами **не сломай
демо-ветку**.

**Повтор обучения.** «Настройки» → «Пройти обучение заново» →
`Settings.resetOnboarding()` → `/onboarding` (`qa_actions.dart:722-731`).

---

## Фича: Главный хаб `/actions`

**Файл.** `lib/src/qr/qa_actions.dart` — эталон текущего визуального языка,
переписан в коммите `f8fb99e ui: hub redesign, sticky CTA, notification card accent`.

**Состав (сверху вниз).**
1. `_PrimaryActionCard` — hero-карточка «Сканер» на `cs.primary`, иконка 36px
   в полупрозрачном квадрате 64×64, стрелка справа.
2. Ряд из двух: `_SecondaryActionCard` «Задачи» и `_NotificationsCard`
   (с badge непрочитанных, подписан на
   `NotificationsService.instance.unreadCount`).
3. Опционально `_SecondaryActionCard(fullWidth: true)` «Осмотр оборудования или
   ТМЦ» — только если `company.allowRequestsWithoutQr`.
4. `_ServiceSection` — свёрнутая по умолчанию секция «Сервис» с четырьмя
   `_ServiceItem`: «Синхронизировать данные», «Сбросить осмотры» (destructive),
   «Информация», «Настройки».

**Побочные эффекты при входе** (`initState`, `qa_actions.dart:29-42`):
`NotificationsService.instance.bootstrap()` и
`PushNotificationsController.instance.ensureRunning()` — страховка на случай, если
после установки foreground-сервис не поднялся при логине.

**Сервисные действия.**
- «Синхронизировать данные» → `DataProvider.syncDataAndScans()` → `enum SyncResult`
  (`noConnection` / `allSynced` / `scansSynced` / `scansFailed`) → `Dialogs.notify`
  с соответствующим текстом (`qa_actions.dart:63-78`). **Образец разделения
  логика/UI**: решение принимает `DataProvider`, диалог показывает виджет.
- «Сбросить осмотры» → `scanBox.clear()` + `scanPendingBox.clear()` **без
  подтверждения** — деструктивное действие без `areYouSure`. Расхождение с
  остальным приложением.
- «Информация» → `GlobalState.buildInfo()` → markdown в `Dialogs.notifyMD`:
  доступность сервера, число неотправленных осмотров/наработок, количество ТМЦ,
  пользователь, дата последней синхронизации, версия, время UTC/локальное.
- «Настройки» → `showAppModalSheet(_SettingsSheet())`: два `SwitchListTile`
  + `SegmentedButton<AppThemeId>` (тема) + «Пройти обучение заново» + «Закрыть».

---

## Фича: Сканирование QR

**Экран.** `/qr_scanner` — `lib/src/qr/qr_screen.dart`.

**Реализация.** `mobile_scanner` 7.0.0-beta.7, `MobileScannerController(autoStart:
false, autoZoom: true)`, старт вручную в `initState`. Окно сканирования — квадрат
200×200 по центру (`qr_screen.dart:93-98`), поверх него `ScanWindowOverlay`
**из пакета** `mobile_scanner` (в `lib/` такого класса нет).

**Логика распознавания** (`qr_screen.dart:103-125`):
1. `barcode.displayValue` парсится как JSON, берётся поле `uuid`;
2. линейный поиск по `dataProvider.inventoryRecords` со сравнением
   `machine.uuid.toLowerCase() == barcodeUUID.toLowerCase()`;
3. совпало → `push('/qr_result', extra: machine)` — сканер остаётся под
   карточкой, «назад» возвращает к камере.

Формат QR задан в `InventoryRecord.getQRValue()`:
`{"uuid": "...", "name": "..."}` (`inventory_record.dart:110-112`).

**Если не нашли — ничего не происходит.** `Strings.qrDetectFailTitle` /
`qrDetectFailDesc` («Станок не найден» / «Проверьте QR код актива») объявлены, но
на этом экране **не показываются**. Известный пробел UX.

**Жизненный цикл камеры.** `WidgetsBindingObserver` →
`resumed` → `controller.start()`, `inactive` → `stop()`
(`qr_screen.dart:65-80`).

**Управление.** Нижняя «таблетка» на `Colors.black.withValues(alpha: 0.45)`,
радиус 32, три кнопки: `ToggleFlashlightButton`, `SwitchCameraButton`, `ZoomButton`
(`lib/src/qr/scanner_button_widgets.dart`).

---

## Фича: Экран результата скана — ядро продукта

**Файлы.** `lib/src/qr/qr_result_screen.dart` (state, сборка `Scan`, отправка) +
`lib/src/qr/result_controls.dart` (все контролы формы).

**Структура.**
```
Scaffold
├── appBar: MyAppBar (только BackButton → /qr_scanner или /problems)
├── body: SingleChildScrollView(padding: 8/0/8/16, Column spacing: 8)
│   ├── _HeroPassport      превью 64px + имя + «модель · S/N» + чип состояния
│   │                       + ExpansionTile «Подробнее» (markdown-паспорт)
│   └── ResultControls
│       ├── выбор задачи (SelectTaskButton → EquipmentDetailScreen в модалке)
│       ├── выбор проблемы (_pickProblem → showModalBottomSheet со списком)
│       ├── приоритет (только для «Другое»)
│       ├── комментарий (TextField, подсветка ошибки)
│       ├── _PhotoStrip (3 слота, камера/галерея)
│       └── _UsageList (наработка, только по своей роли)
└── bottomNavigationBar: _SubmitBar (sticky CTA «Отправить»)
```

**Контроллеры формы** создаются в `State` и передаются вниз через конструктор
(`qr_result_screen.dart:39-47`): `descController` (`TextEditingController`),
три `SelectImageButtonController`, `AnyController<Priority>`,
`AnyController<TypicalProblem>`, `EquipmentDetailController`,
`AnyController<List<UsageUpdate>>`, `AnyController<String>` (состояние).

**Взаимоисключение «задача ↔ проблема».** Нельзя выбрать одновременно. При
конфликте показывается `AlertDialog` «Задача и проблема» с вопросом, что отменить
(`qr_result_screen.dart:358-449`). Защита от рекурсии — флаг `_isProcessingConflict`.

**Смена состояния оборудования** происходит **немедленно**, не по кнопке
«Отправить»: слушатель `stateController` → `DataProvider.updateEquipmentState()` →
`PATCH /v1/company/equipment/{uuid}` → снекбар успеха/ошибки
(`qr_result_screen.dart:90-117`). Офлайн-ошибка отличается от прочих текстом.
Эта операция **не ставится в очередь** — без сети состояние не сохранится.

**Сборка отправляемых `Scan`** — `createScans()` (`qr_result_screen.dart:137-241`).
Правила:
- по каждой выбранной задаче создаётся `Scan(resultStatus: 'closed', taskUuid: ...)`;
  для `scheduled` дополнительно проставляется `periodicTaskUuid`;
- «Другое» требует и комментарий, и приоритет — иначе возвращается `null` и
  подсвечиваются `_highlightDescError` / `_highlightPriorityError`;
- отдельный `Scan` для проблемы создаётся, если выполнено одно из:
  (комментарий + «Другое» + приоритет) ИЛИ (типовая проблема) ИЛИ
  (только комментарий без проблемы/приоритета/задач);
- `createdAt` = момент **открытия** экрана (`widget.openDateTime`, проставляется
  роутером как `GlobalState.nowUTCDate`), `closedAt` = момент отправки.

**Отправка** — `_submit()` (`qr_result_screen.dart:312-345`):
демо-режим → видео; ничего не заполнено → `Dialogs.notify` «Не отправлено»;
иначе `Dialogs.areYouSure` → `addScans()` → `mainSync()` → локальное обновление
`currentValue` наработки → `backOr` на `/qr_scanner` или `/problems`
(осмотр отправлен, карточка закрывается).

`addScans()` дополнительно: осмотр со статусом `open` (проблема «Другое» без
`faultUuid`) конвертируется в `PeriodicTaskRequest` с
`params: {'target_type': 'ad_hoc', 'priority': ...}` и кладётся во **вторую**
очередь (`qr_result_screen.dart:243-270`).

**Настройки, влияющие на экран.**
- `Settings.qrResultShowSimplifiedView` → `_HeroPassport(showDetails: false)` —
  скрывает подробный markdown-паспорт (`qr_result_screen.dart:123`).
- `Settings.qrResultShowTasksFirst` → при первой отрисовке, если у оборудования
  есть задачи, автоматически открывается модалка выбора задачи через
  `addPostFrameCallback` + флаг `firstPaint` (`result_controls.dart:216-224`).

**Разметка `ResultControls`** (`result_controls.dart:257-366`) — образец секционной
формы: `_SectionLabel('Что сделано во время обхода')` → `_ActionCard` из
`_ActionRow` (Задачи / Проблема / Приоритет) → секция «Наработка» с `_CountChip`
→ «Комментарий» (`TextFormField`, `minLines: 3`, `maxLines: 6`) → «Фото» с
`_CountChip` и `_PhotoStrip`. Секция приоритета появляется, только если выбрана
проблема «Другое».

---

## Фича: Список оборудования и задачи

**Экраны.** `/tasks` и `/problems` — один и тот же `EquipmentListScreen`
с флагом `isProblems`.

**Поток `/tasks`.**
1. `GlobalState.allowSyncMainOnce = true` ставится на хабе (`qa_actions.dart:55`).
2. Экран рендерит `FutureBuilder(future: GlobalState.syncMainOnce())` —
   то есть синхронизация выполняется **ровно один раз** на вход, пока крутится
   спиннер 128×128.
3. Список фильтруется: остаётся только оборудование, у которого есть активные
   задачи (`_filteredTasksFor(element).length > 0`).
4. Пусто → `EmptyState` с иконкой `checklist_rounded`.
5. Тап → `/details/{equipment.id}`.

**Поток `/problems`** (вход без QR): тот же список, но тап ведёт на
`/qr_result_problems` с тем же оборудованием — то есть открывает форму осмотра
без сканирования. Доступен только при `company.allowRequestsWithoutQr`.

**Карточка `_EquipmentTile`** (`equipment_list_screen.dart:139-262`): иконка
`precision_manufacturing_outlined` 48×48 (фон `primaryContainer`, если есть задачи,
иначе `surfaceContainerHigh`), имя, подзаголовок со **склонением по-русски**
(`_pluralizeTasks`, строки 152-162), справа badge-счётчик на `cs.primary` или
chevron.

**Экран деталей** (`equipment_detail_screen.dart`) группирует задачи по
периодичности (`Checklist`), каждая группа — `Card` с цветной полосой 4px слева.
Цвета берутся из **захардкоженной** `Map<String, Color> periodColors` по
русской строке названия периода (`equipment_detail_screen.dart:11-28`). Порядок
групп задаётся порядком ключей в этой же мапе. Ключ не совпал → задача **не
попадёт** ни в одну группу. Это хрупко и известно.

**Фильтр задач** (`tasks_filter_state.dart` + `tasks_filter_sheet.dart`) написан
полностью — статусы, оборудование, приоритет, диапазон дат — но **отключён**
константой `_kShowTasksFilter = false` (`equipment_list_screen.dart:15`). Внутри
`TasksFilterState.apply` фильтр по приоритету всегда отбрасывает всё, потому что
у `Task` нет поля приоритета (комментарий на строке 88).

---

## Фича: Ремонты

**Папка.** `lib/src/repairs/` — 7 файлов. Самый крупный — `repair_detail_screen.dart`.

**Кто что делает.** Обходчик ремонт создаёт, выполняет, заполняет фактический
расход ЗИП, прикладывает фото и отправляет на рассмотрение. **Закрывает ремонт
и списывает склад администратор в веб-админке** — в приложении такого действия
нет и быть не должно. Статусы: «Открыт» → «На рассмотрении» → «Закрыт»,
возврат «На рассмотрении» → «Открыт» делает администратор.

**Что делает сервер, а не приложение** (не реализуй заново — см.
`data-and-integrations.md`): сужение списка до «моих», перевод оборудования в
`in_repair` и обратно, проверка уникальности активного ремонта.

### Два входа

**1. Из раздела «Ремонты»** (`/repairs`). Список ремонтов, где обходчик
ответственный либо где ремонт назначен на его должность. Фильтр-чипы:
«Открыт» / «На рассмотрении» / «Закрыт», множественный выбор; пустой выбор =
активные. Закрытые подтягиваются отдельным запросом и живут только в памяти
экрана. Черновики из очереди подмешиваются в тот же список отдельной группой.

**2. Из карточки скана** (`/qr_result` → чип состояния → «В ремонте»).
Состояние **не меняется**: выбор открывает `/repair_create`
(`qr_result_screen.dart:312-318`). Причина — сервер сам ставит `in_repair` при
создании ремонта и отклоняет создание для оборудования, которое уже в этом
состоянии; поменяй приложение состояние первым — ремонт станет невозможно
создать. Так же сделано в веб-админке. Отмена формы ничего не отправляет.

Если у оборудования уже есть активный ремонт, чип показывает не список
состояний, а карточку «Оборудование в ремонте» с кнопкой «Открыть ремонт»
(`qr_result_screen.dart:101-190`); поиск идёт по локальному кэшу, поэтому
работает и без сети.

### Форма создания

`CreateRepairScreen` (`/repair_create`, `extra: InventoryRecord`).
Оборудование заблокировано, ответственный — текущий обходчик (только чтение),
норма расхода ЗИП необязательна (только нормы этого оборудования с назначением
«для ремонта», состав виден при выборе), дата и время начала по умолчанию
«сейчас», комментарий необязателен.

Дату и время выбирают **самописные** листы (`showSingleDateSheet`,
`_TimeWheelSheet`), а не `showDatePicker`/`showTimePicker`: без
`flutter_localizations` штатные пикеры показывают английский интерфейс, а
поставить пакет нельзя. Не «чини» это на штатные.

После создания карточка ремонта открывается через `pushReplacement`: форма
своё отработала и в стеке не нужна, а «назад» из карточки уводит туда, откуда
форму открыли. Без связи вместо карточки открывается список — там черновик
виден с пометкой «Не отправлено».

### Карточка ремонта

`RepairDetailScreen` обслуживает **три режима** одним виджетом:
серверный ремонт (`/repairs/:uuid`), локальный черновик
(`/repair_draft/:localId`, `repairUuid` пуст) и ремонт с неотправленной
правкой — она накладывается поверх серверных данных сразу в `initState`, чтобы
форма открылась с цифрами обходчика, а не с серверными.

Редактируется только в статусе «Открыт»: комментарий (2000 символов), фото
(до 10), таблица фактического расхода. В «На рассмотрении» и «Закрыт» — всё
только для чтения с поясняющей плашкой.

**Таблица расхода.** Строка: название ЗИП, плановое количество по норме,
степпер количества, удаление. Цвет количества — красный при превышении нормы,
зелёный при экономии, обычный при совпадении и при отсутствии нормы. Кнопка
«Заполнить из нормы» добавляет недостающие позиции нормы, введённое вручную не
перезаписывает; работает офлайн, потому что состав нормы приходит вложенным в
сам ремонт (`Repair.normItems`).

**Свободный ролевой ремонт.** Если ответственного нет, а должность совпадает с
должностью пользователя, внизу появляется «Взять в работу» → `claimRepair`.

**Отправка** — диалог подтверждения со сводкой (позиций / превышений нормы),
отдельные варианты для «расход не заполнен» и «нет связи».

### Разрешение конфликтов

`RepairConflictScreen` открывается через `Navigator.push(MaterialPageRoute)`,
**а не `GoRoute`** — сознательное исключение из доминирующего
`clearStackAndNavigate`: это модальный тупик, из которого возвращаются назад.

Два случая: оборудование занял чужой ремонт (предложить перенести расход,
комментарий и фото в существующий через `transferDraftToRepair`, либо удалить
черновик) и ремонт уже закрыт администратором (скопировать данные или
удалить). Данные никогда не удаляются молча.

---

## Фича: Справочник ЗИП

**Папка.** `lib/src/spare_parts/`. Вход — плитка на хабе `/actions`.

`SparePartsScreen` — поиск, фильтры (склад, группа номенклатуры, наличие),
сортировка. Работает офлайн: справочник целиком кэшируется боксом
`spare_parts` через `syncSpareParts()` в `mainSync()`.

`SparePartDetailScreen` — реквизиты позиции, остаток пилюлей и **история
движения** с фильтром по диапазону дат (`widgets/date_range_sheet.dart`).
История **не кэшируется** — грузится с сервера по запросу.

Раздел только для чтения: изменить остаток из приложения нельзя.

---

## Фича: Центр уведомлений

**Экран.** `/notifications` — `lib/src/notifications/notifications_screen.dart`.
**Сервис.** `NotificationsService.instance` — `lib/src/notifications/notifications_service.dart`.

**Контракт с бэкендом (важно).** SSE — **только сигнал**, источник правды — REST.
На каждое событие `notification` клиент делает `refreshList()` заново
(`notifications_service.dart:258-262`). То же зафиксировано в
`sampo_smart_backend/docs/mobile_notifications_flow.md`.

**Состояние сервиса** — шесть `ValueNotifier`: `notifications`, `unreadCount`,
`settings`, `isLoading`, `isLoadingMore`, `hasMore`, `hasLoadedOnce`.
`hasLoadedOnce` существует специально, чтобы на холодном старте не мигало
«Уведомлений пока нет» до ответа сервера — **повторяй этот приём в новых списках**
(`notifications_service.dart:31-35`, `notifications_screen.dart:137-139`).

**Поток экрана.**
1. `initState` → `_service.bootstrap()`; подписка скролла на `loadMore()` за 200px
   до конца; `Timer.periodic(30 s)` для пересчёта «Осталось Nч Mм» в пилюлях.
2. `_HeaderRow` — счётчик непрочитанных + переключатель «скрыть прочитанные»
   (сохраняется в `Settings.notificationsHideRead`).
3. Тело: спиннер → `EmptyState` внутри `RefreshIndicator` → `ListView.separated`
   с `NotificationCard`.
4. Тап → `markRead(uuid)` (оптимистично пересобирает элемент списка) → детальный
   лист.

**SSE в основном изоляте.** `openNotificationStream()` →
`GET /v1/company/notifications/mobile/stream` c `Accept: text/event-stream` →
`utf8.decoder` → `LineSplitter` → `SseLineParser`. Есть watchdog: если тишина
дольше 3 минут — принудительный реконнект (`notifications_service.dart:240-254`);
реконнект через 5 секунд после ошибки/закрытия.

---

## Фича: Push-уведомления (Android)

**Три файла, три роли.**

| Файл | Изолят | Роль |
|---|---|---|
| `push/push_notifications_controller.dart` | main | Запуск/остановка foreground-сервиса, разрешения, watchdog 90 с, диагностика |
| `push/notifications_task_handler.dart` | **фоновый** | Держит собственный SSE-коннект, показывает локальные уведомления, дедуп по `notification_uuid` (окно 200) |
| `push/notification_router.dart` | main | Обработка тапа: `navigatorKey`, флаг `_pendingOpen`, подписка на `sendDataToMain` |

**Как поднимается.** `start()` требует: Android, авторизацию, непустой JWT,
непустой `API_ENDPOINT`, выданное `POST_NOTIFICATIONS`. Дальше кладёт
`sse_base_url` и `sse_jwt` в `FlutterForegroundTask.saveData` и стартует сервис
`serviceId: 736251` с колбэком `notificationsForegroundCallback`.

**Как переживает перезагрузку.** `autoRunOnBoot: true`,
`autoRunOnMyPackageReplaced: true` (`push_notifications_controller.dart:54-57`).

**Почему уведомление сервиса «тихое».** `channelImportance: MIN`,
`priority: MIN`, `onlyAlertOnce: true` — полностью скрыть нельзя, Android API 26+
обязывает foreground-service показывать нотификацию.

**Battery optimization не запрашивается автоматически** — только явным действием
из экрана настроек (`requestBatteryOptimizationException`, комментарий на
строках 120-123).

**Три пути тапа по пушу** (все ведут на `/notifications`):
1. `onDidReceiveNotificationResponse` в main-изоляте → `openNotifications()`;
2. `onLocalNotificationBackgroundTap` в фоновом изоляте → сохраняет флаг
   `push_tap_pending` + `launchApp('/notifications')`;
3. холодный старт → `getNotificationAppLaunchDetails()` либо флаг
   `push_tap_pending` → `_pendingOpen = true` → подхватывается `redirect` в
   `main.dart:218-223`.

---

## Фича: База знаний

`/knowledge_base` — `InAppWebView` на константу
`knowledgeBaseUrl = 'https://docs.toir.sampo-smart.ru/m'`
(`lib/src/knowledge_base/knowledge_base_utils.dart:3`).

- Доступен **до входа** (публичный маршрут в `redirect`).
- Таймаут загрузки 20 секунд → экран ошибки с иконкой `cloud_off_rounded`
  и кнопкой «Открыть в браузере» (`url_launcher`, `LaunchMode.externalApplication`).
- `LinearProgressIndicator` высотой 2px, пока `_progress < 1`.
- Вход — виджет `HelpLink` (SVG `assets/images/ix_user-manual.svg` + «Помощь»),
  используется на `/login` и в AppBar `/actions`.

---

## Пограничные случаи, которые уже учтены в коде

| Случай | Как обработан | Где |
|---|---|---|
| Холодный старт: мигание «пусто» до ответа сервера | Флаг `hasLoadedOnce`, спиннер вместо `EmptyState` | `notifications_service.dart:31-35` |
| Двойная отправка осмотра | Флаг `_isSyncingScans` + ключ = md5 содержимого | `data_provider_outbox.dart:35-41`, `scan.dart:19` |
| Осмотр «завис» в pending при убийстве приложения | При старте всё из `pending_scans` возвращается в `scans` | `main.dart:155-158` |
| Отправка не подтвердилась | Возврат из pending в основной бокс через 120 с | `data_provider_outbox.dart:44-63` |
| Задача ТО уходит раньше наработки | Пропуск отправки, пока есть pending-наработка по тому же оборудованию | `data_provider_outbox.dart:69-88` |
| SSE «тихо умер» | Watchdog: 3 минуты тишины → реконнект (в обоих изолятах) | `notifications_service.dart:240-254` |
| Foreground-сервис прибит OEM | Watchdog 90 с + `ensureRunning()` на каждый resume | `push_notifications_controller.dart:153-178`, `app_lifecycle.dart:53-55` |
| Битая кириллица от сервера | `Utf8Decoder(allowMalformed: true)` на всех GET | `src/http/*.dart` |
| Ломаный рендер кириллицы на Samsung/Xiaomi | Запрет глобального `FontFeature.tabularFigures()` | `app_theme.dart:358-368` |
| Старые записи Hive без нового поля | `try/catch` вокруг лишнего `reader.read()` | `scan.dart:86-91`, `repair.dart:271-283` |
| Нет фото у оборудования | Лайтбокс не открывается, `errorBuilder` → `broken_image_outlined` | `qr_result_screen.dart:508-528` |
| Обновление приложения обнуляло базу Hive | Путь без версии + одноразовый перенос боксов с маркером `.migrated` | `data/hive_storage_location.dart` |
| Повторная отправка ремонта после потери ответа | `Idempotency-Key` = `PendingRepair.localId`; сервер возвращает уже созданный ремонт | `repair_api.dart:123-166` |
| Обрыв связи посреди загрузки фото ремонта | По одному файлу на запрос + свой ключ идемпотентности; принятый путь сразу вычёркивается | `data_provider_outbox.dart:136-171` |
| Приложение убито между созданием ремонта и загрузкой фото | `serverUuid` пишется в черновик **до** фото — повторный проход не создаст второй ремонт | `data_provider_outbox.dart:49-64` |
| Оборудование заняли, пока обходчик был офлайн | Черновик помечается отклонённым, ищется занявший ремонт, открывается экран разрешения конфликта | `data_provider_outbox.dart:203-219`, `repairs/repair_conflict_screen.dart` |
| Протух токен во время работы очереди | `AuthExpiredException` вместо отказа: черновик цел, поднят флаг `authExpired`, баннер в списке | `api.dart:96-105` |
| Перевод оборудования «В ремонте» без сети | Идёт через создание ремонта, а значит через очередь; локально оборудование сразу помечается как в ремонте | `qr_result_screen.dart:312-318`, `data_provider.dart` |

## Что фактически не обработано

- QR не найден в локальном списке — **молчание** (строки `qrDetectFailTitle` есть, показа нет).
- Смена состояния оборудования офлайн — только снекбар «нет интернета», в очередь не встаёт.
  Исключение — перевод «В ремонте», он идёт через очередь ремонтов.
- «Сбросить осмотры» — деструктивно, без подтверждения.
- Валидация формы логина — `validator` есть, `FormState.validate()` не вызывается.
- Задача с неизвестным названием периодичности не попадает ни в одну группу на `/details`.
- Черновик ремонта хранится в очереди без срока давности: если обходчик не
  выходил на связь неделю, оборудование числится в ремонте только локально.
