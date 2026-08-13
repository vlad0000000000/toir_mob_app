# Доказательная база, противоречия и неизвестное

Дата анализа: **2026-08-13** (первичный — 2026-08-01).
Состояние репозитория: ветка `feature/zip-repairs`, HEAD `9e668ef`
(«applied the backend changes.», 2026-08-12), 138 коммитов.
Хеш — метка «когда сверялись», а не доказательство правильности.

**Сверка 2026-08-13** охватила фичу «Ремонты и ЗИП»: 4 коммита поверх
`toir-prod` (`f253695`, `6d311ed`, `95e0db2`, `9e668ef`), +16 192 / −446 строк
в 70 файлах. На момент сверки в рабочем дереве были незакоммиченные правки
UI в `repairs/` и `strings.dart` — косметика, на выводы не влияет.
Утверждения, не связанные с этой фичей, остались от первичного анализа и
повторно построчно не перепроверялись.

---

## Что было прочитано

**Конфигурация и метаданные:** `pubspec.yaml`, `pubspec.lock` (частично),
`analysis_options.yaml`, `.metadata`, `.gitignore`, `android/.gitignore`,
`shorebird.yaml`, `Dockerfile`, `docker-compose.yml`, `README.md`,
`REFACTORING_CHECKLIST.md`, `ПЛАН_РЕМОНТЫ_ЗИП.md`, `.env` (только имена ключей).

**Android:** `android/app/build.gradle`, `android/settings.gradle`,
`android/gradle.properties`, `android/app/src/main/AndroidManifest.xml`,
`android/app/src/main/kotlin/com/example/game_template/MainActivity.kt`,
перечень `android/app/src/main/res/`.

**Dart — прочитано целиком:** `lib/main.dart`, `lib/global_state.dart`,
`lib/settings.dart`, `lib/strings.dart`, весь `lib/src/http/`,
весь `lib/src/data/`, `lib/src/design/app_constants.dart`,
`lib/src/design/app_theme.dart`, `lib/src/design/theme_extensions.dart`,
`lib/src/exceptions/app_exceptions.dart`, `lib/src/app_bar/app_bar.dart`,
`lib/src/app_lifecycle/app_lifecycle.dart`, `lib/src/style/*`,
`lib/src/utils/*` (кроме `inherited_wrapper`), `lib/src/widgets/*` (кроме
`select_problem_button`, `select_task_button`, `select_usage_button`),
`lib/src/login/login_screen.dart`, `lib/src/splash/splash_screen.dart`,
`lib/src/qr/qr_screen.dart`, `lib/src/qr/qa_actions.dart`,
`lib/src/knowledge_base/*`, `lib/src/onboarding/onboarding_welcome_screen.dart`,
`lib/src/onboarding/onboarding_video_player.dart`,
`lib/src/notifications/notifications_service.dart`, `notification_card.dart`,
`notification_formatters.dart`, `sse_line_parser.dart`,
`push/push_notifications_controller.dart`, `push/notification_router.dart`,
`lib/src/tasks/equipment_list_screen.dart`, `task_models.dart`,
`equipment_detail_controller.dart`, `tasks_filter_state.dart`, барреллы,
`lib/src/update_manager.dart`, `lib/src/design/README.md` (первые 60 строк),
`test/widget_test.dart`, модели: `inventory_record`, `scan`, `user`, `task`,
`typical_problem`, `usage_update`, `company`, `session`, `equipment_state`,
`priority`, `notification`, `notification_settings`, `periodic_task_request`.

**Dart — прочитано частично (структура + ключевые фрагменты):**
`lib/src/qr/qr_result_screen.dart` (строки 1–540, 555–836),
`lib/src/qr/result_controls.dart` (1–120, 200–380),
`lib/src/tasks/equipment_detail_screen.dart` (1–140),
`lib/src/notifications/notifications_screen.dart` (1–200),
`lib/src/notifications/push/notifications_task_handler.dart` (1–120).

**Сверка 2026-08-13, прочитано целиком:** `lib/src/model/repair.dart`,
`lib/src/http/repair_api.dart`, `lib/src/data/hive_storage_location.dart`
(начало), `.claude/skills/**` целиком.

**Сверка 2026-08-13, прочитано частично** (структура + ключевые фрагменты):
`lib/src/data/data_provider_outbox.dart` (1–140),
`lib/src/model/pending_repair.dart` (1–120),
`lib/src/repairs/repairs_list_screen.dart` (1–120),
`lib/src/repairs/repair_detail_screen.dart` (41–120),
`lib/src/repairs/create_repair_screen.dart` (34–90),
`lib/main.dart` (маршруты и регистрация адаптеров),
`lib/src/app_bar/app_bar.dart` (новые ветки),
`lib/src/http/api.dart` (90–115).

**Сверка 2026-08-13, не прочитано построчно** (только перечень объявлений):
`lib/src/repairs/repair_conflict_screen.dart`,
`lib/src/repairs/spare_part_picker_sheet.dart`,
`lib/src/repairs/repair_error_messages.dart`,
`lib/src/spare_parts/*`, `lib/src/widgets/date_range_sheet.dart`,
`lib/src/widgets/offline_banner.dart`, `lib/src/widgets/spare_part_row.dart`,
`lib/src/model/spare_part.dart`, `consumption_norm.dart`,
`stock_history_entry.dart`, `repair_conflict.dart`,
`lib/src/data/repair_photo_files.dart`.

**Не прочитано построчно** (только перечень объявлений через grep):
`lib/src/tasks/tasks_filter_sheet.dart`,
`lib/src/notifications/notifications_settings_screen.dart`,
`lib/src/widgets/select_usage_button.dart`,
`lib/src/qr/scanner_button_widgets.dart`,
`lib/src/model/periodic_task_models.dart`, `responsible_user.dart`,
`usage_unit.dart`, `periodicity_rule.dart`, `equipment_fault.dart`.

---

## Проверено командой (факты, а не выводы)

| Проверка | Результат |
|---|---|
| `flutter --version` | Flutter 3.29.0 stable, Dart 3.7.0 |
| `flutter analyze` (2026-08-13) | **1 issue** за 80.2 с: `include_file_not_found` (analysis_options.yaml:1:10). `dead_code` в `update_manager.dart` устранён |
| `git diff --stat toir-prod...feature/zip-repairs` | 70 файлов, +16 192 / −446 |
| `grep -c registerAdapter lib/main.dart` | 28 |
| `grep -c 'Hive.openBox' lib/main.dart` | 20 |
| `grep -c 'GoRoute(' lib/main.dart` | 21 |
| `flutter test` | **Падает**: `Undefined name 'main'` — `test/widget_test.dart` пуст |
| `dart format --output=none --set-exit-if-changed lib test` | `Formatted 95 files (38 changed)` — файлы **не** изменялись на диске, `git status` подтверждён чистым |
| `flutter pub get` | `143 packages have newer versions incompatible with dependency constraints`, `1 package is discontinued`, security advisory `GHSA-3hpf-ff72-j67p` |
| `grep` по `lib/` | 219 относительных импортов против 7 `package:qr_scan_industry/` |
| `grep` по `lib/` | `print(` — 19, `debugPrint(` — 37, `Logger(` — 2 |
| `grep` по `lib/` | `Theme.of(context).colorScheme` — 95, `AppConstants.*` — 230, `Colors.*` — 71, `Color(0x…)` — 146 |
| `grep` по `lib/` | `Semantics(` — 0, `semanticLabel` — 0, `tooltip:` — 5, `HapticFeedback` — 0 |
| `grep` по `lib/` | `Strings.*` — 67 вызовов; строковых литералов с кириллицей — ~340 |
| `git ls-files` | `android/app/debug.keystore` и `android/local.properties` **не** в git (игнорируются `android/.gitignore`); `ios/Runner/GoogleService-Info.plist` и `ios/firebase_app_id_file.json` — **в git** |
| `grep crypto pubspec.yaml` | отсутствует; в `pubspec.lock` — есть (транзитивная) |

---

## Уверенные выводы (высокая уверенность)

Подтверждены и кодом, и командой, и/или git-историей:

1. Линтер не применяется — `analysis_options.yaml` ссылается на отсутствующий пакет.
2. Тестов нет, `flutter test` красный.
3. Hive-адаптеры рукописные, кодогенерации в `lib/` нет.
4. Путь Hive **больше не зависит** от версии приложения: считается в
   `HiveStorageLocation.resolve` от `appName|packageName`, при первом запуске
   боксы переносятся из каталога старой схемы, факт переноса помечается
   файлом `.migrated`.
5. `.env` обязателен и для Dart, и для Gradle; без keystore не собирается даже debug.
6. Только Android реально поддерживается.
7. Только светлая тема, только портрет, только русский.
8. `theme_extensions.dart` не импортируется ни одним файлом.
9. `Palette` и `my_transition.dart` удалены вместе с анимацией переходов.
10. `UpdateManager.checkForUpdate` отключён флагом
    `static const bool enabled = false` (раньше — `return;` первой строкой).
11. `select_priority_button`, `select_problem_button`, `select_state_button`,
    `select_usage_button`, `button_with_select_dialog`, `scanned_barcode_label`,
    `dependent_multi`, `self_cancel_timer` — ноль внешних ссылок.
12. Навигация — настоящий стек: вглубь `push`, назад `backOr(fallback)`,
    сброс стека только на входе, выходе, splash и в онбординге.
13. Очередь возвращает записи из pending через **120** секунд (комментарии в
    коде говорят «60» — комментарии врут).
14. `dio`, `shared_preferences`, `cached_network_image`, `themed`,
    `infinite_scroll_pagination`, `cherry_toast`, `file_picker`,
    `flutter_pdfview`, `gallery_saver_plus`, `mime`, `qr_code_scanner_plus`
    не используются в `lib/`.
15. `crypto` используется (`GlobalState.digest`), но не объявлен в `pubspec.yaml`.
16. Фича «Ремонты и ЗИП» реализована: 9 экранов в `lib/src/repairs/` и
    `lib/src/spare_parts/`, 6 маршрутов, 4 Hive-бокса, 2 part-файла API,
    собственная очередь отправки с идемпотентностью.
17. Список ремонтов сужает **сервер** (ответственный или должность
    пользователя) — клиентского фильтра «мои» нет и не требуется.
18. Обходчик не может закрыть ремонт из приложения: в `repair_api.dart` нет
    метода, отправляющего `status: closed`.
19. Снимки ремонта в очереди хранятся файлами на диске
    (`repair_photo_files.dart`), а не base64 в Hive.

---

## Выводы средней уверенности (сделаны по косвенным признакам)

| Вывод | На чём основан | Что может опровергнуть |
|---|---|---|
| Самообновление отключено в пользу Shorebird | `return;` в `checkForUpdate` + наличие `shorebird.yaml` + запись в `REFACTORING_CHECKLIST.md` («отложено: отключён намеренно (Shorebird?)») — знак вопроса стоит **в самом чек-листе** | Прямой ответ автора |
| Проект отпочкован от игрового Flutter-шаблона | `MainActivity.kt` лежит в `com/example/game_template/`, `android/app/src/main/res/values/games-ids.xml`, комментарий в `main.dart:79-81` про `google_mobile_ads`, запись в чек-листе про «game-template комментарий» | — |
| Firebase-конфиги в `ios/` — мусор от шаблона | Ни одного Firebase-пакета в `pubspec.yaml`; push сделан на `flutter_foreground_task` | Возможно, iOS-сборка когда-то планировалась с FCM |
| Рекомендация «`context.watch` в `build()`, статик в колбэках» | Так написано большинство экранов, но правило нигде не зафиксировано | Явное решение команды |
| `Settings.qrResultShowTasksFirst` действительно работает | Читается в `result_controls.dart:216` и открывает модалку через `addPostFrameCallback`; на устройстве не проверялось | Прогон на устройстве |
| Истечение JWT не обрабатывается | Нет ни refresh-эндпоинта в клиенте, ни перехвата 401 | Возможно, бэкенд выдаёт очень долгий токен и проблема не проявляется |

---

## Противоречия внутри проекта

Перечислены, а не «сглажены». При правке — следуй правой колонке.

| Противоречие | Где | Что делать |
|---|---|---|
| `DataProvider` доступен и как `Provider`, и как статик `GlobalState.dataProvider` — оба варианта в одном файле | `qr_result_screen.dart:107` vs `:274` | `context.watch` в `build()`, статик в колбэках. Открытый пункт `REFACTORING_CHECKLIST.md` Phase 6 |
| Импорты: относительные (219) vs `package:` (7), вперемешку | `main.dart`, `qa_actions.dart`, `equipment_list_screen.dart` | Повторяй стиль правимого файла; в новых файлах — относительные |
| `_XxxState` vs `_Xxx` для приватных State | `login_screen.dart:27` vs `select_state_button.dart:22` | `_XxxState` |
| `print` vs `debugPrint` vs `Logger` | по всему `lib/` | `debugPrint` с тегом `[Модуль]` |
| Токены `AppConstants` vs числовые литералы для высот и длительностей | `spacing`/`radius` — через токены; `56`/`52`/`Duration(milliseconds: 180)` — литералами | Отступы и радиусы — токенами; остальное — как рядом |
| `Strings.*` (67) vs захардкоженные русские литералы (~340) | `qa_actions.dart`, `notification_card.dart` | Повторяющееся — в `Strings`, уникальное для экрана — литералом |
| Комментарий «60 секунд» при пороге 120 | `data_provider_outbox.dart:45,55-58,107,122,133,160` | Верь коду |
| Аргумент `offset` при параметре URL `skip` | `equipment_api.dart:12`, `task_api.dart:11` | Не менять — это контракт бэкенда |
| Тёмные `ColorScheme` написаны, но `themeMode: ThemeMode.light` | `app_theme.dart:142,244` vs `main.dart:416` | Поддерживать целостность схем, но не проверять экраны в тёмной теме |
| Полный фильтр задач написан, но выключен константой | `equipment_list_screen.dart:15` | Не удалять; включать только по задаче |
| «Сбросить осмотры» деструктивно и без подтверждения, при том что везде используется `Dialogs.areYouSure` | `qa_actions.dart:80-85` | Расхождение реальное; чинить только по задаче |
| `Form` + `validator` на логине без `GlobalKey<FormState>` — валидация не срабатывает | `login_screen.dart:102,146,177` | Фактический паттерн валидации — флаги подсветки в `State` |
| `MyAppBar` ветвится по строке `location` | `app_bar.dart:41-137` | Новый маршрут = обязательная правка `app_bar.dart` |
| `MainActivity.kt` в пакете `com.example.qr_scan_industry`, но в папке `com/example/game_template/`, `namespace = "com.example.qr_machine_scanner"`, `applicationId` из `.env` — четыре разных идентификатора | `build.gradle:47,69`, `AndroidManifest.xml:3`, путь файла | Не трогать без нужды: смена `applicationId` = новая установка |
| `ПЛАН_РЕМОНТЫ_ЗИП.md` расходится с реализацией по четырём пунктам: хранение (п. 1.4 требовал `stringBox`, сделаны типизированные боксы), фильтр «мои» (п. B2 — сервер решил сам), ответственный (п. 9.1 был открытым вопросом — реализована должность), закрытые ремонты (п. 9.4 — сделан отдельный эндпоинт на последние 10) | план vs `lib/src/repairs/`, `lib/src/model/`, `repair_api.dart` | **Правда за кодом.** План читать ради дизайн-контракта и обоснования офлайн-механики |
| Две несовместимые схемы офлайн-очереди в одном файле: пара боксов + таймаут (осмотры) и один бокс + `Idempotency-Key` (ремонты) | `data_provider_outbox.dart` | Обе действующие. Выбор по признаку «есть ли у отправки побочный эффект на сервере» — см. `SKILL.md`, рецепт «Новая отправляемая сущность» |
| Диалоги подтверждения: `Dialogs.areYouSure` (везде) vs собственный `_SubmitConfirmDialog` (ремонты) | `utils/dialogs.dart` vs `repair_detail_screen.dart:2128` | У ремонтов диалог показывает сводку и три разных варианта текста — штатный этого не умеет. Для простого «да/нет» по-прежнему `Dialogs.areYouSure` |
| Навигация: `GoRouter.push` (везде) vs `Navigator.push(MaterialPageRoute)` (экран конфликта) | `repairs_list_screen.dart`, `repair_detail_screen.dart` | Исключение осознанное: модальный тупик вне таблицы маршрутов. Закрывается `Navigator.pop`, а не `backOr` |
| Кнопка «назад» есть и в `MyAppBar`, и в собственных `AppBar` карточек ремонта, ЗИП и уведомлений | `app_bar.dart`, `repair_detail_screen.dart`, `spare_part_detail_screen.dart`, `notifications_screen.dart` | И там, и там — `backOr(fallback)`. Запасной адрес выбирается по разделу |

---

## Устаревшая документация

| Файл | Проблема |
|---|---|
| `lib/src/design/README.md` | Боилерплейт «Flutter Theme Generator». Описывает `lib/theme/`, `darkTheme` + `ThemeMode.system`, расширения `context.gapMD`/`context.colorScheme` — ничего этого в проекте нет. **Игнорировать** |
| `README.md` | Три строки, упоминает только `API_ENDPOINT`. Реально обязательных ключей `.env` — одиннадцать |
| `REFACTORING_CHECKLIST.md` | Актуален по состоянию Phase 1–7, но Phase 8 (feature-first) не сделан, и часть отметок описывает промежуточное состояние. Фича «Ремонты и ЗИП» в чек-листе не отражена вовсе. Читать как журнал решений, не как ТЗ |
| `ПЛАН_РЕМОНТЫ_ЗИП.md` | План реализованной фичи. Разошёлся с кодом по хранению, фильтрации, ответственному и закрытым ремонтам (см. «Противоречия»). Ценен разделом «Промт 0» (дизайн-контракт) и обоснованием офлайн-механики |
| Комментарии «60 секунд» в `data_provider_outbox.dart` | Не соответствуют коду (120) |
| `main.dart:79-82` | Комментарий про `google_mobile_ads` в пустом `if` — от шаблона |
| `periodic_task_request.dart:48-57` | Закомментированный образец JSON — может отставать от контракта бэкенда |

---

## Что не удалось изучить

| Объект | Почему | Как исправить |
|---|---|---|
| `assets/onboarding/1–4.mp4` | Видеофайлы, содержимое нечитаемо инструментами | Описание сценария каждого ролика — от автора онбординга |
| `assets/onboarding/lisa.png`, `assets/images/back.jpg`, `icon.jpg/png` | Растр; визуальные значения из бинарников выводить нельзя | Не требуется для кода |
| `assets/images/ix_user-manual.svg` | Не открывался (используется только как монохромная иконка через `ColorFilter`) | При необходимости — прочитать как текст |
| Фигма / макеты | В репозитории отсутствуют. Единственный текстовый эталон дизайна — `ПЛАН_РЕМОНТЫ_ЗИП.md`, «Промт 0» | Ссылка на файл Figma от дизайнера |
| Реальные ответы бэкенда | Сервер не поднимался в ходе анализа; структура полей выведена из `fromJson` | OpenAPI-схема `sampo_smart_backend` (`/openapi.json/`) |
| Поведение на устройстве | Ни один сценарий не прогонялся на телефоне/эмуляторе в рамках этого анализа. Для ремонтов это особенно чувствительно: офлайн-очередь, разрешение конфликтов, дозагрузка фото и перенос базы Hive со старой схемы проверяются только вживую | Ручной прогон |
| Серверная часть ремонтов | Читался только клиент. Поведение `Idempotency-Key`, правила `access_user_id`/`access_role_id` и белый список полей для `walker` известны из комментариев в клиентском коде, а не из бэкенда | Сверка с `sampo_smart_backend` |
| iOS-сборка | Нет macOS-окружения; `Podfile.lock` отсутствует | Сборка на macOS |
| `pubspec.lock` целиком | Прочитан выборочно (`crypto`) | При необходимости — точечно |

---

## Открытые вопросы к продукту и команде

1. **Что делать при истечении JWT?** Refresh-механизма в приложении нет,
   401 нигде не перехватывается. Ожидается ли переход на экран логина?
2. **Обязателен ли `UpdateManager`?** Он отключён `return;`-ом, но код и
   разрешение `MANAGE_EXTERNAL_STORAGE` остались. Удалять вместе с разрешением
   или чинить?
3. **Судьба фильтра задач.** Экран написан целиком, но выключен константой
   `_kShowTasksFilter = false`. Включать, доделывать (фильтр по приоритету не
   работает — у `Task` нет такого поля) или удалять?
4. **Мёртвое семейство `select_*_button`** — удалять или планируется вернуть?
   `REFACTORING_CHECKLIST.md` Phase 4 упоминает идею общего `SelectButton<T>`.
5. **Смена состояния оборудования офлайн** сейчас теряется (в очередь не
   ставится) — кроме перевода «В ремонте», который идёт через очередь
   ремонтов. Для остальных состояний это принятое поведение или дефект?
6. **QR не найден** — сообщение `Strings.qrDetectFail*` объявлено, но не
   показывается. Показывать?
7. **Срок жизни черновика ремонта.** Черновик лежит в очереди бессрочно; пока
   он не уехал, оборудование числится в ремонте только на этом устройстве.
   Нужен предельный срок и напоминание? (Вопрос 9.3 исходного плана — остался
   открытым, остальные три вопроса раздела 9 закрыты реализацией.)
8. **Целевая структура папок** (Phase 8) — переезд планируется или отменён?
   Фича «Ремонты» легла в текущую структуру (`lib/src/repairs/`,
   `lib/src/spare_parts/`), то есть решение де-факто отложено ещё раз.
9. **Шифрование локальных данных.** Пароль пользователя лежит в Hive открытым
   текстом ради офлайн-входа. Требование заказчика или недосмотр?
10. **Обновление зависимостей.** 143 пакета отстают, `go_router` — на 6
    мажорных версий. Планируется ли апгрейд, и допустима ли поломка
    `GoRouter.location`?
11. **Локализация.** `Strings` покрывает 17% текста. Расширять его,
    переходить на ARB/`flutter_localizations` или оставить как есть?
12. **Тесты.** Нужны ли вообще? Если да — с чего начинать (симметричность
    Hive-адаптеров даст наибольшую отдачу).
