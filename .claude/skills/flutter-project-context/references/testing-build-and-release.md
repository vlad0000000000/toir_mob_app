# Тесты, сборка и релиз

## Версии инструментов

| Что | Версия | Источник |
|---|---|---|
| Flutter | **3.29.0** stable (revision `35c388afb5`) | `Dockerfile:1`, `.metadata:7`, проверено `flutter --version` |
| Dart SDK | **3.7.0** | проверено `dart --version` |
| Ограничение SDK в pubspec | `sdk: ^3.0.0` | `pubspec.yaml:10` |
| JDK | **17** (обязательно) | `Dockerfile:4-8` явно удаляет openjdk-21 и ставит 17 |
| Android Gradle Plugin | 8.1.1 | `android/settings.gradle:33` |
| Kotlin | 2.1.10 | `android/settings.gradle:34` |
| compileSdk | 35 | `android/app/build.gradle:48` |
| NDK | 25.1.8937393 | `android/app/build.gradle:51` |
| Java compatibility | 1.8 (source/target/jvmTarget) | `android/app/build.gradle:53-60` |
| Имя пакета Dart | `qr_scan_industry` | `pubspec.yaml:1` |
| Версия приложения | `0.0.1+2` в pubspec, но реально из `.env` | `pubspec.yaml:7` vs `build.gradle:74-75` |

**JDK 21 ломает сборку** — Gradle 8.x в этой связке поддерживает Java ≤ 20.
`JAVA_HOME` должен указывать на JDK 17.

---

## Обязательная подготовка окружения

### 1. `.env` в корне проекта

Без него **не собирается ничего**, включая debug: `android/app/build.gradle:9-13`
читает файл на этапе конфигурации Gradle, а `lib/main.dart:83` — на старте
приложения.

Минимальный рабочий набор ключей:

```
API_ENDPOINT=<url бэкенда>
API_USER=<любая непустая строка>
API_PASSWORD=<любая непустая строка>
APP_TITLE=<заголовок приложения>
APP_ID=<applicationId, например com.company.appname>
APP_VERSION_CODE=<целое>
APP_VERSION_NAME=<x.y.z>
SIGN_STORE_FILE=<имя файла keystore относительно android/app/>
SIGN_STORE_PASS=<пароль хранилища>
SIGN_KEY_ALIAS=<алиас ключа>
SIGN_KEY_PASS=<пароль ключа>
```

`API_USER` / `API_PASSWORD` уходят в заголовок Basic Auth только для
`isAlive()`; бэкенд их не проверяет, поэтому подойдёт любая непустая пара.

Требования к формату: **без кавычек вокруг значений** — файл парсится и как
`.env` (`flutter_dotenv`), и как `java.util.Properties` (Gradle).

`.env` объявлен ассетом (`pubspec.yaml:66`) — попадает внутрь APK. Не клади туда
ничего, что не должно уехать на устройство. В git не коммить (файл untracked, но
в `.gitignore` его **нет** — легко закоммитить случайно).

**Смена `APP_VERSION_*` обнуляет локальную базу Hive** (путь = md5 от версии,
`main.dart:95-108`). Перед bump-ом убедись, что очередь осмотров пуста.

### 2. Keystore

`signingConfigs.release` создаётся **безусловно** на этапе конфигурации
(`build.gradle:81-88`) — то есть файл по пути `android/app/${SIGN_STORE_FILE}`
должен существовать даже для debug-сборки. Keystore в git не попадает
(`android/.gitignore:12` — `**/*.keystore`, `**/*.jks`), его создаёт разработчик:

```bash
keytool -genkey -v -keystore android/app/<SIGN_STORE_FILE> \
  -storepass <SIGN_STORE_PASS> -keypass <SIGN_KEY_PASS> -alias <SIGN_KEY_ALIAS> \
  -keyalg RSA -keysize 2048 -validity 10000
```
Значения подставь **из своего `.env`** — они обязаны совпадать, иначе Gradle
не откроет хранилище. Реальные значения в документацию не выписывай.

### 3. `android/local.properties`

Пути к Flutter и Android SDK. Игнорируется git (`android/.gitignore:6`), но
**обязателен** — `android/settings.gradle:16-19` содержит
`assert flutterSdkPath != null`.

---

## Команды

### Разработка

```bash
flutter pub get
flutter devices
flutter run -d <device-id>
```

В консоли `flutter run`: `r` — hot reload, `R` — полный рестарт, `q` — выход.
**`.env` читается только при старте** — после его правки нужен `q` и новый
`flutter run`, hot reload не поможет.

### Статический анализ

```bash
flutter analyze
```

**Эталонный результат — ровно 1 предупреждение** (проверено, 80 с):

```
warning - The include file 'package:analysis_defaults/flutter.yaml' in
          analysis_options.yaml can't be found - analysis_options.yaml:1:10 - include_file_not_found
```

Оно известно и намеренно: `analysis_defaults` не числится в зависимостях,
из-за чего **блок `linter.rules` не применяется вообще**.

Прежнее второе предупреждение (`dead_code` в `update_manager.dart`) устранено:
самообновление отключается флагом `static const bool enabled = false`, а не
`return;` первой строкой.

Любое **второе** предупреждение — регрессия твоей правки.

### Форматирование

```bash
dart format lib/src/путь/к/файлу.dart      # только файлы, которые правишь
```

**Не запускай `dart format lib`.** Проверено: `dart format --output=none
--set-exit-if-changed lib test` сообщает `38 changed` из 95 файлов — то есть
больше трети проекта не отформатировано. Массовый прогон утопит содержательный
диф в косметике.

Файлы, которые формат изменил бы (для справки, не как задание): `main.dart`,
`strings.dart`, `login_screen.dart`, большинство `model/*.dart`, вся
`notifications/`, `qa_actions.dart`, `qr_result_screen.dart`,
`result_controls.dart`, `equipment_*_screen.dart`, `tasks_filter_sheet.dart`,
`select_*.dart`, `dialogs.dart`, `snack_bar.dart`.

### Тесты

```bash
flutter test
```

**Сейчас падает.** Проверено:

```
Error: Undefined name 'main'.
Failed to load "test/widget_test.dart": Compilation failed
```

Причина: единственный тестовый файл `test/widget_test.dart` полностью
закомментирован (шаблонный counter-тест из `flutter create`, ссылающийся к тому
же на несуществующий пакет `qr_machine_scanner`). Функции `main()` в нём нет.

**Тестов в проекте нет.** Ни unit, ни widget, ни golden, ни integration.
Папок `integration_test/` и `test_driver/` не существует. Моков, фикстур,
`mockito`/`mocktail` нет.

Это baseline. Не отчитывайся об «успешном прогоне тестов» — их нет.

### Сборка

```bash
flutter build apk                 # debug/release APK
flutter build apk --release
flutter build appbundle           # не проверялось в этом проекте
```

Контейнерная сборка (Linux-окружение с правильным JDK):

```bash
docker compose up                 # → ./build_output
```
`docker-compose.yml` монтирует `./build_output`, подхватывает `.env` через
`env_file` и выполняет `flutter pub get && flutter build apk && cp -r
build/app/outputs /app/build_output/`.

⚠️ **Осторожно с `docker compose up`.** Команда содержит две подстановки:
```
find . -type f -exec sed -i 's/fedorenko/$PROJECT_NAME/g' {} +
find . -type f -exec sed -i 's/Yarmarka/$PROJECT_TITLE/g' {} +
```
Это наследие шаблона другого проекта: `sed -i` проходит **по всем файлам
рекурсивно**, а переменные `PROJECT_NAME`/`PROJECT_TITLE` в `.env` не заданы.
Внутри контейнера это безопасно (работает на копии), но команду не переносить
на хост.

### Иконки

```bash
dart run flutter_launcher_icons
```
Конфиг — `pubspec.yaml:70-88`, исходник `assets/images/icon.jpg`, adaptive-фон
`#ffffff`, `min_sdk_android: 21`.

### Кодогенерация

**Не нужна.** `hive_ce_generator` числится в `dev_dependencies`, но `build_runner`
не подключён, `*.g.dart` в проекте нет. Все `TypeAdapter` рукописные —
`REFACTORING_CHECKLIST.md`, Phase 7: «Решение: оставляем ручной `read`/`write`».

Не запускай `build_runner` — он ничего не сгенерирует, а если настроить —
перезапишет рукописные адаптеры и **сломает данные на устройствах**.

---

## Флейворы и окружения

**Флейворов нет.** `--flavor` не поддерживается, `productFlavors` в
`build.gradle` отсутствуют, `--dart-define` не используется, `main_dev.dart` /
`main_prod.dart` нет.

Единственный механизм переключения окружения — правка `API_ENDPOINT` в `.env`
и перезапуск приложения.

Типовые значения `API_ENDPOINT` для локальной разработки:

| Устройство | Значение | Дополнительно |
|---|---|---|
| Android-эмулятор | `http://10.0.2.2:8000` | `10.0.2.2` — алиас loopback хоста |
| Телефон по USB | `http://localhost:8000` | нужен `adb -s <serial> reverse tcp:8000 tcp:8000`, повторять после переподключения кабеля |

---

## CI/CD

**Нет.** Ни `.github/workflows/`, ни `.gitlab-ci.yml`, ни `bitrise.yml`,
ни `codemagic.yaml`, ни fastlane. Никаких автоматических проверок при пуше.

Единственная автоматизация — `docker-compose.yml` для локальной сборки APK.

---

## Релиз

**Ветка** — `toir-prod` (единственная, она же `origin/HEAD`). Feature-веток в
удалённом репозитории нет. 134 коммита, последний — `bdbfc23 fix(notifications):
8 bug-fixes from QA round` (2026-06-02).

**Стиль сообщений коммитов** — Conventional Commits, преимущественно английский
заголовок с русским телом там, где нужно пояснение:
```
feat: пуш-уведомления (foreground SSE, тап-роутинг, дедуп) + UX уведомлений
fix(notifications): 8 bug-fixes from QA round
refactor(theme): tasks_filter_sheet полностью на тему (Phase 5)
ui: hub redesign, sticky CTA, notification card accent
design: industrial-grade SOTA-2026 theme — полная перепись AppTheme
docs: обновить чек-лист по Phase 5
chore: чистка предсуществующих warning'ов (analyze 15 → 2)
```
Префиксы в ходу: `feat`, `fix`, `refactor`, `ui`, `design`, `docs`, `chore`.
Ранние коммиты (`updates`, `last updates`, `clean`, `fixes and other`) —
легаси, не повторять.

**Версионирование** — только через `.env` (`APP_VERSION_CODE`,
`APP_VERSION_NAME`). Значение `version: 0.0.1+2` в `pubspec.yaml`
**не влияет** на APK: `build.gradle:74-75` берёт версию из `.env`.
Помни про обнуление Hive при смене версии.

**Shorebird (code push).** `shorebird.yaml` с
`app_id: 8065b3a6-9eb5-4031-a189-35179469054a`, `auto_update` не отключён
(значит, патчи применяются автоматически при запуске). Файл включён в assets
(`pubspec.yaml:67`). Вероятно, именно поэтому самообновление через
`UpdateManager` отключено `return;`-ом. CLI Shorebird (`shorebird release`,
`shorebird patch`) в репозитории не автоматизирован.

---

## Файлы, которые нельзя править вручную

| Путь | Почему |
|---|---|
| `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` | генерируется Flutter |
| `ios/Runner/GeneratedPluginRegistrant.{h,m}` | то же |
| `ios/Flutter/Generated.xcconfig`, `ios/Flutter/flutter_export_environment.sh` | то же |
| `.flutter-plugins`, `.flutter-plugins-dependencies` | то же |
| `.dart_tool/`, `build/`, `android/.gradle/`, `android/.kotlin/`, `android/app/.cxx/` | артефакты сборки |
| `pubspec.lock` | только через `flutter pub get` / `flutter pub upgrade` |
| `.metadata` | служебный файл Flutter |
| `android/local.properties` | машинно-зависимый, не в git |
| `android/app/debug.keystore` | бинарный, не в git |

## Файлы, которые править можно, но осторожно

| Путь | Риск |
|---|---|
| `.env` | Правка версии обнуляет Hive; правка `SIGN_*` ломает сборку |
| `lib/main.dart` (блок регистрации адаптеров и открытия боксов) | Пропущенный `registerAdapter` = падение при чтении бокса |
| `lib/src/model/*.dart` (`read`/`write` адаптеров) | Несимметричное изменение = потеря данных пользователей |
| `android/app/build.gradle` | Читает `.env` на этапе конфигурации |
| `pubspec.yaml` (секция `assets`) | `.env` и `shorebird.yaml` должны остаться в assets |

---

## Известные ограничения инструментария

1. **Линтер не работает** — `include_file_not_found`, набор `linter.rules`
   не применяется. Проект не защищён правилами, только формой соседнего кода.
2. **`flutter test` красный** из-за пустого шаблонного файла — не путать с
   регрессией.
3. **Форматирование не соблюдено** в 40% файлов.
4. **CI отсутствует** — все проверки только локально и вручную.
5. **Зависимости устарели:** `flutter pub get` сообщает
   `143 packages have newer versions incompatible with dependency constraints`,
   `1 package is discontinued` и предупреждение о security advisory
   (`GHSA-3hpf-ff72-j67p`). Апгрейд не делался; `go_router` 7.1.1 — на 6 мажорных
   версий позади. Не обновляй пакеты без отдельной задачи: `go_router` 8.x
   удаляет `GoRouter.location`, который используется в `app_bar.dart:41` и
   `qr_result_screen.dart:339`.
6. **`mobile_scanner: ^7.0.0-beta.7`** — beta-версия в проде.
7. **iOS не проверяется** — нет macOS-окружения, `Podfile.lock` отсутствует,
   в `ios/` лежат чужие Firebase-конфиги.

---

## Если понадобится завести тесты

Реалистично покрывается без рефакторинга (чистая логика, не требует ни Hive,
ни сети):

- `SseLineParser.handleLine` — `lib/src/notifications/sse_line_parser.dart`;
- `TasksFilterState.apply` — `lib/src/tasks/tasks_filter_state.dart`;
- `NotificationFormatters.*` — `lib/src/notifications/notification_formatters.dart`;
- `*.fromJson` всех моделей;
- `_pluralizeTasks` — `lib/src/tasks/equipment_list_screen.dart:152`
  (приватный, потребует вынести);
- `UsageParameter.validate` — `lib/src/model/inventory_record.dart:278`;
- **симметричность Hive-адаптеров** (`write` → `read` → сравнение) — самый
  ценный тест для этого проекта, защищает от потери данных пользователей.

Что покрыть **нельзя** без изменения архитектуры: всё, что ходит через `API` —
класс использует статические поля и `package:http` напрямую, точки внедрения
клиента нет. Widget-тесты экранов требуют инициализированного
`GlobalState.dataProvider`, `Settings.dataProvider`, `dotenv` и открытых
Hive-боксов — то есть почти полного `main()`.

Первый тестовый файл должен **заменить** `test/widget_test.dart` (или добавиться
рядом), иначе `flutter test` продолжит падать на нём.
