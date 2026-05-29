# Чек-лист рефакторинга `lib/`

> Порядок — от безопасного к рискованному. После каждого пункта: `flutter analyze` зелёный, поведение не меняется (если не указано иное).
> Корневая причина большинства проблем: **нет слоёв** — UI напрямую дёргает Hive и `API`, состояние на глобальных статиках. Самый ценный, но рискованный пункт — слой данных (Phase 6).

---

## Phase 1 — Мёртвый код (риск ≈ 0)

- [x] Удалить `src/model/inventory_scan.dart` (мёртвый `ScanAdapter` с дублем `typeId=2`, единственная ссылка — закомментирована)
- [x] Удалить `src/qr_tab_screen/` (демо-код «Content for Tab 2», в роутере только в комментариях)
- [x] Убрать дубли-геттеры в `src/style/palette.dart` (`backgroundMain2`/`textColor2`) + стереть game-template комментарий
- [x] Удалить недостижимый `return` в `src/widgets/select_image_button.dart:83-92`
- [x] Удалить мёртвые `lastIncoming` и `_onForegroundNotification` в `src/notifications/notifications_service.dart` (+ упростить `_dispatchSseEvent`)
- [ ] ~~Решить судьбу `src/update_manager.dart`~~ — **отложено**: отключён намеренно (Shorebird?), снос вызовов меняет поведение, нужно решение пользователя
- [ ] Снести крупные блоки закомментированного кода — **отложено до Phase 3** (всё равно режем эти god-файлы)

## Phase 2 — Импорты и имя пакета

- [ ] Единый стиль импортов: всё на `package:...` — **свёрнуто в Phase 8** (переезд файлов всё равно перепишет импорты)
- [x] Переименовать пакет `my_app` → `qr_scan_industry` (`pubspec.yaml` + 9 вхождений `package:my_app/` в 5 файлах)

## Phase 3 — Разбить god-файлы (git mv + барреллы, риск ≈ 0)

- [x] `api.dart` (952) → ядро + `auth_api`/`equipment_api`/`task_api`/`scan_api`/`notifications_api` (part-файлы + extension на API; вызовы `api.method()` не менялись)
- [x] `data_provider.dart` (724) → ядро + `data_provider_remote`/`_sync`/`_outbox` (part + extension). NB: extension-методы требуют прямого импорта библиотеки в местах вызова — добавил импорты в `qa_actions`/`qr_result_screen`
- [x] `tasks.dart` (824) → `task_models` + `equipment_detail_controller` + `equipment_list_screen` + `equipment_detail_screen`; `tasks.dart` стал барреллом (реэкспорт, call-sites не трогали)
- [x] `tasks_filter.dart` (765) → `tasks_filter_state` (модель) + `tasks_filter_sheet` (UI); `tasks_filter.dart` стал барреллом
- [x] `qr_result_screen.dart` (988→~660) → вынесены `ResultControls` + `YandexImage` в `result_controls.dart`. NB: глубокий section-split (state/problem/photos/tasks) отложен — требует вытаскивать методы State в виджеты (риск)
- [x] `notifications_screen.dart` (679→~360) → `notification_formatters` (статики) + `notification_card` (карточка+бейджи); устранён cross-class доступ к приватным статикам State

## Phase 4 — Дедупликация

- [x] `ControllerListenerMixin` — вынесен дублирующийся initState/dispose/listener boilerplate из 6 `select_*`-виджетов. NB: полный generic `SelectButton<T>` (слияние dropdown'ов) + замена самописных `*Controller` на `AnyController` — отложено (бо́льший рефактор UI)
- [ ] `SseConnection` — общий для `notifications_service` (main isolate) и `notifications_task_handler` (background)
- [x] `showAppModalSheet()` (`widgets/app_bottom_sheet.dart`) — подключён ко всем 4 совпадающим точкам (`select_task_button`, `select_usage_button`, `qa_actions` settings, `equipment_detail` фото-вьюер). Прочие sheet'ы (DraggableScrollableSheet, ScannerDemoModal) — другой паттерн, не трогали
- [x] `HelpLink` — общий виджет `widgets/help_link.dart` (подключён в `app_bar.dart` + `login_screen.dart`, убран дубль + лишний `flutter_svg`)
- [x] Один `_buildTaskItem` вместо `_buildTaskItem`/`_buildOpenTaskItem` (null-safe title, `equipment_detail_screen.dart`)

## Phase 5 — Тема и дизайн-система

- [ ] Решить судьбу `theme/app_theme.dart` (orphaned, 466 строк): подключить в `MaterialApp` ИЛИ удалить
- [ ] Вынести `theme/example/` из `lib/` (демо-приложения в бандле)
- [ ] Завести design-токены (spacing/radius/color/text), подключить `colorScheme`/`textTheme`
- [ ] Заменить inline `Color(0xFF…)` (~111) и `TextStyle(...)` (~105) на токены/тему
- [~] Inline ButtonStyle в `main.dart`: удалены мёртвые `flatButtonStyle` + `outlineButtonStyle` (хардкод `Colors.red`). Осталось вынести используемый `raisedButtonStyle` в тему

## Phase 6 — Слой данных (наибольший эффект, средний риск)

- [ ] `ScanRepository` — вынести scan/sync-путь (Hive + API + очередь) из виджетов; добьёт остаток багов очереди
- [ ] `EquipmentRepository` — убрать сырые `inventoryBox.put` и `api.updateEquipmentState` из `qr_result_screen.dart:381-502`
- [ ] Вынести sync-логику из `qa_actions.dart:84-107` в метод репозитория
- [ ] Развести двойную подачу зависимостей (`GlobalState.dataProvider` static vs `Provider`)

## Phase 7 — Модели

- [x] Убрать конфликт Hive `typeId` — `inventory_scan` удалён (Phase 1) + снята мёртвая `@HiveType(12)` с `Company` (реальный adapter `typeId=15` не тронут)
- [x] Снять нерабочие `@HiveType`/`@HiveField` со всех моделей (company, equipment_state, periodic_task_models). **Решение: оставляем ручной `read`/`write`** (без кодогена) — формат Hive не меняется, данные пользователей в безопасности
- [ ] Enum-статусы вместо magic strings — **отложено**: при ручном read/write смена типа поля `String→enum` меняет сериализацию. Делать только как additive-слой (геттеры) + регресс-проверки
- [~] `copyWith` добавлен в `InventoryRecord` + задействован в `qr_result_screen` (убрана ручная копия 13 полей). `==`/`hashCode` — отложено (меняет семантику `Set<Task>` в контроллере = поведение)
- [x] Чистка предсуществующих warning'ов: неиспользуемые импорты (`settings.dart` −9, `modal`, `inventory_record`) и локалы (`global_state`, `main` ButtonStyles). flutter analyze 30→15

## Phase 8 — Структура папок (большой git mv)

- [ ] feature-first: `features/{auth,home,scan,tasks,notifications,onboarding}/{ui,data,model}`
- [ ] `core/{http,storage,state,routing,utils}` (перенести `global_state`, `settings`, `strings`, `http`, `data`)
- [~] `design/{theme,tokens,components}` — создан `lib/src/design/`, orphaned `lib/theme/` перенесён туда (нулевой каскад). tokens/components — позже
- [ ] Схлопнуть 4 «qr»-папки и single-file папки

## Прочее (точечно)

- [ ] `addPostFrameCallback` из `build()` в `initState` (qr_result_screen:748, qr_screen:188, qa_actions:42, login_screen:45)
- [x] Переименовать `exceptions/login_exceptions.dart` → `app_exceptions.dart` (3 импортёра обновлены)
- [ ] `Strings`: убрать пересборку `{'ru':…}`-map на каждый геттер
- [ ] `Settings`: helper `_bool/_int` вместо 6× повтора с magic-ключами
- [ ] Роутинг: уйти от передачи объектов через `state.extra` (`main.dart:339/353/364`)
