# Конвенции кода

Условные обозначения силы правила:

- **[ЖЁСТКО]** — нарушение ломает данные, сборку или контракт. Не отступать.
- **[ДОМИНИРУЕТ]** — так написано подавляющее большинство кода. Следовать.
- **[СМЕШАНО]** — в проекте оба варианта. Указан рекомендованный.
- **[ЛЕГАСИ]** — так писали раньше. Не тиражировать.

> **Важно про линтер.** `analysis_options.yaml:1` подключает
> `package:analysis_defaults/flutter.yaml`, которого нет в зависимостях — include
> не резолвится, и блок `linter.rules` **не применяется**. Значит, форматирование
> и стиль не навязаны инструментом: единственный ориентир — форма соседнего кода.
> `flutter analyze` даёт ровно 1 предупреждение (`include_file_not_found`),
> это эталонное состояние.

---

## Именование

### Файлы и папки — **[ЖЁСТКО]** `snake_case.dart`

Экраны — `*_screen.dart` (`login_screen.dart`, `notifications_screen.dart`).
Сервисы — `*_service.dart`. Контроллеры — `*_controller.dart`.
Part-файлы именуются по родителю с суффиксом: `data_provider_remote.dart`,
`api.dart` → `auth_api.dart` / `scan_api.dart`.
Барреллы — по имени старого god-файла (`tasks.dart`, `tasks_filter.dart`),
содержат только `export`.

Исключение-легаси: `qa_actions.dart` содержит класс `QRActions` (имена не совпадают).

### Классы — PascalCase; аббревиатуры пишутся заглавными

`QRScreen`, `QRResultScreen`, `QRActions`, `API`, `SseLineParser`,
`InventoryRecord`, `AppNotification`. **[ДОМИНИРУЕТ]**

### Приватные State-классы — **[СМЕШАНО]**

Два варианта в проекте:
```dart
class _LoginScreenState extends State<LoginScreen>          // с суффиксом State
class _SelectStateButton extends State<SelectStateButton>   // без суффикса
```
Первый — новее и встречается во всех переписанных файлах.
**Пиши `_XxxState`.** Второй вариант живёт только в мёртвых `select_*`-виджетах
и `button_with_select_dialog.dart`.

### Приватные виджеты-помощники — **[ДОМИНИРУЕТ]**

Живут в **том же файле**, что и экран, с префиксом `_`:
`_PrimaryActionCard`, `_SecondaryActionCard`, `_IconCircle`, `_NotificationsCard`,
`_ServiceSection`, `_ServiceTile`, `_SettingsSheet` (`qa_actions.dart`);
`_HeroPassport`, `_SubmitBar` (`qr_result_screen.dart`);
`_SectionLabel`, `_CountChip`, `_ActionCard`, `_ActionRow`, `_UsageList`,
`_UsageRow`, `_PhotoStrip`, `_PhotoSlot` (`result_controls.dart`);
`_StatusPill`, `_PriorityPill`, `_DeadlinePill` (`notification_card.dart`).

**Не выноси такой виджет в `lib/src/widgets/`, если он используется одним
экраном.** В `widgets/` живёт только то, что реально переиспользуется.

### Поля и переменные

- Приватные поля состояния — `_busy`, `_passwordVisible`, `_serviceExpanded`,
  `_isSyncingScans`, `_highlightDescError`. **[ДОМИНИРУЕТ]**
- Локальные алиасы темы в `build()` — **[ЖЁСТКО ПО ФОРМЕ]** ровно эти два имени:
  ```dart
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  ```
  Встречаются в ~30 файлах. Не пиши `colorScheme` / `textTheme` / `theme`.
- Контроллеры формы — `<смысл>Controller`: `descController`,
  `priorityController`, `problemController`, `usageController`, `stateController`.
- Константы времени/порогов — `static const Duration _readTimeout`,
  `_silentDropThreshold`, `_keepaliveCheckInterval`, `_watchdogInterval`.

### Одно исключение из camelCase — **[ЛЕГАСИ]**

`User.JWTToken` (`lib/src/model/user.dart:8`) — с заглавной. Менять нельзя:
поле пишется/читается Hive-адаптером. Просто не повторяй.

---

## Импорты

### **[ДОМИНИРУЕТ]** относительные импорты (219 против 7)

```dart
import '../../global_state.dart';
import '../../src/model/inventory_record.dart';
import '../design/app_constants.dart';
```
Причём распространена **избыточная** форма `'../../src/model/x.dart'` из файла,
который уже лежит в `lib/src/` — она работает, потому что путь поднимается до
`lib/` и снова заходит в `src/`. Так написана бо́льшая часть проекта.

`package:qr_scan_industry/...` встречается 7 раз, вперемешку с относительными
в тех же файлах (`main.dart:12-14`, `qa_actions.dart:3`,
`equipment_list_screen.dart:3`, `qr_result_screen.dart:8`).

**Правило для нового кода:** повторяй стиль импортов **того файла, который
правишь**. При создании нового файла — относительные импорты. `REFACTORING_CHECKLIST.md`
Phase 2 отмечает унификацию как отложенную до переезда папок.

### Порядок импортов — **[ДОМИНИРУЕТ]**

```dart
import 'dart:async';            // 1. dart:
import 'dart:convert';

import 'package:flutter/material.dart';   // 2. package:
import 'package:go_router/go_router.dart';

import '../../global_state.dart';         // 3. локальные
import '../design/app_constants.dart';
```
Внутри групп — без строгой сортировки. Пустая строка между группами
соблюдается не везде (`main.dart` смешивает всё), но в переписанных файлах —
да (`notifications_service.dart:1-13`).

### Барреллы — **[ДОМИНИРУЕТ]** только как результат разбиения god-файла

`lib/src/tasks/tasks.dart` и `lib/src/tasks/tasks_filter.dart` содержат только
`export` и существуют, чтобы не переписывать импорты у потребителей. Новые
барреллы «для красоты» не заводить.

### `part` / `extension` — **[ДОМИНИРУЕТ]** способ разбить крупный класс

Так разбиты `API` и `DataProvider`:
```dart
// api.dart
part 'auth_api.dart';
part 'equipment_api.dart';

// auth_api.dart
part of 'api.dart';
extension AuthApi on API { … }
```
**Подводный камень:** методы из extension видны только там, где импортирована
**библиотека целиком** (`api.dart` / `data_provider.dart`) — импорт part-файла
напрямую не сработает. Это уже кусало проект, см. `REFACTORING_CHECKLIST.md`, Phase 3.

---

## Виджеты

### `const` — **[СМЕШАНО]**, склоняется к `const` в новом коде

`prefer_const_constructors` в конфиге явно выключен
(`analysis_options.yaml:8`) — но конфиг не применяется. В переписанных файлах
`const` расставлен последовательно (`qa_actions.dart`, `notification_card.dart`,
`empty_state.dart`). **Ставь `const`, где можно.**

### Конструктор виджета — **[ДОМИНИРУЕТ]**

```dart
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });
```
`super.key` (не `Key? key : super(key: key)`), named-параметры, `required` для
обязательных, поля объявлены **до** конструктора.

**[ЛЕГАСИ], не повторять** — конструктор с телом и `late final`:
```dart
class SelectPriorityButton extends StatefulWidget {
  late final AnyController<Priority> controller;
  SelectPriorityButton({super.key, controller = null}) {
    if (controller == null) { this.controller = AnyController<Priority>(); }
    else { this.controller = controller; }
  }
```
(`select_priority_button.dart:8-17`) — нетипизированный параметр, не-`const`
конструктор, мутация в теле. Все такие виджеты сейчас мертвы.

### Сложность `build()` — **[ДОМИНИРУЕТ]** декомпозиция подвиджетами

`build()` экрана собирает дерево из приватных виджетов и локальных функций,
а не разворачивает 300 строк вложенности. Эталон — `qa_actions.dart:100-189`
(90 строк на весь экран) и `equipment_list_screen.dart`.

Обработчики выносятся в **методы `State`** с префиксом `_` и говорящим именем:
`_onScan`, `_onTasks`, `_onSync`, `_onResetScans`, `_onInfo`, `_onSettings`.
Локальные функции внутри `build()` тоже встречаются (`doLogin` в
`login_screen.dart:50`, `_logout` в `app_bar.dart:21`) — допустимо, когда нужен
захват локальных переменных.

### `addPostFrameCallback` из `build()` — **[ЛЕГАСИ]**

```dart
WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
  UpdateManager.checkForUpdate(context);
});
```
Встречается в `login_screen.dart:43`, `qr_screen.dart:194`, `qa_actions.dart:102`,
`qr_result_screen.dart:276` — то есть колбэк регистрируется **на каждый ребилд**.
`REFACTORING_CHECKLIST.md`, «Прочее» помечает это как подлежащее переносу в
`initState`. **В новом коде — `initState`.**

### Подписка на контроллер — **[ДОМИНИРУЕТ]** `ControllerListenerMixin`

```dart
class _State extends State<Foo> with ControllerListenerMixin {
  @override
  Listenable get controllerListenable => widget.controller.valueNotifier;

  @override
  void onControllerChanged() { setState(() { value = widget.controller.value; }); }
}
```
(`lib/src/widgets/controller_listener_mixin.dart`, 7 потребителей). Убирает
ручные `addListener`/`removeListener`. Если подписок несколько — делай их
руками в `initState`/`dispose`, как в `result_controls.dart:56-72` и
`qr_result_screen.dart:451-480`.

### `mounted` — **[ЖЁСТКО]** перед любым `context` после `await`

```dart
if (!mounted) return;
Dialogs.notify(context, …);
```
Соблюдается в `login_screen.dart`, `qa_actions.dart`, `qr_result_screen.dart`,
`notifications_screen.dart`. Не пропускай.

---

## Управление состоянием

- **[ДОМИНИРУЕТ]** локальное состояние — `setState` в `State`.
- **[ДОМИНИРУЕТ]** разделяемое реактивное состояние — `ValueNotifier` +
  `ValueListenableBuilder`. Образец — `NotificationsService`.
- **[ДОМИНИРУЕТ]** значение формы — `AnyController<T>`
  (`lib/src/utils/any_controller.dart`). Не пиши собственный
  `XxxController` с `ValueNotifier<String>` внутри — так сделаны
  `SelectImageButtonController` и `ButtonWithSelectDialogController`, и это
  помечено в чек-листе как подлежащее замене на `AnyController`.
- **[СМЕШАНО]** доступ к `DataProvider`: `context.watch<DataProvider>()` в
  `build()`, `GlobalState.dataProvider` вне контекста. Оба варианта живут в
  одном файле. Рекомендация — та же: контекст в `build()`, статик в колбэках.
- Нет: BLoC, Riverpod, GetX, `ChangeNotifier`-модели, `freezed`.

---

## Модели

### **[ЖЁСТКО]** Hive-адаптеры пишутся руками, симметрично

```dart
class ScanAdapter extends TypeAdapter<Scan> {
  @override
  final int typeId = 2;                 // уникальный, переиспользованию не подлежит

  @override
  Scan read(BinaryReader reader) { … }  // ТОТ ЖЕ порядок, что и в write

  @override
  void write(BinaryWriter writer, Scan obj) { … }
}
```
Занятые `typeId`: 0–4, 6–28 (5 освобождён удалением `inventory_scan.dart`,
но переиспользовать его **нельзя** — на старых устройствах могут лежать записи).
Следующий свободный — 29. Новый адаптер обязательно зарегистрировать в
`main.dart:117-144`.

**Добавление поля в существующую модель** — единственный безопасный способ
(образцы: `scan.dart:76-105`, `repair.dart:271-283` — там же вынесен помощник
`_readTrailingList<T>`, возвращающий пустой список вместо падения):
```dart
// write: новое поле — ПОСЛЕДНИМ
writer.write(obj.isOtherFault);

// read: обёрнуто в try/catch на случай старых записей
bool? isOtherFault;
try { isOtherFault = reader.read(); } catch (_) { isOtherFault = null; }
```

Смена типа существующего поля (например `String` → `enum`) **запрещена** —
`REFACTORING_CHECKLIST.md`, Phase 7 фиксирует это решение явно.

### **[ДОМИНИРУЕТ]** `fromJson` — фабрика с ручным приведением

```dart
factory Company.fromJson(Map<String, dynamic> json) {
  return Company(
    id: json['id'] as int,
    logoUrl: json['logo_url'] as String?,
    tariffValidUntil: json['tariff_valid_until'] != null
        ? DateTime.parse(json['tariff_valid_until'] as String) : null,
  );
}
```
Ключи JSON — `snake_case` (контракт бэкенда), поля Dart — `camelCase`.

**[СМЕШАНО]** второй вариант — pattern matching со `switch`:
```dart
factory Session.fromJson(Map<String, dynamic> json) {
  return switch (json) {
    {'id': int id, 'status': String status, …} => Session(…),
    _ => throw const FormatException('Failed to load session from json.'),
  };
}
```
(`session.dart:19-30`, `user.dart:14-23`, `inventory_record.dart:119-151`).
Он строже — падает на неполном ответе. Оба варианта живы;
для необязательных полей используй первый.

`toJson()` есть **не у всех** моделей — только у тех, что отправляются:
`Scan`, `UsageUpdate`, `PeriodicTaskRequest`, `Company`, `NotificationSettings`.

### **[ДОМИНИРУЕТ]** ключ элемента очереди = md5 содержимого

```dart
String key() => GlobalState.digest(jsonEncode({ 'files': files, … }));
```
(`scan.dart:19`, `usage_update.dart:11`, `periodic_task_request.dart:17`).
Даёт дедупликацию по содержимому. `GlobalState.digest` — md5 из `package:crypto`.

### `==` / `hashCode` — по `uuid` там, где объект кладут в `Set`/сравнивают

`Task` (`task.dart:64-72`), `InventoryRecord` (`inventory_record.dart:100-108`),
`TypicalProblem` (по `id ^ uuid`). Добавлено осознанно ради `Set<Task>` в
`EquipmentDetailController` (`REFACTORING_CHECKLIST.md`, Phase 7).

### `copyWith` — **[СМЕШАНО]**, есть только у `InventoryRecord`

Модели преимущественно `final` + иммутабельны, но есть мутабельные поля:
`Scan.resultStatus`, `UsageParameter.currentValue`, `User.password/role/JWTToken`,
`NotificationSettings.*`. Не считай иммутабельность гарантией.

---

## Сервисы и HTTP

### **[ЖЁСТКО]** шаблон метода `API`

```dart
extension EquipmentApi on API {
  Future<List<InventoryRecord>> getEquipment({limit = 10, offset = 0}) async {
    _guardOffline();                                     // 1. рубильник симуляции
    if (API.jwtToken == null) {                          // 2. проверка авторизации
      throw Exception('Not authenticated');
    }
    final response = await http.get(
      Uri.parse('${API.baseUrl}/v1/company/equipment?limit=${limit}&skip=${offset}'),
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);                         // 3. обязательный таймаут

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);   // 4. кириллица
      final decodedBytes = utf8Decoder.convert(response.bodyBytes);
      final List<dynamic> data = jsonDecode(decodedBytes);
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load inventory: ${response.statusCode}');
    }
  }
}
```
Все четыре шага обязательны. Таймауты: `API._readTimeout` 15 с (GET и мелкие
записи), `API._uploadTimeout` 60 с (multipart с фото), `API._aliveTimeout` 5 с
(только `isAlive`).

**Пагинация:** параметр называется `skip`, не `offset` — при том что аргумент
метода зовётся `offset`. Не перепутай (`equipment_api.dart:12`, `task_api.dart:11`).

**Не** используется `dio`, хотя он в зависимостях. Только `package:http`.

### **[ДОМИНИРУЕТ]** метод `DataProviderSync`

```dart
Future<void> syncUsageUnitTypes() async {
  _isLoading = true;
  try {
    _usageUnits = await loadAllUsageUnitTypes();
    await usageUnitBox.clear();
    await usageUnitBox.addAll(_usageUnits);
  } catch (e) {
    print('Failed sync usage unit types: $e');
  } finally {
    _isLoading = false;
  }
}
```
Полная замена содержимого бокса, ошибка глотается с `print`. Новый справочник
добавляется по этому шаблону + вызов в `mainSync()` (`data_provider_sync.dart:127-138`).

### Синглтон-сервис — **[ДОМИНИРУЕТ]**

```dart
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();
```

---

## Асинхронность

- **[ЖЁСТКО]** у каждого сетевого вызова — `.timeout(...)`.
- **[ДОМИНИРУЕТ]** `Future<void>` для операций без результата; `Future<bool>` —
  для «получилось / нет» (`api.sendScan`, `api.updateUsageParameter`,
  `api.createPeriodicTask`).
- **[ДОМИНИРУЕТ]** возврат результата операции через `enum`, когда UI должен
  выбрать сообщение: `enum SyncResult { noConnection, allSynced, scansSynced,
  scansFailed }` (`data_provider_sync.dart:4`). Хороший образец.
- **[ЛЕГАСИ]** вечный цикл вместо таймера:
  ```dart
  Future.sync(() async {
    while (true) {
      await Future.delayed(Duration(seconds: 5));
      await syncScans();
    }
  });
  ```
  (`data_provider_sync.dart:140-161`, `main.dart:179-184`). Не останавливается
  никогда, не отменяется. Не заводи новые такие циклы — используй `Timer.periodic`,
  как `NotificationsService._keepaliveTimer` и `PushNotificationsController._watchdog`.
- `unawaited(...)` используется только в `qr_screen.dart:41,76,78`.

---

## Обработка ошибок

- **[ДОМИНИРУЕТ]** `throw Exception('Failed to <что>: ${response.statusCode}')` —
  без кастомных типов.
- **[ДОМИНИРУЕТ в новом коде]** если бэкенд отдаёт осмысленный русский `detail`
  (ремонты, ЗИП, нормы) — доставать его и показывать пользователю, а не код
  ответа. Помощники в `api.dart`: `_serverDetail(response, fallback)` и
  `_throwServerError(...)`; перевод в текст для UI — `repairErrorMessage`
  (`repairs/repair_error_messages.dart`).
- **[ЖЁСТКО]** отличай «сервер отказал» от «нет связи» и от «протух токен»,
  если код работает в фоновой очереди: `isRetryableRepairError` и
  `AuthExpiredException` (401 выделяется в `_throwServerError`). Отказ —
  запомнить причину и не повторять; связь/токен — повторить позже.
- **[ЖЁСТКО]** кастомные исключения — только четыре, три про логин и
  `AuthExpiredException` (`lib/src/exceptions/app_exceptions.dart`). Форма:
  ```dart
  class WalkerOnlyException implements Exception {
    final String message;
    WalkerOnlyException([this.message = 'Only walkers can login']);
    @override
    String toString() => message;
  }
  ```
- **[ДОМИНИРУЕТ]** на экране — `try / on X / on Y / catch (e) / finally` с
  показом `Dialogs.notify` (эталон: `login_screen.dart:52-95`).
- **[ЛЕГАСИ, но повторяемо]** детект офлайна строками. Если нужен — копируй форму
  `_isOfflineError` из `qr_result_screen.dart:80-88`, не пиши четвёртый вариант.
- Нет: `Result<T,E>`, `Either`, sealed-иерархий ошибок, глобального
  `FlutterError.onError` / `runZonedGuarded`.

---

## Логирование

Три механизма одновременно — **[СМЕШАНО]**:

| Механизм | Где | Использовать? |
|---|---|---|
| `print(...)` (19 шт.) | `data_provider_*`, `scan_api.dart`, `update_manager.dart` | Нет |
| `debugPrint(...)` (37 шт.) | `notifications_*`, `push/*` | **Да** — доминирует в свежем коде |
| `package:logging` `Logger` (1 шт.) | `app_lifecycle.dart:19` | Настроен в `main()`, но почти не используется |

**Правило:** новый код — `debugPrint` с префиксом-тегом в квадратных скобках,
как в push-подсистеме: `debugPrint('[Push] startService result: $result')`,
`debugPrint('[NotifTask] missing base url or jwt — abort')`.

Крашрепортинга нет (ни Sentry, ни Crashlytics), несмотря на остатки
Firebase-конфигов в `ios/`.

---

## Локализация

- **[ЖЁСТКО]** язык один — русский. `flutter_localizations`,
  `localizationsDelegates`, `supportedLocales`, ARB-файлы **отсутствуют**.
- `lib/strings.dart` — самодельный класс:
  ```dart
  class Strings {
    static final locale = 'ru';
    static get logout => {'ru': 'Выйти'}[Strings.locale];
  }
  ```
  Геттеры нетипизированы (`get`, а не `String get`) и пересобирают Map на каждый
  вызов. Помечено в `REFACTORING_CHECKLIST.md` как подлежащее исправлению.
- **[СМЕШАНО]** реально: `Strings.*` вызывается 67 раз, а русских строковых
  литералов прямо в виджетах — около 340. То есть **большинство текста
  захардкожено**.
- **[ДОМИНИРУЕТ в новом коде]** строки фичи — отдельным классом-контейнером в
  том же `lib/strings.dart`: `RepairStrings`, `RepairCardStrings`,
  `ConflictStrings`, `SparePartStrings`. Внутри — `static const String`
  (а не Map-геттеры, как в старом `Strings`) и статические методы для строк с
  подстановкой. **Так же заводи строки для новых фич**: класс на фичу, а не
  вываливание в общий `Strings`.
- **Рекомендация:** переиспользуемые/повторяющиеся строки («Отмена», «Понятно»,
  «Да»/«Нет», названия действий) — в `Strings`. Уникальные тексты конкретного
  экрана — можно литералом рядом с местом использования, как сейчас в
  `qa_actions.dart`, `notification_card.dart`, `empty_state`-вызовах.
- Даты форматируются через `intl`: `DateFormat('dd.MM.yyyy HH:mm')`
  (`notification_formatters.dart:29`), `DateFormat('dd-MM-yyyy HH:mm:ss')`
  (`data_provider.dart:107`), русская локаль подтягивается через
  `initializeDateFormatting('ru_RU', null)` (`global_state.dart:87`).
- Склонения по числу пишутся вручную — образец `_pluralizeTasks`
  (`equipment_list_screen.dart:152-162`).

---

## Комментарии и документация

- **[ДОМИНИРУЕТ]** doc-комментарии `///` **на русском**, перед классом или
  нетривиальным методом, объясняют **зачем**, а не что:
  ```dart
  /// Хранилище приложения (Hive-боксы + in-memory кэш). Сетевые загрузки,
  /// фоновая синхронизация и офлайн-очереди вынесены в part-файлы …
  ```
  (`data_provider.dart:25-27`). Отличные примеры: `app_theme.dart:15-27`,
  `data_provider_outbox.dart:32-34`,
  `notifications_service.dart:31-35`, `app_theme.dart:358-368`.
- **[ДОМИНИРУЕТ]** ASCII-разделители секций внутри крупных файлов:
  ```dart
  // ───────────────────────────────────────────────────────────
  // Sub-themes
  // ───────────────────────────────────────────────────────────
  ```
  (`app_theme.dart`, `qa_actions.dart`, `result_controls.dart`).
- **[ЛЕГАСИ]** крупные закомментированные блоки старого кода
  (`main.dart:86-92,166-174`, `splash_screen.dart:35-61`,
  `global_state.dart:59-65`, `android/settings.gradle:1-11`). Не добавляй новые;
  при правке файла старые удалять можно.
- **Комментируй нетривиальные обходные пути.** Проект это делает системно — в
  комментариях зафиксированы: причина запрета `tabularFigures`, причина
  инициализации `_finished` в `_MyReveal`, причина `NotificationChannelImportance.MIN`,
  причина `go()` вместо `clearStackAndNavigate()` в push-роутере. Продолжай.

---

## Тесты

Тестов нет. `test/widget_test.dart` полностью закомментирован, `flutter test`
падает. Инфраструктуры моков и фикстур не существует.

**Если задача требует тестов** — см. `testing-build-and-release.md`, раздел
«Если понадобится завести тесты»: `hive_ce` можно поднять на временной
директории, `API` подменить нельзя (статические поля + `package:http` напрямую),
поэтому реалистично тестируются только чистые куски: `SseLineParser`,
`TasksFilterState.apply`, `NotificationFormatters`, `*.fromJson`,
`_pluralizeTasks`, симметричность Hive-адаптеров.

---

## Что считать образцом

Файлы, переписанные последними и наиболее близкие к «как надо» — на них
ориентируйся при сомнениях:

| Категория | Эталон |
|---|---|
| Экран-хаб / карточки | `lib/src/qr/qa_actions.dart` |
| Экран-список с состояниями | `lib/src/tasks/equipment_list_screen.dart` |
| Экран с пагинацией и загрузкой | `lib/src/notifications/notifications_screen.dart` |
| Компонент-карточка с пилюлями | `lib/src/notifications/notification_card.dart` |
| Переиспользуемый виджет | `lib/src/widgets/empty_state.dart` |
| Сервис с реактивным состоянием | `lib/src/notifications/notifications_service.dart` |
| Чистая логика без Flutter | `lib/src/notifications/sse_line_parser.dart` |
| Метод API | `lib/src/http/equipment_api.dart` |
| Метод API с разбором `detail` и идемпотентностью | `lib/src/http/repair_api.dart` |
| Очередь отправки | `lib/src/data/data_provider_outbox.dart` (`syncPeriodicTasks`) |
| Очередь с побочным эффектом на сервере | `data_provider_outbox.dart` (`syncPendingRepairs`) |
| Модель с Hive | `lib/src/model/usage_update.dart` |
| Модель с вложенными объектами API и поздним полем | `lib/src/model/repair.dart` |
| Строки фичи | `RepairCardStrings` в `lib/strings.dart` |
| Тема и токены | `lib/src/design/app_theme.dart`, `app_constants.dart` |

Файлы, на которые ориентироваться **не надо**: `lib/src/update_manager.dart`,
`lib/src/design/theme_extensions.dart`,
`lib/src/widgets/select_*_button.dart` (кроме `select_image_button` и
`select_task_button`), `lib/src/widgets/button_with_select_dialog.dart`,
`lib/src/design/README.md`.
