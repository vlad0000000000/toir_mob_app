# Конвенции кода

Пометки силы правила: **[ЖЁСТКО]** — нарушение ломает данные или сборку.
**[ДОМИНИРУЕТ]** — так написано большинство кода. **[ЛЕГАСИ]** — не тиражировать.

> **Линтера нет.** `analysis_options.yaml:1` подключает отсутствующий
> `package:analysis_defaults/flutter.yaml`, поэтому блок `linter.rules` не
> применяется. Единственный ориентир — форма соседнего кода.
> `flutter analyze` даёт ровно 1 предупреждение — это эталон.

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
    final response = await http.get(
      Uri.parse('${API.baseUrl}/v1/company/equipment?limit=$limit&skip=$offset'),
      headers: {'Authorization': 'Bearer ${API.jwtToken}'},
    ).timeout(API._readTimeout);                       // 3. обязательный таймаут

    if (response.statusCode == 200 || response.statusCode == 201) {
      const utf8Decoder = Utf8Decoder(allowMalformed: true);   // 4. кириллица
      final data = jsonDecode(utf8Decoder.convert(response.bodyBytes));
      return data.map((json) => InventoryRecord.fromJson(json)).toList();
    }
    throw Exception('Failed to load inventory: ${response.statusCode}');
  }
}
```

Все четыре шага обязательны. Таймауты: `_readTimeout` 15 с, `_uploadTimeout`
60 с (multipart), `_aliveTimeout` 5 с (`isAlive`).

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
    print('Failed sync usage unit types: $e');
  } finally {
    _isLoading = false;
  }
}
```

Полная замена содержимого бокса, ошибка глотается. Новый справочник — по этому
шаблону плюс вызов в `mainSync()`. **Исключение — каталог ЗИП:** он большой и
в `mainSync` намеренно не входит, см. `data-and-integrations.md`.

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
- **[ЖЁСТКО]** в фоновой очереди различай три исхода: «сервер отказал»
  (запомнить причину, не повторять), «нет связи» (повторить позже),
  «протух токен» (`AuthExpiredException`, 401). Смешивать нельзя — иначе
  очередь либо теряет данные, либо долбит сервер вечно.
- Кастомных исключений четыре: три про логин и `AuthExpiredException`
  (`exceptions/app_exceptions.dart`).
- Детект офлайна строками — **[ЛЕГАСИ, но повторяемо]**: копируй форму
  `_isOfflineError` из `qr_result_screen.dart`, не пиши пятый вариант.

Нет: `Result<T,E>`, `Either`, sealed-иерархий, глобального `runZonedGuarded`.

---

## Логирование

`debugPrint` с тегом в квадратных скобках — **так пишет свежий код**:
`debugPrint('[Push] startService result: $result')`. В старых файлах есть
`print` (19 шт.) и `package:logging` (1 шт.) — не тиражировать.

Крашрепортинга нет.

---

## Локализация

**[ЖЁСТКО]** язык один — русский. `flutter_localizations` **не подключён и не
может быть подключён**: пакет требует intl 0.19, а понижение с 0.20 ломает
сборку Flutter. Отсюда самописные листы выбора даты и времени
(`widgets/date_range_sheet.dart`, `_TimeWheelSheet` в форме создания ремонта) —
штатные `showDatePicker`/`showTimePicker` были бы англоязычными.

Строки фичи — отдельным классом в `lib/strings.dart`: `RepairStrings`,
`RepairCardStrings`, `ConflictStrings`, `SparePartStrings`. Внутри
`static const String` и статические методы для подстановок. **Так же заводи
строки для новых фич.**

Старый класс `Strings` (Map-геттеры, только 'ru') покрывает ~17% текста;
остальное — литералы в виджетах. Повторяющееся выноси, уникальное для экрана
можно оставить литералом.

Даты — через `intl`, `DateFormat('dd.MM.yyyy HH:mm')`. Склонения по числу
пишутся вручную (образец `_pluralizeTasks`).

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

Их нет, `flutter test` красный из-за пустого шаблонного файла. Инфраструктуры
моков и фикстур не существует. Не отчитывайся об «успешном прогоне тестов».

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
| Очередь отправки | `data/data_provider_outbox.dart` |
| Модель с Hive | `model/usage_update.dart` |
| Модель с вложенными объектами и поздним полем | `model/repair.dart` |
| Строки фичи | `RepairCardStrings` в `lib/strings.dart` |
| Тема и токены | `design/app_theme.dart`, `app_constants.dart` |

**Не ориентироваться:** `update_manager.dart`, `design/theme_extensions.dart`,
`widgets/select_*_button.dart` (кроме `select_image_button`, `select_task_button`),
`widgets/button_with_select_dialog.dart`, `design/README.md`.
