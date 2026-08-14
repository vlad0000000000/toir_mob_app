# Тесты, сборка и релиз

## Версии

| Что | Версия |
|---|---|
| Flutter | **3.29.0** stable |
| Dart | 3.7.0 |
| JDK | **17 — обязательно** (Gradle 8.x поддерживает Java ≤ 20, JDK 21 ломает сборку) |
| AGP / Kotlin | 8.1.1 / 2.1.10 |
| compileSdk / NDK | 35 / 25.1.8937393 |
| Пакет Dart | `qr_scan_industry` |

Версия приложения берётся **из `.env`**, а не из `pubspec.yaml` (там `0.0.1+2`,
и оно ни на что не влияет).

---

## Обязательная подготовка

### 1. `.env` в корне

Без него **не собирается ничего**, включая debug: Gradle читает его на этапе
конфигурации, Dart — на старте приложения.

```
API_ENDPOINT=<url бэкенда, без слеша на конце>
API_USER=<любая непустая строка>
API_PASSWORD=<любая непустая строка>
APP_TITLE=<заголовок>
APP_ID=<applicationId>
APP_VERSION_CODE=<целое>
APP_VERSION_NAME=<x.y.z>
SIGN_STORE_FILE=<имя keystore относительно android/app/>
SIGN_STORE_PASS=  SIGN_KEY_ALIAS=  SIGN_KEY_PASS=
```

`API_USER`/`API_PASSWORD` уходят в Basic Auth только для `isAlive()`; бэкенд их
не проверяет.

**Без кавычек вокруг значений** — файл парсится и как `.env`, и как
`java.util.Properties`.

Файл в `.gitignore` и вне индекса git, но объявлен ассетом и **попадает в APK**
— не клади туда лишнего.

Слеш на конце `API_ENDPOINT` больше не фатален (`API.baseUrl` его срезает), но
писать адрес без слеша правильнее.

### 2. Keystore

`signingConfigs.release` создаётся **безусловно** на этапе конфигурации — файл
`android/app/${SIGN_STORE_FILE}` должен существовать даже для debug-сборки. В
git keystore не попадает (`android/.gitignore`: `**/*.keystore`, `**/*.jks`),
каждый разработчик заводит свой:

```bash
keytool -genkeypair -v -keystore android/app/<SIGN_STORE_FILE> \
  -alias <SIGN_KEY_ALIAS> -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Sampo Smart, O=Sampo, C=RU"
```

Пароли — **из своего `.env`**, иначе Gradle не откроет хранилище. Реальные
значения в документацию не выписывай.

**Свой ключ ≠ релизный.** APK, подписанный другим ключом, не установится поверх
существующего (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) и не годится для
публикации. Для распространения нужен настоящий keystore.

### 3. `android/local.properties`

Пути к Flutter и Android SDK. Не в git, но обязателен —
`settings.gradle` содержит `assert flutterSdkPath != null`.

---

## Команды

```bash
flutter pub get
flutter run -d <device-id>
flutter build apk --release        # → build/app/outputs/flutter-apk/
docker compose up                  # контейнерная сборка → ./build_output
```

**`.env` читается только при старте** — после правки нужен полный перезапуск,
hot reload не поможет. Это же касается APK: `.env` лежит внутри ассетов, так что
правка конфига требует пересборки.

### Статический анализ

```bash
flutter analyze
```

**Эталон — ровно 1 предупреждение:**

```
warning - The include file 'package:analysis_defaults/flutter.yaml' … include_file_not_found
```

Оно намеренно: пакета нет в зависимостях, из-за чего **блок `linter.rules` не
применяется вообще**. Любое **второе** предупреждение — регрессия твоей правки.

### Форматирование

```bash
dart format lib/src/путь/к/файлу.dart      # только файлы, которые правишь
```

**Не запускай `dart format lib`** — 38 из 95 файлов не отформатированы,
массовый прогон утопит содержательный диф в косметике.

### Тесты

`flutter test` **падает**: единственный файл `test/widget_test.dart` полностью
закомментирован, `main()` в нём нет. Тестов в проекте нет — ни unit, ни widget,
ни integration; моков и фикстур тоже. Это baseline, а не регрессия.

### Кодогенерация

Не нужна и **запрещена**: `build_runner` не подключён, все `TypeAdapter`
рукописные. Запуск перезапишет их и **сломает данные на устройствах**.

---

## Установка на устройство

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell monkey -p <APP_ID> -c android.intent.category.LAUNCHER 1
adb logcat | grep -iE "flutter|Push|NotifTask"
```

`-r` работает, только если установленная сборка подписана **тем же** ключом.
Иначе нужен `adb uninstall <APP_ID>` — а это стирает базу Hive вместе со всем
неотправленным. Перед удалением проверь отладочную полосу и «Сервис →
Информация».

Локальный бэкенд с эмулятора: `http://10.0.2.2:8000` (`10.0.2.2` — алиас
хоста). Учти, что release-сборка блокирует cleartext HTTP: в манифесте нет ни
`usesCleartextTraffic`, ни network-security-config.

---

## Флейворы, CI, релиз

**Флейворов нет**, `--dart-define` не используется. Переключение окружения —
правка `API_ENDPOINT` и перезапуск.

**CI нет.** Ни GitHub Actions, ни GitLab CI, ни fastlane. Все проверки локально.

**Ветка** — `toir-prod` (она же `origin/HEAD`); работа по фичам ведётся в
`feature/*`.

**Коммиты** — Conventional Commits, префиксы `feat`, `fix`, `refactor`, `ui`,
`design`, `docs`, `chore`. Ранние (`updates`, `clean`, `fixes and other`) —
легаси, не повторять.

**Shorebird (code push)** — `shorebird.yaml`, `auto_update` не отключён, файл в
assets. Вероятно, поэтому самообновление через `UpdateManager` и выключено.
CLI не автоматизирован.

---

## Файлы, которые нельзя править вручную

`GeneratedPluginRegistrant.*`, `ios/Flutter/Generated.*`, `.flutter-plugins*`,
`.dart_tool/`, `build/`, `android/.gradle/`, `.metadata`,
`android/local.properties`, keystore-файлы. `pubspec.lock` — только через
`flutter pub`.

## Править осторожно

| Путь | Риск |
|---|---|
| `.env` | Правка `SIGN_*` ломает сборку; `.env` едет в APK |
| `main.dart` (регистрация адаптеров, открытие боксов) | Пропущенный `registerAdapter` = падение при чтении бокса |
| `model/*.dart` (`read`/`write`) | Несимметричное изменение = потеря данных пользователей |
| `android/app/build.gradle` | Читает `.env` на этапе конфигурации |
| `pubspec.yaml`, секция `assets` | `.env` и `shorebird.yaml` должны там остаться |

---

## Ограничения инструментария

1. **Линтер не работает** — правила не применяются, ориентир только форма
   соседнего кода.
2. **`flutter test` красный** из-за пустого шаблона.
3. **Форматирование не соблюдено** в 40% файлов.
4. **CI отсутствует.**
5. **Зависимости устарели:** `143 packages have newer versions`, есть
   discontinued-пакет и security advisory. Не обновляй без отдельной задачи:
   `go_router` 8.x удаляет `GoRouter.location`, который используется в
   `app_bar.dart` и `qr_result_screen.dart`.
6. **`mobile_scanner` — beta-версия в проде.**
7. **`flutter_localizations` подключить нельзя** — требует intl 0.19, а
   понижение с 0.20 ломает сборку Flutter. Отсюда самописные листы выбора даты
   и времени.
8. **iOS не проверяется** — нет macOS-окружения, в `ios/` лежат чужие
   Firebase-конфиги.

---

## Если понадобятся тесты

Реалистично покрывается без рефакторинга: `SseLineParser.handleLine`,
`TasksFilterState.apply`, `NotificationFormatters.*`, `*.fromJson` моделей,
`UsageParameter.validate`, и — самое ценное для этого проекта —
**симметричность Hive-адаптеров** (`write` → `read` → сравнение), защищающая от
потери данных пользователей.

Покрыть **нельзя** без изменения архитектуры всё, что ходит через `API`:
статические поля и `package:http` напрямую, точки внедрения клиента нет.
Widget-тесты экранов требуют почти полного `main()`.

Первый тестовый файл должен **заменить** `test/widget_test.dart`, иначе
`flutter test` продолжит падать на нём.
