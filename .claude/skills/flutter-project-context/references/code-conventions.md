# Конвенции кода

Пометки силы правила: **[ЖЁСТКО]** — нарушение ломает данные или сборку.
**[ДОМИНИРУЕТ]** — так написано большинство кода. **[ЛЕГАСИ]** — не тиражировать.

> **Линтер включили в августе 2026.** До этого `analysis_options.yaml:1`
> подключал `package:analysis_defaults/flutter.yaml` — пакета не было в
> зависимостях, поэтому не применялось ничего, кроме встроенных проверок.
> Сейчас подключён `package:flutter_lints/flutter.yaml`.
> Эталон `flutter analyze` — **106 замечаний уровня `info` и ни одного
> `warning`/`error`**. Все они — наследство: были в коде и до включения
> линтера. Разбирать их — отдельная работа; следи за тем, чтобы твоя правка не
> добавила `warning`. Сверяйся по уровню, а не по числу.
>
> Две строки `false` в `linter.rules` (`prefer_const_constructors`,
> `prefer_single_quotes`) по-прежнему ничего не выключают: ни того, ни другого
> правила во `flutter_lints` 5 нет. Оставлены как запись о решении.

---

## Именование

- Файлы — `snake_case.dart`. Экраны `*_screen.dart`, сервисы `*_service.dart`,
  контроллеры `*_controller.dart`. Part-файлы — по родителю: `api.dart` →
  `repair_api.dart`, `data_provider.dart` → `data_provider_sync.dart`.
- Классы — PascalCase, аббревиатуры заглавными: `QRScreen`, `API`,
  `SseLineParser`, `InventoryRecord`.
- Приватные `State` — `_XxxState`. (В мёртвых `select_*`-виджетах встречается
  `_Xxx` без суффикса — **[ЛЕГАСИ]**.)
- Приватные виджеты-помощники живут **в том же файле**, что и экран, с
  префиксом `_`. В `lib/src/widgets/` выноси только то, что реально
  переиспользуется двумя и более экранами.
- Локальные алиасы темы в `build()` — **[ЖЁСТКО ПО ФОРМЕ]** ровно эти имена:
  ```dart
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  ```
- **[ЛЕГАСИ]** `User.JWTToken` с заглавных — менять нельзя, поле пишется
  Hive-адаптером. Не повторять.

---

## Импорты

**[ДОМИНИРУЕТ]** относительные (219 против 7 `package:`). В новом файле — 
относительные; при правке существующего повторяй его стиль.

Порядок: `dart:` → `package:` → локальные, между группами пустая строка.

### **[ЖЁСТКО]** Подводный камень `part` / `extension`

Так разбиты `API` и `DataProvider`:

```dart
// api.dart
part 'repair_api.dart';

// repair_api.dart
part of 'api.dart';
extension RepairApi on API { … }
```

Методы из `extension` видны только там, где импортирована **библиотека
целиком** (`api.dart`, `data_provider.dart`), а не part-файл. Забыть этот
импорт — типовая ошибка проекта, она кусала уже трижды. Пример правильного
импорта с пояснением — `repairs_list_screen.dart` и `repair_detail_screen.dart`.

---

## Виджеты

Конструктор — **[ДОМИНИРУЕТ]**: `super.key`, named-параметры, `required` для
обязательных, поля объявлены до конструктора, `const` где возможно.

`build()` собирается из приватных подвиджетов, а не разворачивается в 300 строк
вложенности. Обработчики — методы `State` с префиксом `_`: `_onScan`, `_onSync`.

**[ЖЁСТКО]** `if (!mounted) return;` перед любым обращением к `context` после
`await`.

Подписка на один контроллер — `ControllerListenerMixin`
(`widgets/controller_listener_mixin.dart`). Если подписок несколько — вручную в
`initState`/`dispose`.

**[ЛЕГАСИ]** `addPostFrameCallback` из `build()` — колбэк регистрируется на
каждый ребилд. В новом коде — из `initState`.

---

## Управление состоянием

- Локальное — `setState` в `State`.
- Разделяемое реактивное — `ValueNotifier` + `ValueListenableBuilder`
  (образец `NotificationsService`).
- Значение формы — `AnyController<T>` (`utils/any_controller.dart`). Свой
  контроллер с `ValueNotifier` внутри не писать.
- Доступ к `DataProvider`: `context.watch<DataProvider>()` в `build()`,
  `GlobalState.dataProvider` в колбэках.
- Значение, которое должно пережить пересоздание экрана (фильтр раздела) —
  статик на классе `State`. Образцы: `_lastStatuses` в списке ремонтов,
  `_lastFilter` в справочнике ЗИП.

Нет: BLoC, Riverpod, GetX, `ChangeNotifier`-модели, `freezed`, кодогенерации.

---

## Модели

### **[ЖЁСТКО]** Hive-адаптеры пишутся руками

`read()` читает поля **строго в том порядке**, в котором их пишет `write()`.
Смена порядка или типа поля ломает данные на устройствах пользователей.

Единственный безопасный способ добавить поле — дописать **в конец** `write()`
и прочитать через `try/catch`:

```dart
// write: новое поле — ПОСЛЕДНИМ
writer.write(obj.normItems);

// read: обёрнуто, в старых записях поля нет
try { return reader.read().cast<T>(); } catch (_) { return const []; }
```

Образцы: `scan.dart` (поле `isOtherFault`), `repair.dart` (`normItems` +
помощник `_readTrailingList`).

**Приём работает только у объекта верхнего уровня** — того, что лежит в боксе
сам по себе. Вложенный объект пишется в **общий поток** с родителем, границы
записи у него нет: лишний `reader.read()` не упрётся в конец и не бросит
исключение, а прочитает следующее поле родителя. Дальше разъезжается вся
запись, `Hive.openBox` падает на разборе — а он разбирает **все** записи сразу,
и приложение навсегда остаётся на заставке.

Вложенные и потому закрытые для дописывания: `PeriodicTask`, `Equipment`,
`CustomRole`, `PeriodicTaskPhoto` (внутри `Task`), `RepairConsumption`,
`RepairPhoto`, `RepairNormItem` (внутри `Repair` и `PendingRepair`). Нужно
новое поле у такого — либо не сохраняй его вовсе (образец:
`PeriodicTask.isMaintenance`, приходит с сервера и восстанавливается
синхронизацией), либо клади блок одной JSON-строкой (образец:
`Task.sparePartUsage`).

Боксы-кэши открываются через `_openCacheBox` в `main.dart`: он пересоздаёт
нечитаемый бокс вместо того, чтобы уронить запуск. Очереди отправки и данные
входа — намеренно мимо него.

Занятые `typeId`: 0–4 и 6–29, следующий свободный — **30**. `typeId = 5`
освобождён, но переиспользованию не подлежит. Новый адаптер обязательно
зарегистрировать в `main.dart`.

### Остальное

- `fromJson` — фабрика с ручным приведением; ключи JSON `snake_case`, поля Dart
  `camelCase`. Вложенные объекты сервера принято раскладывать в плоские поля
  (`repair.dart`).
- `toJson()` — только у моделей, которые отправляются.
- Ключ элемента очереди — md5 содержимого: `GlobalState.digest(jsonEncode({…}))`.
  Даёт дедупликацию. Исключение — `PendingRepair.localId`: он же
  `Idempotency-Key`, считается один раз и больше не меняется.
- `==`/`hashCode` по `uuid` там, где объект кладут в `Set`.

---

## HTTP

### **[ЖЁСТКО]** шаблон метода `API`

```dart
extension EquipmentApi on API {
  Future<List<InventoryRecord>> getEquipment({limit = 10, offset = 0}) async {
    _guardOffline();                                   // 1. рубильник офлайна
    if (API.jwtToken == null) {                        // 2. авторизация
      throw Exception('Not authenticated');
    }
    final response = await _client.get(                // 3. ТОЛЬКО общий клиент
      Uri.parse('${API.baseUrl}/v1/company/equipment?limit=$limit&skip=$offset'),
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);                       // 4. обязательный таймаут

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);   // 5. кириллица
      final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    }
    throw Exception('Failed to load inventory: ${response.statusCode}');
  }
}
```

Все пять шагов обязательны. **`_client`, а не top-level `http.get/post`** —
мимо него нет ни `connectionTimeout` 3 с, ни отметки о недоступности сервера
(`data-and-integrations.md`). Таймауты: `_readTimeout` 8 с, `_uploadTimeout`
60 с (multipart), `_aliveTimeout` 5 с (`isAlive`, идёт через `_probeClient`).

**Пагинация: параметр URL называется `skip`**, хотя аргумент метода — `offset`.
Повторяющиеся параметры (`status`, `responsible_user_uuids`) собирай через
`Uri.replace(queryParameters:)`, а не интерполяцией строки.

**Фильтруй на сервере, а не на телефоне.** Если у эндпоинта есть подходящий
фильтр — передавай его. Открытые задачи качались по всей компании и отбирались
на устройстве, пока не начали слать `responsible_user_uuids`.

Используется только `package:http`. `dio` в зависимостях есть, но не
импортируется — не начинай.

### Метод синхронизации

```dart
Future<void> syncUsageUnitTypes() async {
  _isLoading = true;
  try {
    _usageUnits = await loadAllUsageUnitTypes();
    await usageUnitBox.clear();
    await usageUnitBox.addAll(_usageUnits);
  } catch (e) {
    _syncLog.warning('Failed sync usage unit types: $e');
  } finally {
    _isLoading = false;
  }
}
```

Полная замена содержимого бокса, ошибка глотается в журнал. Новый справочник —
по этому шаблону плюс вызов в `mainSync()`. **Исключение — каталог ЗИП:** он
единственный качается инкрементально, см. `data-and-integrations.md`.

Синглтон-сервис: приватный конструктор + `static final instance`.

---

## Асинхронность

- **[ЖЁСТКО]** у каждого сетевого вызова — `.timeout(...)`.
- Результат операции для UI — через `enum` (`SyncResult`), а не через bool с
  комментарием.
- **[ЛЕГАСИ]** вечный цикл `while (true) { await Future.delayed(...) }` вместо
  таймера — так сделаны фоновые циклы в `data_provider_sync.dart` и `main.dart`.
  Новые такие не заводить, брать `Timer.periodic`.

---

## Ошибки

- **[ДОМИНИРУЕТ]** `throw Exception('Failed to <что>: ${response.statusCode}')`.
- **[ДОМИНИРУЕТ в новом коде]** если бэкенд отдаёт осмысленный русский `detail`
  (ремонты, ЗИП, нормы) — доставать его и показывать пользователю. Помощники в
  `api.dart`: `_serverDetail`, `_throwServerError`; перевод для UI —
  `repairErrorMessage` (`repairs/repair_error_messages.dart`).
- **[ЖЁСТКО]** в фоновой очереди различай четыре исхода: «сервер отказал»
  (запомнить причину, не повторять), «сбой сервера или шлюза»
  (`ServerFailureException.isTransient` — 5xx, 408, 429: повторить),
  «нет связи» (повторить позже), «протух токен» (`AuthExpiredException`, 401).
  Смешивать нельзя — иначе очередь либо теряет данные, либо долбит сервер вечно.
- Кастомных исключений семь (`exceptions/app_exceptions.dart`): три про логин,
  `AuthExpiredException`, `NoConnectionException`, `ServerFailureException`
  (несёт код ответа; `toString()` печатается как прежний `Exception(текст)` —
  переводы ошибок разбирают строку, формат менять нельзя) и
  `InsufficientStockException` со списком `InsufficientStockItem`.
- Детект офлайна — **[ЖЁСТКО]** общий `isOfflineError` из
  `utils/offline_error.dart`. Своих копий не заводить: их было три, и каждая
  ошибалась по-своему.

Нет: `Result<T,E>`, `Either`, sealed-иерархий, глобального `runZonedGuarded`.

---

## Логирование

Два способа, и выбор между ними не вкусовой:

- **`package:logging`** — в фоновых слоях (`API`, `DataProvider` и его
  part-файлы, `AppLifecycleObserver`): `final _syncLog = Logger('DataProviderSync')`,
  уровень **не ниже `warning`**. В релизной сборке `main.dart` поднимает
  `Logger.root.level` до `Level.WARNING`, и всё, что тише, туда не доедет. Это
  сообщения, которые нужны при разборе жалоб «расход не списался», «осмотр
  пропал».
- **`debugPrint`** с тегом в квадратных скобках (46 вхождений) — в UI и push:
  `debugPrint('[Push] startService result: $result')`.

Голых `print` осталось 4 — не тиражировать. Крашрепортинга нет.

---

## Локализация

**[ЖЁСТКО]** язык один — русский. `flutter_localizations` **не подключён и не
может быть подключён**: пакет требует intl 0.19, а понижение с 0.20 ломает
сборку Flutter. Отсюда самописные листы выбора даты и времени
(`widgets/date_range_sheet.dart`, `_TimeWheelSheet` в форме создания ремонта) —
штатные `showDatePicker`/`showTimePicker` были бы англоязычными.

Строки фичи — отдельным классом в `lib/strings.dart`: `RepairStrings`,
`RepairCardStrings`, `ConflictStrings`, `SparePartStrings`,
`InspectionConsumptionStrings`, `ScanQueueStrings`, `UsageQueueStrings`,
`ScanConflictStrings`. Внутри `static const String` и статические методы для
подстановок. **Так же заводи строки для новых фич.**

Старый класс `Strings` (Map-геттеры, только 'ru') покрывает ~17% текста;
остальное — литералы в виджетах. Повторяющееся выноси, уникальное для экрана
можно оставить литералом.

Даты — через `intl`, `DateFormat('dd.MM.yyyy HH:mm')`. Склонения по числу
пишутся вручную (образец `_pluralizeTasks`).

**[ЖЁСТКО]** Количества (остатки ЗИП, расход, нормы, наработка) показываются
через `formatQuantity` из `utils/quantity_format.dart`: целое — без дробной
части, дробное — **через запятую**, как в веб-админке. Ввод разбирается
`parseQuantity` — запятая и точка равнозначны, потому что на клавиатуре
телефона десятичный знак зависит от раскладки. Голый `value.toString()` в
интерфейсе не писать. На сервер числа уходят обычными `double` внутри
`jsonEncode` — там разделитель всегда точка, и трогать это нельзя.

---

## Комментарии

Doc-комментарии `///` **на русском**, перед классом или нетривиальным методом,
объясняют **зачем**, а не что.

**Комментируй неочевидные обходные пути** — проект делает это системно, и
именно эти комментарии экономят больше всего времени. Уже зафиксированы:
причина запрета `tabularFigures`, причина отказа от `flutter_localizations`,
почему фото ремонта уходят по одному, почему `serverUuid` пишется до фото,
почему у экрана конфликта `Navigator.push`, а не `GoRoute`.

Внутри крупных файлов — ASCII-разделители секций.

---

## Тесты

`flutter test` **зелёный: 122 теста в 19 файлах** — и должен таким оставаться.
Только unit и только на чистую логику: симметричность Hive-адаптеров
(`repair_adapter_test`, `pending_repair_adapter_test`), разбор отказов сервера
(`scan_error_messages_test`, `repair_error_messages_test`), поведение записей
очереди при отказе, окно недоступности (`offline_window_test`), расход ЗИП
(`consumption_*`, `insufficient_stock_item_test`, `spare_part_usage_test`),
фича-флаг ППР, формат копирования ремонта.

Моков, фикстур, widget- и integration-тестов нет. Всё, что ходит через `API`,
покрыть нельзя: клиент приватный и не подменяется.

Пиши название теста **по-русски** — так написаны существующие.

---

## Что считать образцом

| Категория | Эталон |
|---|---|
| Экран-хаб / карточки | `qr/qa_actions.dart` |
| Экран-список с состояниями | `tasks/equipment_list_screen.dart` |
| Список с пагинацией | `notifications/notifications_screen.dart` |
| Список с офлайном и очередью | `repairs/repairs_list_screen.dart` |
| Карточка с режимами «сервер / черновик / есть правка» | `repairs/repair_detail_screen.dart` |
| Компонент-карточка с пилюлями | `notifications/notification_card.dart` |
| Переиспользуемый виджет | `widgets/empty_state.dart` |
| Сервис с реактивным состоянием | `notifications/notifications_service.dart` |
| Чистая логика без Flutter | `notifications/sse_line_parser.dart` |
| Метод API | `http/equipment_api.dart` |
| Метод API с `detail` и идемпотентностью | `http/repair_api.dart` |
| Метод API, собирающий данные из двух эндпоинтов | `http/ppr_api.dart` |
| Экран разбора отказа сервера | `qr/scan_conflict_screen.dart` |
| Очередь отправки | `data/data_provider_outbox.dart` |
| Модель с Hive | `model/usage_update.dart` |
| Модель с вложенными объектами и поздним полем | `model/repair.dart` |
| Строки фичи | `RepairCardStrings` в `lib/strings.dart` |
| Тема и токены | `design/app_theme.dart`, `app_constants.dart` |

**Не ориентироваться:** `update_manager.dart`, `design/theme_extensions.dart`,
`widgets/select_*_button.dart` (кроме `select_image_button`, `select_task_button`),
`widgets/button_with_select_dialog.dart`, `design/README.md`.
