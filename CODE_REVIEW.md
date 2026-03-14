# Code Review — QR Scan Industry

**Дата:** 04.02.2025  
**Проект:** Flutter-приложение для QR-сканирования и учёта оборудования

---

## Содержание
1. [Безопасность](#1-безопасность)
2. [Архитектура](#2-архитектура)
3. [Качество кода](#3-качество-кода)
4. [Обработка ошибок](#4-обработка-ошибок)
5. [Производительность](#5-производительность)
6. [Тестирование](#6-тестирование)
7. [Рекомендации по рефакторингу](#7-рекомендации-по-рефакторингу)
8. [Мелкие замечания](#8-мелкие-замечания)

---

## 1. Безопасность

### 🔴 Критично

#### 1.1 Файл `.env` и секреты
- **Проблема:** `.env` не добавлен в `.gitignore`. В git status он помечен как `??` (untracked), но риск случайного коммита высок.
- **Решение:** Добавить в `.gitignore`:
  ```
  .env
  .env.*
  !.env.example
  ```
- Создать `.env.example` с placeholder-значениями без реальных секретов.

#### 1.2 Хранение паролей
- **Проблема:** В `User` пароль хранится в открытом виде и сохраняется в Hive (`UserAdapter`).
- **Файлы:** `lib/src/model/user.dart`, `lib/global_state.dart`
- **Решение:**
  - Не сохранять пароль в Hive. Использовать только JWT.
  - Для offline-логина рассмотреть отдельный механизм (биометрия, PIN), без хранения пароля в БД.

#### 1.3 API-учётные данные
- **Проблема:** `API.username`, `API.password`, `API.basicAuth` — статические поля, инициализируются из `.env` при загрузке.
- **Рекомендация:** Оставить как есть для server-to-server auth (isAlive), но убедиться, что в `.env` только dev/тестовые ключи, а prod-секреты — через переменные окружения/secure storage.

### 🟡 Рекомендации
- Использовать `flutter_secure_storage` для JWT и чувствительных данных.
- Для web — избегать хранения секретов в `localStorage`.

---

## 2. Архитектура

### 🔴 Проблемы

#### 2.1 GlobalState как God Object
- **Файл:** `lib/global_state.dart`
- **Проблема:** Глобальное статическое состояние (`dataProvider`, `authUser`, `debug`, `hasConnectionToServer` и т.д.) создаёт жёсткие связи и усложняет тестирование.
- **Решение:**
  - Использовать Provider/Riverpod/Bloc для DI и состояния.
  - `DataProvider` и `authUser` — через `Provider`.
  - `hasConnectionToServer` — отдельный сервис/репозиторий.

#### 2.2 Смешение ответственностей в DataProvider
- **Файл:** `lib/src/data/data_provider.dart`
- **Проблема:** Класс одновременно: хранилище, синхронизатор, логика авторизации, работа с Hive, вызовы API.
- **Решение:** Разделить на:
  - `AuthRepository` — логин, токены, текущий пользователь.
  - `SyncService` — синхронизация (inventory, tasks, scans).
  - `LocalStorage` / `HiveRepository` — работа с боксами.

#### 2.3 Роутинг `/details/:index`
- **Файл:** `lib/main.dart` (строки 241–253)
- **Проблема:**
  ```dart
  final index = int.parse(state.pathParameters['index']!);
  ...
  GlobalState.dataProvider.inventoryRecords
      .where((element) => element.id == index)
      .first  // ← выбросит StateError, если нет записи
  ```
- **Решение:**
  - Обработать `FormatException` от `int.parse`.
  - Использовать `firstWhere(orElse: () => throw NotFoundException())` или `firstOrNull` и редирект на 404/главную.

#### 2.4 Дублирование маршрутов `/qr_result` и `/qr_result_problems`
- Оба роута почти идентичны. Можно объединить в один с query-параметром, например `?mode=problems`.

### 🟡 Рекомендации
- Использовать единый стиль импортов (`package:my_app/...` вместо `../../` где возможно).
- Вынести конфигурацию роутов в отдельный файл (`router.dart`).

---

## 3. Качество кода

### 🔴 Критично

#### 3.1 Огромный файл `tasks.dart` (963 строки)
- **Файл:** `lib/src/tasks/tasks.dart`
- **Проблема:** В одном файле — модели (`Equipment`, `Checklist`), контроллер, экраны списка и деталей, хардкод цветов.
- **Решение:**
  - `models/equipment.dart` — `Equipment`, `Checklist`.
  - `controllers/equipment_detail_controller.dart`.
  - `screens/equipment_list_screen.dart`.
  - `screens/equipment_detail_screen.dart`.
  - `constants/period_colors.dart`.

#### 3.2 Дублирование в `_buildTaskItem` и `_buildOpenTaskItem`
- **Файл:** `lib/src/tasks/tasks.dart`
- Оба метода содержат похожий UI (чекбокс, контейнер, контент). Вынести общую часть в отдельный виджет, например `_TaskItemCard`.

#### 3.3 Баг в `EquipmentDetailController.selectAll`
- **Строки 60–69:** `selectAll` фактически выбирает только первую задачу:
  ```dart
  if (allTasks.isNotEmpty) {
    selectedTasks.add(allTasks.first);  // ← только первая!
    value = [allTasks.first];
  }
  ```
- По коду и UI ("Выберите только одну задачу") — возможно, это намеренно, но название `selectAll` misleading. Переименовать в `selectFirst` или явно ограничить выбор одной задачей в UI.

#### 3.4 Список не удаляется при `list.length == 0`
- **Файл:** `lib/src/tasks/tasks.dart`, строки 116–138
- **Проблема:** При `equipmentList.length == 0` возвращается `ListView` с `itemCount: 1`, но при `taskCount == 0` элемент всё равно показывается. Логика «нет задач» и «нет оборудования» смешана.
- **Рекомендация:** Упростить условие и использовать `equipmentList.isEmpty`.

### 🟡 Важно

#### 3.5 `print()` вместо логгера
- **Файлы:** `api.dart`, `data_provider.dart`, `qr_result_screen.dart`, `update_manager.dart`
- В проекте уже есть `logging` (см. `main.dart`). Заменить все `print()` на `Logger`.
- Пример:
  ```dart
  final _log = Logger('DataProvider');
  _log.warning('Failed sync inventory', e, s);
  ```

#### 3.6 Опасные вызовы `.toList()[0]`
- **Файлы:**
  - `data_provider.dart`: `periodRealName`, `getUsageUnitDisplayName`, `getUsageUnitShortName`
- **Проблема:** Если список пустой — `RangeError`.
- **Решение:** Использовать `firstOrNull` или `firstWhere` с `orElse` и обработать отсутствие значения.

#### 3.7 Несогласованность импортов
- В `main.dart`: смесь `package:my_app/...` и `../../src/...`. Лучше придерживаться `package:my_app/...`.

#### 3.8 Неиспользуемый код
- **main.dart:**
  - `flatButtonStyle` — не используется.
  - `outlineButtonStyle` с `Colors.red` как `backgroundColor` — выглядит как ошибка.
  - `textButtonTheme` использует `raisedButtonStyle` — путаница в названиях.

#### 3.9 Debug-панель в production
- **main.dart, строки 311–322:** Нижняя панель с `GlobalState.debug` отображается всегда.
- **Рекомендация:** Показывать только в debug-режиме:
  ```dart
  if (kDebugMode)
    Container(...)  // debug bar
  ```

---

## 4. Обработка ошибок

### 🔴 Проблемы

#### 4.1 API: общие Exception
- **Файл:** `lib/src/http/api.dart`
- Почти везде выбрасывается `Exception('...')`. Для логина уже используются кастомные исключения (`InvalidCredentialsException`, `NoConnectionException`).
- **Рекомендация:** Ввести и использовать `ApiException`, `NotAuthenticatedException` и т.п. для единообразной обработки на UI.

#### 4.2 DataProvider: тихие ошибки
- В `syncInventory`, `syncTypicalProblems` и др. при ошибке только `print()`, пользователь не получает обратной связи.
- **Рекомендация:** События об ошибках синхронизации — через Stream/ValueNotifier или callback, с показом SnackBar/диалога.

#### 4.3 QRResultScreen: listener не снимается
- **Файл:** `lib/src/qr_result/qr_result_screen.dart`
- В `dispose` закомментировано: `// stateController.valueNotifier.removeListener(_onStateChanged);`
- **Проблема:** После dispose виджета `_onStateChanged` может быть вызван при обновлении `stateController`, что приведёт к обращению к несуществующему контексту/виджету.
- **Решение:** Раскомментировать и вызывать `removeListener` перед `stateController.dispose()`.

### 🟡 Рекомендации
- Для `Future.sync()` в `main.dart` и `DataProvider` — оборачивать в try-catch, чтобы бесконечные циклы синхронизации не падали «тихо».
- Добавить обработку `dotenv.load()` — если `.env` отсутствует, приложение должно сообщать об этом, а не падать при обращении к `dotenv.env["..."]!`.

---

## 5. Производительность

### 🟡 Рекомендации

#### 5.1 Повторные вызовы `getTasksForMachine`
- **Файл:** `lib/src/tasks/tasks.dart`, `EquipmentListScreen`
- `getTasksForMachine` вызывается многократно для одних и тех же машин в `sort` и `where`.
- **Решение:** Вычислить `taskCount` один раз и использовать мапу/кэш.

#### 5.2 Итерация по `inventoryBox.keys` при смене состояния
- **Файл:** `lib/src/qr_result/qr_result_screen.dart`, `_onStateChanged`
- Перебор всех ключей бокса при каждом обновлении состояния.
- **Решение:** Индексировать по `uuid` или хранить `key` в `InventoryRecord`, если возможно.

#### 5.3 Hive: `values.toList()` при каждом доступе
- В `getTasksForMachine`, `getTypicalProblemsForMachine` и т.п. — создаются новые списки. При большом объёме данных рассмотреть ленивую итерацию или кэширование.

---

## 6. Тестирование

### 🔴 Проблемы
- Папка `test/` минимальна, unit-тестов по сути нет.
- Отсутствуют тесты для:
  - `DataProvider` (логика синхронизации, логин).
  - API (mock HTTP).
  - Моделей (`Task.fromJson`, `InventoryRecord.fromJson` и т.д.).
  - `EquipmentDetailController`.

### 🟡 Рекомендации
- Добавить тесты для парсинга JSON в моделях.
- Добавить интеграционные тесты для критичных экранов (login, qr_result).
- Использовать `mockito` / `mocktail` для моков API и DataProvider.

---

## 7. Рекомендации по рефакторингу

### Приоритет 1
1. Добавить `.env` в `.gitignore`, создать `.env.example`.
2. Исправить снятие listener в `QRResultScreen.dispose`.
3. Защитить роут `/details/:index` от некорректного index и отсутствующей записи.
4. Убрать хранение пароля в Hive.

### Приоритет 2
1. Разбить `tasks.dart` на несколько файлов.
2. Заменить `print` на `Logger`.
3. Исправить/переименовать `selectAll` в `EquipmentDetailController`.
4. Вынести `periodColors` в константы/конфиг.

### Приоритет 3
1. Рефакторинг `GlobalState` и `DataProvider` (разделение на сервисы).
2. Унификация обработки ошибок API.
3. Добавление unit-тестов.

---

## 8. Мелкие замечания

| Файл | Замечание |
|------|-----------|
| `pubspec.yaml` | `name: my_app` — лучше заменить на осмысленное, например `qr_scan_industry`. |
| `analysis_options.yaml` | Стоит включить `prefer_const_constructors` и `prefer_single_quotes` по мере готовности. |
| `main.dart` | Закомментированный код (google_mobile_ads, js.context) — удалить или оформить как feature flag. |
| `Task` | `required this.periodicTask` в конструкторе, но в `fromJson` может быть `null` — типы совпадают, но стоит проверить консистентность. |
| `inventory_record.dart` | `location` в конструкторе `this.location = ''`, в `fromJson` `?? ''` — ок, но тип `String?` vs `String` в конструкторе. |
| `dart:io` в `qr_result_screen.dart` | `SocketException`, `HttpException` — на web эти типы недоступны. Использовать условный импорт или обёртки. |
| `Strings` | Все геттеры возвращают `{'ru': '...'}[Strings.locale]` — для единственной локали можно упростить или подготовить расширение под `intl`. |

---

## Итоговая сводка

| Категория | Критичных | Важных | Рекомендаций |
|-----------|-----------|--------|--------------|
| Безопасность | 2 | 1 | 1 |
| Архитектура | 3 | 1 | 2 |
| Качество кода | 4 | 4 | 2 |
| Обработка ошибок | 2 | 0 | 2 |
| Производительность | 0 | 0 | 3 |
| Тестирование | 1 | 0 | 2 |
| Рефакторинг | — | — | 9 пунктов |

Рекомендуется в первую очередь заняться безопасностью (.env, пароли), исправлением dispose/listener и защитой роутинга, затем — рефакторингом `tasks.dart` и логированием.
