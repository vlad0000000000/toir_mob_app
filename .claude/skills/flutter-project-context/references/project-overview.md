# Обзор продукта

## Назначение

Мобильное приложение **«Обходчик»** — клиентская часть системы ТОиР (техническое
обслуживание и ремонт) **Sampo Smart**. Пользователь — рабочий на производстве,
который физически обходит оборудование: сканирует QR-код на станке, видит его
паспорт и назначенные задачи, закрывает осмотры, фиксирует неисправности, вносит
показания счётчиков наработки и меняет состояние оборудования.

Ключевые продуктовые ограничения, заложенные в код:

- **Только офлайн-устойчивая работа.** Всё, что вводит обходчик, сначала ложится в
  Hive и только потом уходит на сервер через очередь с ретраями
  (`lib/src/data/data_provider_outbox.dart`). Потеря связи не должна терять данные.
- **Только роль `walker`.** Пользователь с любой другой ролью получает
  `WalkerOnlyException` и не пускается внутрь
  (`lib/src/data/data_provider_remote.dart:151-156`).
- **Только русский язык.** `Strings.locale = 'ru'` (`lib/strings.dart:2`),
  `flutter_localizations` не подключён.
- **Только портрет.** `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])`
  (`lib/main.dart:74-76`).
- **Только светлая тема.** `themeMode: ThemeMode.light` (`lib/main.dart:416`),
  `darkTheme` не передаётся в `MaterialApp`.
- **Работа в перчатках при плохом освещении.** Отсюда крупные тап-таргеты
  (≥48px, primary CTA 52–56px) и высокий контраст — см.
  `lib/src/design/app_theme.dart:21-27` и `ПЛАН_РЕМОНТЫ_ЗИП.md`, раздел «Промт 0».

## Тип пользователя

Один: **обходчик** (`walker`). Разграничения внутри приложения нет — есть только
`effectiveRole` и `customRoleId`, которые используются для **фильтрации задач**, а не
для доступа к экранам:

- `Task.resultStatus == 'scheduled'` показывается, если `periodicTask.customRoles`
  содержит `customRoleId` пользователя;
- `Task.resultStatus == 'open'` показывается, если `responsibleUser.uuid` совпадает
  с `uuid` пользователя.

Источник: `lib/src/data/data_provider.dart:222-241`.

Наработку (`usage_parameters`) обходчик видит только по тем параметрам, у которых
`maintenanceRole.name == authUser.effectiveRole`
(`lib/src/qr/result_controls.dart:74-79`).

## Основные бизнес-сущности

| Сущность | Класс | Файл | Назначение |
|---|---|---|---|
| Оборудование / ТМЦ | `InventoryRecord` | `lib/src/model/inventory_record.dart` | Паспорт станка: имя, модель, S/N, локация, фото, состояние, параметры наработки |
| Задача | `Task` | `lib/src/model/task.dart` | Осмотр или ТО. Статусы `open` / `scheduled` / `closed` |
| Периодическая задача | `PeriodicTask` | `lib/src/model/periodic_task_models.dart` | Правило повторения, роли-исполнители, сроки |
| Осмотр (отправляемый) | `Scan` | `lib/src/model/scan.dart` | То, что обходчик отправляет: комментарий, фото, проблема, приоритет |
| Наработка | `UsageParameter` / `UsageUpdate` | `lib/src/model/inventory_record.dart`, `usage_update.dart` | Счётчик (моточасы, км и т.п.) и его обновление |
| Типовая проблема | `TypicalProblem` | `lib/src/model/typical_problem.dart` | Справочник неисправностей, привязан к оборудованию |
| Состояние оборудования | `EquipmentState` | `lib/src/model/equipment_state.dart` | Словарь `код → название` («В работе», «В ремонте», …) |
| Уведомление | `AppNotification` | `lib/src/model/notification.dart` | Элемент центра уведомлений |
| Компания | `Company` | `lib/src/model/company.dart` | Тариф + фича-флаг `allowRequestsWithoutQr` |
| Пользователь | `User` | `lib/src/model/user.dart` | Логин, роль, JWT, `customRoleId` |
| Сессия инвентаризации | `Session` | `lib/src/model/session.dart` | Активная инвентаризация компании |
| Ремонт | `Repair` | `lib/src/model/repair.dart` | Статусы `open` / `under_review` / `closed`, ответственный или должность, фактический расход, фото |
| Черновик ремонта | `PendingRepair` | `lib/src/model/pending_repair.dart` | Ремонт, созданный офлайн и ждущий отправки; `localId` = `Idempotency-Key` |
| Отложенная правка ремонта | `PendingRepairUpdate` | `lib/src/model/pending_repair_update.dart` | Одна на ремонт, перезаписывается при повторной правке |
| ЗИП (запчасть) | `SparePart` | `lib/src/model/spare_part.dart` | Позиция номенклатуры: артикул, единица, остаток, склад, группа |
| Норма расхода ЗИП | `ConsumptionNorm` | `lib/src/model/consumption_norm.dart` | Плановый состав по оборудованию, назначение «для ремонта» |
| Движение ЗИП | `StockHistoryEntry` | `lib/src/model/stock_history_entry.dart` | Строка истории склада (приход, списание, корректировка) |

Полные определения терминов — `project-glossary.md`.

## Поддерживаемые платформы

| Платформа | Статус | Основание |
|---|---|---|
| **Android** | Единственная реально поддерживаемая | `Dockerfile` собирает только APK; весь push/foreground-код за `Platform.isAndroid` (`lib/src/notifications/push/push_notifications_controller.dart:30,68,135`) |
| iOS | Каркас есть, не сопровождается | `ios/` существует, но содержит чужие артефакты (`GoogleService-Info.plist`, `firebase_app_id_file.json`); push-подсистема отключена на не-Android |
| Web | Каркас есть, деградированный режим | Ветки `kIsWeb` в `main.dart:69,101` и `push_notifications_controller.dart`; Hive инициализируется без кастомного пути |

Считать проект **Android-only**, если задача явно не про другую платформу.

## Точки входа

- `lib/main.dart` → `main()` — единственная точка входа. Делает всё:
  1. настройка `logging` (`Level.WARNING` в release),
  2. `FlutterForegroundTask.initCommunicationPort()` + `PushNotificationsController.instance.init()` + `PushNotificationRouter.init()` (только не-web),
  3. фиксация портретной ориентации,
  4. `dotenv.load(fileName: ".env")`,
  5. вычисление пути Hive через `HiveStorageLocation.resolve(packageInfo)`
     (`main.dart:112`; md5 от `appName|packageName`, **без версии**) + разовый
     перенос базы со старой схемы,
  6. регистрация **28** `TypeAdapter`,
  7. открытие **20** боксов и сборка `DataProvider`,
  8. перенос «зависших» `pending_scans` обратно в `scans`,
  9. публикация `GlobalState.dataProvider` и `Settings.dataProvider`,
  10. восстановление темы из `Settings.themeId`,
  11. запуск двух вечных циклов (`startSyncing` 60 с, `startScanSyncing` 5 с) и цикла обновления debug-строки (15 с),
  12. `runApp(MyApp(...))`.
- `lib/main.dart` → `MyApp` — `ScreenUtilInit` → `AppLifecycleObserver` → `MultiProvider`
  → `MaterialApp.router` + нижняя отладочная полоса статуса.
- `lib/src/notifications/push/notifications_task_handler.dart:15`
  `notificationsForegroundCallback()` — **вторая** точка входа, изолят
  foreground-сервиса (`@pragma('vm:entry-point')`).

## Флаги окружения и фича-флаги

| Флаг | Где | Что делает |
|---|---|---|
| `API_ENDPOINT` | `.env` → `API.baseUrl`, `PushNotificationsController.start()` | Базовый URL бэкенда |
| `APP_TITLE` | `.env` → `MaterialApp.title`, `AndroidManifest` `android:label` | Заголовок приложения |
| `APP_ID`, `APP_VERSION_*`, `SIGN_*` | `.env` → `android/app/build.gradle` | Идентификатор, версия, подпись |
| `Company.allowRequestsWithoutQr` | сервер → `lib/src/qr/qa_actions.dart:106-107,141-149` | Показывает плитку «Осмотр оборудования или ТМЦ» (вход без сканирования) |
| `API.simulateOffline` | `lib/src/http/api.dart:61` | Отладочный рубильник: `isAlive()` → `false`, остальные методы бросают `SocketException` |
| `_kShowTasksFilter` | `lib/src/tasks/equipment_list_screen.dart:15` | Фильтр задач написан, но выключен константой |
| `Settings.qrResultShowTasksFirst`, `qrResultShowSimplifiedView`, `notificationsHideRead`, `themeId` | Hive `stringBox` | Пользовательские переключатели в «Настройках» |

## Главные фичи

1. **Вход** — логин/пароль, JWT, офлайн-фолбэк на локально сохранённых пользователей.
2. **Онбординг** — 4 видео + демо-оборудование «конвейерная лента», сквозной сценарий.
3. **Сканирование QR** — `mobile_scanner`, поиск по `uuid` в локальном списке оборудования.
4. **Экран результата скана** — паспорт оборудования, задачи, проблема, приоритет, фото, наработка, смена состояния, отправка.
5. **Список оборудования / задач** — группировка по периодичности, счётчики.
6. **Ремонты** — создание из карточки скана и работа по назначенным; фактический
   расход ЗИП, фото, отправка на рассмотрение. Полностью работает офлайн через
   собственную очередь с идемпотентностью и разрешением конфликтов.
   Закрытие ремонта и списание склада — только у администратора в веб-админке.
7. **Справочник ЗИП** — поиск, фильтры, карточка позиции с историей движения.
   Только для чтения.
8. **Центр уведомлений** — список с пагинацией, фильтр «скрыть прочитанные», настройки, SSE realtime.
9. **Push-уведомления** — Android foreground-service держит SSE, показывает локальные уведомления, роутит тап на `/notifications`.
10. **База знаний** — `InAppWebView` на `https://docs.toir.sampo-smart.ru/m`.
11. **Сервисные операции** — ручная синхронизация, сброс осмотров, диагностическая карточка «Информация», настройки, повтор обучения.

Детально — `features-and-flows.md`.

## Ключевые проектные ограничения

- **Формат Hive нельзя менять «на месте».** См. п.1 в `SKILL.md`.
- **Одиночные значения и флаги — в `stringBox`**, отдельный бокс ради них не
  заводить. Коллекция сущности вправе получить свой типизированный бокс —
  прецедент есть (ЗИП и ремонты, `typeId` 22–28).
- **Цвета и отступы — только из существующей дизайн-системы**, новых констант не
  заводить.
- **Строки интерфейса — в `lib/strings.dart`**, класс на фичу
  (`RepairStrings`, `SparePartStrings`); фактически же ~340 русских литералов
  из ~407 сидят прямо в виджетах старых экранов.
- **Статический анализ должен остаться без новых замечаний** — эталон 1 warning.
- **Публичные пути API менять нельзя** — контракт держит бэкенд `sampo_smart_backend`.
- **Закрытие ремонта и списание ЗИП в приложении не реализуются** — это
  действие администратора в веб-админке.

## Ссылки на репозиторий

- `README.md` — три строки: перед сборкой создать `.env` с `API_ENDPOINT`.
- `REFACTORING_CHECKLIST.md` — журнал поэтапного рефакторинга (Phase 1–8), что
  сделано и что осознанно отложено. Читать перед любой реструктуризацией.
- `ПЛАН_РЕМОНТЫ_ЗИП.md` — исходный план фичи «Ремонты и ЗИП» (датирован
  31.07.2026). Фича **реализована**, и план местами разошёлся с кодом
  (хранение, фильтрация «моих», ответственная должность) — при расхождении
  правда за кодом. Ценен двумя вещами: зафиксированный заказчиком контракт
  дизайн-системы (раздел «Промт 0») — самый подробный текстовый источник по
  токенам — и объяснение, почему у ремонтов такая офлайн-механика.
- `lib/src/design/README.md` — боилерплейт генератора тем, **не** документация
  проекта. Игнорировать.
- `shorebird.yaml` — конфигурация code-push (Shorebird), `app_id` публичный.
- `docker-compose.yml` + `Dockerfile` — контейнерная сборка APK в `./build_output`.
