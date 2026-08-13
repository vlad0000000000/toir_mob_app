---
name: flutter-project-context
description: Project-specific source of truth for this Flutter mobile application. Use before planning, explaining, reviewing, debugging, testing, or changing any application code, architecture, functionality, dependencies, UI, UX, localization, integrations, tests, builds, or release behavior in this repository. Consult this skill automatically for every project-related task.
---

# Контекст проекта: мобильное приложение «Обходчик» (`qr_scan_industry`)

Источник правды по этому Flutter-приложению. Всё ниже выведено из текущего кода,
конфигов и git-истории репозитория `sampo_smart_mobile`, а не из общих практик Flutter.

**Что это за приложение в одном абзаце.** Android-приложение для обходчика на
производстве: сканирует QR-код оборудования, закрывает задачи ТО/осмотра, фиксирует
проблемы и наработку, меняет состояние оборудования, получает уведомления. Работает
офлайн — всё пишется в Hive и уходит на бэкенд Sampo Smart через очередь. Язык
интерфейса только русский, ориентация только портретная, тема только светлая,
единственная допустимая роль пользователя — `walker`.

---

## Обязательный порядок работы

Перед тем как что-то планировать, объяснять или менять:

1. **Определи область.** Какая фича, какой экран, какой слой (`lib/src/http/`,
   `lib/src/data/`, `lib/src/model/`, экран, `lib/src/design/`).
2. **Прочитай только релевантные справочники** из `references/` (таблица ниже).
   Не читай всё подряд.
3. **Открой сами файлы реализации**, которые затрагивает задача. Справочник может
   отставать от кода; побеждает код.
4. **Найди 1–2 существующих прецедента** — экран или виджет, который уже решает
   похожую задачу, и повторяй его форму. Прецеденты перечислены в
   `references/ui-ux-system.md` и `references/features-and-flows.md`.
5. **Переиспользуй существующее**: `AppConstants`, `Theme.of(context).colorScheme`,
   `EmptyState`, `showAppModalSheet`, `Dialogs`, `ControllerListenerMixin`,
   `AnyController<T>`, `clearStackAndNavigate`. Не пиши свой аналог.
6. **Не вводи новое** — пакет, слой абстракции, подход к состоянию, визуальный
   паттерн, структуру папок — если задача явно этого не требует.
7. **Когда сосуществуют старый и новый паттерн — следуй доминирующему**
   (`references/code-conventions.md`, раздел «Что считать образцом»).
8. **Сохраняй** русские строки, состояния загрузки/пустоты/ошибки, поведение
   офлайн-очереди и совместимость Hive-формата.
9. **Прогони проверки** после правки (`references/testing-build-and-release.md`).
   Минимум: `flutter analyze` должен остаться на прежнем 1 предупреждении.
10. **Назови отклонения.** Если пришлось отойти от текущей конвенции — скажи об
    этом явно и объясни почему.
11. **Обнови справочники**, если задача осознанно поменяла стабильное знание
    (архитектуру, навигацию, дизайн-систему, терминологию) —
    см. `references/maintenance-guide.md`.

---

## Какой справочник читать

| Задача | Читать |
|---|---|
| «Что вообще делает приложение», термины, роли | `references/project-overview.md`, `references/project-glossary.md` |
| Новый экран, новая фича, изменение потока | `references/features-and-flows.md` + `references/architecture.md` |
| Работа с API, Hive, синхронизацией, офлайном | `references/data-and-integrations.md` + `references/architecture.md` |
| Правка UI, цветов, отступов, состояний экрана | `references/ui-ux-system.md` |
| Как писать код, чтобы он не выделялся | `references/code-conventions.md` |
| Сборка, .env, подпись, тесты, релиз | `references/testing-build-and-release.md` |
| «Почему тут так странно», что непроверено | `references/evidence-and-unknowns.md` |
| Правка самого скилла | `references/maintenance-guide.md` |

---

## Правила принятия решений

- **Исполняемый код — первичный источник правды.** Документация (включая этот
  скилл, `REFACTORING_CHECKLIST.md`, `lib/src/design/README.md`) авторитетна
  только пока совпадает с кодом.
- **`lib/src/design/README.md` — не документация проекта.** Это боилерплейт
  генератора тем, описывающий структуру, которой в проекте нет
  (`lib/theme/`, dark mode, `context.gapMD`). Не следуй ему.
- **Генерируемый код — не образец стиля.** `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`,
  `ios/Runner/GeneratedPluginRegistrant.*`, `.dart_tool/`, `build/` — не трогать
  и не цитировать как конвенцию. В `lib/` кодогенерации **нет вообще**:
  Hive-адаптеры написаны руками (см. ниже).
- **Готовые компоненты приоритетнее ручной сборки UI.** Пустой список — это
  `EmptyState`, а не собранный на месте `Column`. Нижний лист — это
  `showAppModalSheet`, а не голый `showModalBottomSheet`.
- **Токены приоритетнее хардкода.** Отступ — `AppConstants.spacingMD`, а не `16`.
  Цвет — `Theme.of(context).colorScheme.primary`, а не `Colors.green`.
- **Навигация делится на два вида, и путать их нельзя.** Переход вглубь
  (хаб → раздел → карточка) — `push`: предыдущий экран остаётся в стеке, и
  «назад» возвращает на него сам. Сброс (вход, выход, шаги онбординга,
  отправка осмотра) — `clearStackAndNavigate`: возвращаться некуда и не нужно.
  Кнопка «назад» — всегда `backOr(fallback)`, а не жёсткий адрес.
- **Устаревшее не сохраняем вслепую.** `theme_extensions.dart`,
  семейство `select_*_button` — мёртвые или почти мёртвые. Не расширяй их;
  если пришлось коснуться — зафиксируй это в `references/evidence-and-unknowns.md`.
- **Никогда не выдумывай поведение продукта.** Нет в коде — значит неизвестно.
  Спрашивай или помечай как unknown. `ПЛАН_РЕМОНТЫ_ЗИП.md` — исходный план
  фичи «Ремонты и ЗИП», местами разошедшийся с реализацией; при расхождении
  правда за кодом (расхождения перечислены в `features-and-flows.md`).
- **При неуверенности — читай ещё код и записывай unknown**, а не угадывай.
- **В скилл идёт стабильное знание.** Детали конкретной задачи, временные
  обходные пути и «сегодня не собралось» — не идут.

---

## Пять фактов, которые ломают работу, если их не знать

1. **Hive без кодогенерации.** Каждый `TypeAdapter` в `lib/src/model/*.dart`
   написан руками: `read()` читает поля **строго в том порядке**, в котором их
   пишет `write()`. Добавление поля, смена порядка или смена типа ломает данные на
   устройствах пользователей. Единственный безопасный приём — дописать поле
   **в конец** `write()` и прочитать его в `read()` через `try/catch`
   (образец: `lib/src/model/scan.dart:86-91`, поле `isOtherFault`).
   `typeId` уникальны и переиспользованию не подлежат.

2. **Путь к базе Hive считает `HiveStorageLocation.resolve`**
   (`lib/src/data/hive_storage_location.dart`), а не `main.dart`. Имя каталога —
   md5 от `appName|packageName`, **без версии**, поэтому обновление приложения
   базу больше не обнуляет. При первом запуске сборки с этой схемой боксы
   переносятся из каталога прошлой версии, факт переноса помечается файлом
   `.migrated` внутри каталога. Не возвращай версию в состав пути и не удаляй
   маркер — повторный перенос затрёт свежие данные старыми.

3. **`.env` в корне проекта обязателен и читается дважды.** Из Dart — через
   `dotenv.load()` в `lib/main.dart:83`; из Gradle — как `java.util.Properties`
   в `android/app/build.gradle:9-13`. Gradle **на этапе конфигурации** создаёт
   `signingConfigs.release` из `SIGN_*`, поэтому без валидного keystore падает
   даже debug-сборка. Обязательные ключи: `API_ENDPOINT`, `API_USER`,
   `API_PASSWORD`, `APP_TITLE`, `APP_ID`, `APP_VERSION_CODE`, `APP_VERSION_NAME`,
   `SIGN_STORE_FILE`, `SIGN_STORE_PASS`, `SIGN_KEY_ALIAS`, `SIGN_KEY_PASS`.

4. **Линтера фактически нет.** `analysis_options.yaml:1` подключает
   `package:analysis_defaults/flutter.yaml`, которого нет в зависимостях, — include
   не резолвится, набор `linter.rules` не применяется. Работают только штатные
   диагностики анализатора. Значит: «так делает анализатор» — не аргумент,
   ориентируйся на форму соседнего кода.

5. **`flutter test` в этом репозитории красный.** Единственный файл
   `test/widget_test.dart` полностью закомментирован, в нём нет `main()`, и запуск
   падает с `Undefined name 'main'`. Это состояние на момент анализа, а не
   поломка от твоих правок. Тестов в проекте нет.

---

## Рецепты типовых задач

Короткие чек-листы. Детали и образцы — в справочниках.

### Новый экран

1. Виджет в подпапку по фиче: `lib/src/<фича>/<имя>_screen.dart`.
2. `GoRoute` в `MyApp._router` (21 маршрут): `pageBuilder`, возвращающий
   `NoTransitionPage`. Анимации переходов в приложении нет — `builder` не
   используй, он даст штатный Material-переход.
3. **Ветка в `MyAppBar.build`** (`lib/src/app_bar/app_bar.dart:43-160`) — иначе
   экран получит дефолтный тёмный AppBar с одной кнопкой «Выйти».
   Исключение: если заголовок зависит от данных (номер ремонта, пилюля
   статуса), экран строит собственный `AppBar` и ветка не заводится — так
   сделаны карточки ремонта и ЗИП, там же в `app_bar.dart` оставлен
   поясняющий комментарий.
4. Маршрут по умолчанию защищённый; публичный — добавить в условие
   `isGoingToProtectedRoute` в `redirect` (`main.dart:240-242`).
5. Переход вглубь — `GoRouter.of(context).push('/путь')`; кнопка «назад» —
   `GoRouter.of(context).backOr('/запасной_путь')`. Сброс стека нужен только
   для входа, выхода и онбординга.
6. Прецедент по типу экрана — таблица в `references/ui-ux-system.md`.

### Новый эндпоинт / серверный справочник

1. Метод — extension в существующем part-файле `lib/src/http/*_api.dart`
   (новый домен → новый part + строка `part` в `api.dart`). Шаблон метода —
   `references/code-conventions.md`.
2. Модель в `lib/src/model/` с `fromJson`.
3. Если нужен офлайн: рукописный `TypeAdapter` (новый `typeId`) →
   регистрация в `main.dart:117-144` → открытие бокса в `main.dart:148-172` →
   поле в конструкторе `DataProvider`.
   Одиночное значение или флаг — клади в `stringBox`, отдельный бокс ради него
   не заводи. Для коллекции сущности типизированный бокс — рабочий вариант:
   так сделаны ЗИП и ремонты (`typeId` 22–28). Формат при этом обязан
   меняться только дописыванием поля в конец (см. `code-conventions.md`).
4. `sync<X>()` в `data_provider_sync.dart` по образцу `syncUsageUnitTypes` +
   вызов в `mainSync()`.
5. Если данные держатся в памяти — обнови кэш `DataProvider` после записи
   (как `updateInventoryRecords()`).

### Новая отправляемая сущность (офлайн-очередь)

Общее: модель с `key()`, `add<X>()` в `DataProvider`, `sync<X>()` в
`data_provider_outbox.dart`, вызов в цикле `startScanSyncing`, учёт в
отладочной полосе и `GlobalState.buildInfo()`. Дальше — по тому, есть ли у
отправки побочный эффект на сервере:

- **нет** (осмотр, наработка, ad-hoc задача) → пара боксов `<x>` +
  `pending_<x>`, возврат из pending через 120 с. Образец `syncPeriodicTasks`,
  модель `usage_update.dart` (`key()` = md5 содержимого);
- **есть** (ремонт: сервер меняет состояние оборудования и шлёт уведомления) →
  один бокс и `Idempotency-Key` вместо таймаута. Образец `syncPendingRepairs`
  (`data_provider_outbox.dart:25-113`). Четыре правила: ключ считается один
  раз при создании и не меняется; многошаговая отправка фиксирует прогресс в
  боксе после каждого шага (у ремонта `serverUuid` пишется **до** фото);
  отказ сервера отличается от отсутствия связи (`isRetryableRepairError`);
  отклонённое не повторяется автоматически, причина хранится по-русски.

### Правка UI существующего экрана

1. `references/ui-ux-system.md` → нужный паттерн (карточка / пилюля / badge /
   липкая панель / состояние экрана).
2. Цвета — `cs.*` и `AppSemanticColors`; отступы и радиусы — `AppConstants.*`.
3. Ничего, что уже задано под-темой (`Card`, `TextField`, `AppBar`,
   `ElevatedButton`, `SnackBar`), локально не переопределяй.
4. Пустой список — `EmptyState`; нижний лист — `showAppModalSheet`;
   подтверждение — `Dialogs.areYouSure`.

### Рефакторинг без изменения поведения

1. Прочитай `REFACTORING_CHECKLIST.md` — там записано, что уже сделано и что
   **осознанно отложено**.
2. Не начинай переезд папок (Phase 8) попутно.
3. Не трогай `read`/`write` Hive-адаптеров.
4. `flutter analyze` должен остаться на 2 предупреждениях.

## Быстрая карта репозитория

```
lib/
  main.dart                 точка входа + весь GoRouter (21 маршрут) + MyApp
  global_state.dart         статики: dataProvider, authUser, debug, hasConnectionToServer
  settings.dart             пользовательские настройки поверх Hive stringBox
  strings.dart              частичная локализация (Strings + Repair*/Conflict*/SparePart*)
  src/
    http/        api.dart + 7 part-файлов (auth/equipment/task/scan/
                 notifications/repair/spare_part)
    data/        data_provider.dart + 3 part-файла (remote/sync/outbox)
                 + hive_storage_location.dart, repair_photo_files.dart
    model/       26 файлов моделей + 28 рукописных Hive-адаптеров
    design/      app_constants.dart (токены), app_theme.dart (2 схемы)
    widgets/     переиспользуемые виджеты
    utils/       AnyController, Dialogs, go_router_ext, Dependent
    app_bar/     MyAppBar.build(context) — один AppBar на большинство экранов
    qr/          сканер + экран результата скана (ядро продукта)
    tasks/       список оборудования + карточка задач
    repairs/     список, карточка, создание, конфликт, пикер ЗИП
    spare_parts/ справочник ЗИП + карточка позиции с историей движения
    notifications/ центр уведомлений, SSE, foreground-service push
    onboarding/  4 видео + демо-оборудование
    login/  splash/  knowledge_base/  app_lifecycle/  exceptions/  style/
```

Подробности — в `references/architecture.md`.

---

## Что запускать после правки

```bash
flutter pub get
flutter analyze     # эталон: ровно 1 warning (include_file_not_found в analysis_options.yaml)
flutter run -d <device>
```

`dart format` — **не запускать по всему проекту**: 38 из 95 файлов не отформатированы,
массовый прогон создаст нечитаемый диff. Форматируй только файлы, которые правишь.
Подробности и подводные камни сборки — `references/testing-build-and-release.md`.
