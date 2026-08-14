# Дизайн-система и UX

## Принципы

Сформулированы в doc-комментарии `design/app_theme.dart` и подтверждены кодом:

- **Глубина через tonal elevation, а не тени.** Ступени `surfaceContainerLow →
  Highest`. Карточки — `elevation: 0` + обводка `outlineVariant` 0.5px. Тени
  только у модалок.
- **Крупные тап-таргеты** — ≥48px, 52–56px для главного CTA. Работа в перчатках.
- **Светлая тема всегда**, портрет, русский язык.
- **Никаких `tabularFigures` глобально** — на Samsung One UI / Xiaomi MIUI
  ломает рендер кириллицы. Нужны моноширинные цифры — применяй локально через
  `copyWith(fontFeatures: ...)`.
- Всё компонуется в один вертикальный скролл со «липкой» нижней панелью.

---

## Токены — `design/app_constants.dart`

Единственный источник числовых констант. **Используй их, а не литералы.**

| Группа | Значения |
|---|---|
| Отступы | `spacingXS 4`, `SM 8`, `MD 16`, `LG 24`, `XL 32`, `XXL 48` |
| Радиусы | `radiusXS 4`, `SM 8`, `MD 12`, `LG 16`, `XL 24`, `Full 9999` |
| Размеры | `buttonHeight 48`, `buttonHeightLarge 56`, `appBarHeight 56` |
| Кегли | `fontSizeDisplayLarge 57` … `fontSizeLabelSmall 11` (шкала M3) |

Реально в ходу `spacing*` и `radius*` (~230 обращений). `elevationLevel*`,
`duration*`, `curve*`, `breakpoint*` почти не используются — длительности
задаются литералами. Помощники `getResponsivePadding`, `isMobile/isTablet` не
вызываются нигде: приложение только под телефон в портрете.

---

## Тема — `design/app_theme.dart`

Две палитры, переключатель в настройках: `fresh` (дефолт) и `industrial`.
Выбор хранится в `Settings.themeId`, `MaterialApp` перестраивается через
`ValueListenableBuilder` на `AppTheme.activeThemeId`.

### `fresh` — светлая, по умолчанию

| Роль | Значение |
|---|---|
| `primary` / `onPrimary` | `#71B738` / `#FFFFFF` |
| `primaryContainer` / `onPrimaryContainer` | `#E8F4E1` / `#55892A` |
| `secondary` | `#55892A` |
| `tertiary` (= success) | `#71B738` |
| `error` / `onError` | `#E23636` / `#FFFFFF` |
| `errorContainer` / `onErrorContainer` | `#FADBDB` / `#701010` |
| `surface` / `onSurface` | `#FAF8F5` (тёплый cream) / `#2E2E2E` |
| `onSurfaceVariant` | `#737373` |
| `surfaceContainerLowest…Highest` | `#FFFFFF`, `#F5F2EE`, `#EFEBE6`, `#E7E1DA`, `#DCD6CE` |
| `outline` / `outlineVariant` | `#B8B8B8` / `#E0E0E0` |
| `inverseSurface` / `onInverseSurface` | `#2E2E2E` / `#FAF8F5` |

`industrial` — графит `#1A2332` + cyan `#0891B2`, прежняя схема, оставлена как
опция.

**Тёмные схемы написаны, но не подключены** (`themeMode: ThemeMode.light`).
Не проверяй новые экраны в тёмной теме, но и не ломай схемы.

### Семантические цвета — `extension AppSemanticColors on ColorScheme`

Единственный правильный способ получить статусный цвет. Требует
`import '../design/app_theme.dart'`:

```dart
cs.success / onSuccess / successContainer     // = tertiary
cs.warning          // #EA580C, жёстко задан
cs.warningContainer // #FEDD9C
cs.info             // = secondary
cs.priorityHigh / priorityMedium / priorityLow
```

---

## Типографика

| Стиль | Кегль/вес | Где |
|---|---|---|
| `headlineSmall` | 24 w600 | заголовок диалога, «Вход в систему» |
| `titleLarge` | 22 w600 | AppBar (w700), заголовок `EmptyState` |
| `titleMedium` | 16 w600 | название карточки |
| `bodyLarge` | 16 w400 | основной текст |
| `bodyMedium` | 14 w400 | описание, подсказка |
| `bodySmall` | 12 w400 | вторичный текст |
| `labelLarge` | 14 w600 | текст кнопок |
| `labelMedium` | 12 w600 | бейджи |
| `labelSmall` | 11 w600 | пилюли, отладочная полоса |

Шрифт системный. **Бери стиль из `tt.*` и модифицируй `copyWith`**, не собирай
`TextStyle` с нуля.

---

## Под-темы настроены — локально не переопределяй

`AppTheme._build` настраивает ~24 под-темы. На практике:

| Компонент | Уже из темы |
|---|---|
| `ElevatedButton` | фон `primary`, высота ≥48, радиус 12, `elevation: 0` |
| `Card` | `surfaceContainerLow`, радиус 16, обводка 0.5, без тени |
| `TextField` | `filled`, радиус 12, фокус `primary` 2px |
| `AppBar` | `surface`, `elevation: 0`, нижняя граница `outlineVariant` |
| `SnackBar` | `inverseSurface`, floating, радиус 12 |
| `Dialog` | `surfaceContainerHigh`, радиус 24 |
| `BottomSheet` | `surface`, верхний радиус 28, drag-handle |

`_buttonTextStyle` намеренно **без `color`** — иначе он перебивал бы
`foregroundColor`. Не добавляй.

---

## Переиспользуемые компоненты

| Компонент | Файл | Когда |
|---|---|---|
| `EmptyState` | `widgets/empty_state.dart` | Любой пустой список |
| `showAppModalSheet<T>` | `widgets/app_bottom_sheet.dart` | Модальный лист на 90% высоты |
| `Modal` | `widgets/modal.dart` | Каркас листа |
| `Dialogs.notify / notifyMD / areYouSure` | `utils/dialogs.dart` | Информирование и подтверждение |
| `OfflineBanner` | `widgets/offline_banner.dart` | Полоса «нет связи» над содержимым |
| `SparePartRow` | `widgets/spare_part_row.dart` | Строка позиции ЗИП |
| `showSingleDateSheet`, `showDateRangeSheet` | `widgets/date_range_sheet.dart` | Выбор даты. **Вместо `showDatePicker`** — штатный без `flutter_localizations` англоязычный |
| `RepairStatusPill`, `RepairFreePill` | `repairs/repair_status_pill.dart` | Пилюли статуса ремонта |
| `HelpLink`, `SquareButton`, `SelectImageButton` | `widgets/` | |
| `ControllerListenerMixin` | `widgets/controller_listener_mixin.dart` | Подписка на контроллер |
| `showSnackBar(String)` | `style/snack_bar.dart` | Снекбар без `BuildContext` |
| `MyAppBar.build(context)` | `app_bar/app_bar.dart` | AppBar экрана — не создавай свой, добавь ветку. Исключение: заголовок зависит от данных |

**Мертво, не переиспользовать:** `design/theme_extensions.dart`,
`select_priority_button`, `select_problem_button`, `select_state_button`,
`select_usage_button`, `button_with_select_dialog`, `scanned_barcode_label`,
`dependent_multi`, `self_cancel_timer`.

---

## Ключевые паттерны

**Карточка списка** — `Card` + `InkWell` + `Padding(spacingMD)`, внутри `Row`:
иконка 48×48 в скруглённом квадрате, текст, справа badge-счётчик или chevron.
Эталон — `_EquipmentTile`.

**Пилюля-статус** — заливка `цвет.withValues(alpha: 0.12)`, текст и иконка тем
же цветом на полной непрозрачности, радиус `radiusSM`, внутри точка 5×5 или
иконка 11px. Эталон — `_StatusPill` в `notification_card.dart`.

**Badge-счётчик** — `radiusFull`, фон `primary` (или `error` для тревоги),
`labelMedium` w700, переполнение `count > 99 ? '99+'`.

**Липкая нижняя панель** — `Scaffold.bottomNavigationBar`: `SafeArea` →
`Container(color: surface, border: top outlineVariant 0.5, padding 16/12)` →
кнопка 56px на всю ширину. Эталон — `_SubmitBar`.

**Кнопки подтверждения в диалоге — друг под другом, на всю ширину.** В ряд
каждой достаётся половина, и длинная подпись переносится на вторую строку,
которую срезает фиксированная высота.

**Секционный заголовок** — `labelSmall`, `letterSpacing: 0.6`, w600,
`onSurfaceVariant`, текст **прописными**.

**Список выбора в нижнем листе** — `showModalBottomSheet` с `showDragHandle`,
заголовок прописными, `ListTile` с точкой слева и галочкой у выбранного.

---

## Состояния экрана

| Состояние | Как выглядит |
|---|---|
| Первичная загрузка | `CircularProgressIndicator`; на списках крупный (`strokeWidth: 8`, 128×128) |
| Загрузка в кнопке | Кнопка не исчезает: внутрь `SizedBox(22, CircularProgressIndicator(strokeWidth: 2.5))` |
| Фоновое обновление | `LinearProgressIndicator(minHeight: 2)` над списком — список остаётся рабочим |
| Пусто | `EmptyState`. Внутри `RefreshIndicator` оборачивай в `ListView` с `AlwaysScrollableScrollPhysics` |
| Ошибка экрана | Круг 96×96 `errorContainer` + иконка 48 `error` + заголовок + кнопка восстановления |
| Ошибка действия | `Dialogs.notify` или снекбар |
| Ошибка поля | Флаг подсветки в `State` → `errorText` |
| Успех | Снекбар `cs.success` + `check_circle_rounded` |
| Нет связи | `OfflineBanner` над содержимым; кэш остаётся рабочим |
| Не отправлено | Пилюля «Не отправлено», у черновика — пунктирная обводка |
| Отправка отклонена | Причина по-русски на карточке, автоповтора нет |

**Правило первичной загрузки:** заводи флаг «хоть раз загрузили»
(`hasLoadedOnce`) и показывай спиннер, а не `EmptyState`, пока он `false` —
иначе на холодном старте мигает «ничего нет».

**Правило кэша:** если данные есть локально — рисуй их сразу, а сеть пусть
обновляет уже показанное. Не держи экран на спиннере до ответа сервера.

---

## Формы

- Валидация — **флаги подсветки в `State`**, а не `Form.validate()` (на логине
  `validator` объявлены, но не вызываются).
- Числовая валидация — метод модели, возвращающий `String?`.
- Многострочное поле: `minLines: 3, maxLines: 6, alignLabelWithHint: true`.
- `windowSoftInputMode="adjustResize"` — формы всегда в `SingleChildScrollView`.

---

## Иконки, изображения, анимация

Material Icons, вариант `_rounded` (доминирует) или `_outlined` (для
неактивного состояния). Размеры: 24 по умолчанию, 48 в `EmptyState`, 18–22 в
строках, 11–12 в пилюлях.

Фото оборудования — `Image.network` с обязательным `errorBuilder`. Фото
осмотра — base64 в памяти. Лайтбокс — `Dialog(transparent)` + `InteractiveViewer`.

**Анимации переходов между экранами нет** — все маршруты отдают
`NoTransitionPage`. Из анимаций осталось раскрытие секции «Сервис»
(`AnimatedSize` 200 мс) и диалоги `awesome_dialog`. Кастомных
`AnimationController` нет. **Хаптики отсутствуют полностью.**

---

## Доступность

Слабое место: `Semantics` и `semanticLabel` — 0 вхождений, `tooltip:` — 5.
Масштабирование системного шрифта специально не поддержано. При добавлении
иконочных кнопок **ставь `tooltip:`** — это текущий минимум проекта.

---

## Отладочная полоса статуса

Постоянный элемент внизу **каждого** экрана: полоса на `cs.inverseSurface`,
моноширинный `labelSmall`, обновляется раз в 15 секунд:

```
Сервер: доступен  |  Осмотров не отправлено: 0  |  Пользователь: 123
```

Это **часть продукта**, а не временная отладка — по ней обходчик и поддержка
понимают, есть ли связь и всё ли отправлено. Не убирай.

---

## Эталонные экраны

| Тип задачи | Ориентир |
|---|---|
| Плитка/действие на главной | `qr/qa_actions.dart` |
| Список сущностей | `tasks/equipment_list_screen.dart` |
| Список с пагинацией и pull-to-refresh | `notifications/notifications_screen.dart` |
| Список с офлайном и очередью | `repairs/repairs_list_screen.dart` |
| Карточка сущности с метаданными | `notifications/notification_card.dart` |
| Карточка с режимами «сервер / черновик / правка» | `repairs/repair_detail_screen.dart` |
| Экран-форма с липким CTA | `qr/qr_result_screen.dart` + `result_controls.dart` |
| Ввод числа крупными кнопками | `_QuantityStepper` в `repairs/repair_detail_screen.dart` |
| Диалог необратимого действия | `_SubmitConfirmDialog` там же |
| Модальный тупик / разрешение конфликта | `repairs/repair_conflict_screen.dart` |
| Фильтр-лист с чипами | `spare_parts/spare_parts_screen.dart` (рабочий) |
| Экран с внешним контентом и ошибкой | `knowledge_base/knowledge_base_screen.dart` |

---

`design/README.md` — боилерплейт генератора тем, описывает структуру, которой в
проекте нет. **Игнорировать.**
