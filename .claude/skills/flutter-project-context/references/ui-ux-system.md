# Дизайн-система и UX

## Принципы, выведенные из кода

Сформулированы в doc-комментарии `lib/src/design/app_theme.dart:15-27` и
подтверждены реализацией:

- **Глубина через tonal elevation, а не тени.** Ступени
  `surfaceContainerLow → Highest`. Тени остались только у модалок
  (`Modal`, `blurRadius: 16`) и FAB. Карточки — `elevation: 0` +
  обводка `outlineVariant` 0.5px.
- **Крупные тап-таргеты.** ≥48px для кнопок (`minimumSize: Size(0, 48)` во всех
  темах кнопок), 52–56px для главного CTA. Причина — работа в перчатках.
- **Высокий контраст**, светлая тема всегда.
- **Единая шкала радиусов** 4/8/12/16/24 + 28 для нижних листов.
- **Никаких `tabularFigures` глобально** — на Samsung One UI / Xiaomi MIUI ломает
  рендер кириллицы (подробный комментарий: `app_theme.dart:358-368`). Нужны
  моноширинные цифры — применяй локально через `copyWith(fontFeatures: ...)`.
- **Русские тексты, портрет, одна рука.** Всё компонуется в один вертикальный
  скролл со «липкой» нижней панелью для главного действия.

---

## Токены — `lib/src/design/app_constants.dart`

Единственный источник числовых констант. **Используй их, а не литералы.**

| Группа | Константы |
|---|---|
| Отступы | `spacingXS 4`, `spacingSM 8`, `spacingMD 16`, `spacingLG 24`, `spacingXL 32`, `spacingXXL 48` |
| Радиусы | `radiusXS 4`, `radiusSM 8`, `radiusMD 12`, `radiusLG 16`, `radiusXL 24`, `radiusFull 9999` |
| Толщина границ | `borderWidthThin 1`, `borderWidthMedium 2`, `borderWidthThick 4` |
| Elevation | `elevationLevel0 0` … `elevationLevel5 12` |
| Длительности | `durationFast 150ms`, `durationNormal 300ms`, `durationSlow 500ms` |
| Кривые | `curveDefault easeInOut`, `curveEmphasized`, `curveBounce`, `curveLinear` |
| Размеры | `buttonHeight 48`, `buttonHeightLarge 56`, `buttonHeightSmall 40`, `textFieldHeight 56`, `appBarHeight 56`, `avatarSize 40` |
| Брейкпоинты | `breakpointMobile 600`, `breakpointTablet 900`, `breakpointDesktop 1200` |
| Кегли | `fontSizeDisplayLarge 57` … `fontSizeLabelSmall 11` (шкала M3) |

**Что из этого реально в ходу:** `spacing*` и `radius*` — 230 обращений
к `AppConstants.*` по всему `lib/`. `elevationLevel*`, `duration*`, `curve*`,
`buttonHeight*`, `breakpoint*` — почти не используются: анимации задаются
литералами (`Duration(milliseconds: 180)` в `_ServiceSection`,
`200` в `AnimatedSize`), высоты кнопок — числами
(`52`, `56`, `48`).

**Помощники `AppConstants.getResponsivePadding`, `isMobile/isTablet/isDesktop`,
`getTextSizeMultiplier` не вызываются нигде.** Приложение только под телефон
в портрете.

---

## Тема — `lib/src/design/app_theme.dart`

### Две палитры, переключатель в настройках

```dart
enum AppThemeId { fresh, industrial }
static const AppThemeId defaultThemeId = AppThemeId.fresh;
static final ValueNotifier<AppThemeId> activeThemeId = ValueNotifier(defaultThemeId);
```
`main.dart:410` слушает `activeThemeId` через `ValueListenableBuilder` и
перестраивает `MaterialApp`. Выбор сохраняется в `Settings.themeId` (Hive) и
восстанавливается в `main()` (`main.dart:164`). UI переключателя —
`SegmentedButton<AppThemeId>` в `_SettingsSheet` (`qa_actions.dart:698-714`),
подписи «Свежая» / «Графит».

### `fresh` — дефолт, светлая (`app_theme.dart:90-138`)

| Роль | Значение | Комментарий |
|---|---|---|
| `primary` / `onPrimary` | `#71B738` / `#FFFFFF` | лаймовый зелёный из веб-админки |
| `primaryContainer` / `onPrimaryContainer` | `#E8F4E1` / `#55892A` | |
| `secondary` | `#55892A` | тот же зелёный, темнее |
| `tertiary` (= success) | `#71B738` | в админке status-success = primary |
| `error` / `onError` | `#E23636` / `#FFFFFF` | |
| `errorContainer` / `onErrorContainer` | `#FADBDB` / `#701010` | |
| `surface` / `onSurface` | `#FAF8F5` / `#2E2E2E` | тёплый cream — фон экрана |
| `onSurfaceVariant` | `#737373` | вторичный текст |
| `surfaceContainerLowest` … `Highest` | `#FFFFFF`, `#F5F2EE`, `#EFEBE6`, `#E7E1DA`, `#DCD6CE` | ступени глубины |
| `outline` / `outlineVariant` | `#B8B8B8` / `#E0E0E0` | |
| `inverseSurface` / `onInverseSurface` | `#2E2E2E` / `#FAF8F5` | тёмные полосы: статус-бар, сканер, снекбар |
| `inversePrimary` | `#AEDB8A` | акцент на тёмном |

### `industrial` — альтернатива (`app_theme.dart:191-240`)

Графит `#1A2332` primary + cyan `#0891B2` secondary + emerald `#047857` tertiary,
поверхности `#FAFAF9`. Прежняя схема, оставлена как опция.

### Тёмные схемы

`_freshDarkScheme()` и `_industrialDarkScheme()` **написаны полностью**, но
**не подключены**: `MaterialApp` получает только `theme: AppTheme.lightTheme` и
`themeMode: ThemeMode.light` (`main.dart:415-416`). Dark mode фактически
отсутствует. Не проверяй новые экраны в тёмной теме — но и не ломай схемы.

### Семантические цвета — `extension AppSemanticColors on ColorScheme`

`app_theme.dart:871-894`. Единственный правильный способ получить статусный цвет:

```dart
cs.success / cs.onSuccess / cs.successContainer / cs.onSuccessContainer   // = tertiary
cs.warning        // #EA580C   (жёстко задан, не из схемы)
cs.warningContainer // #FEDD9C
cs.info           // = secondary
cs.priorityHigh   // = error
cs.priorityMedium // #EA580C
cs.priorityLow    // = tertiary
```
Требует `import '../design/app_theme.dart';`. Используется в
`notification_formatters.dart`, `notification_card.dart`, `qr_result_screen.dart`.

---

## Типографика

Полная `TextTheme` собрана в `AppTheme._textTheme` (`app_theme.dart:370-487`) из
кеглей `AppConstants`. Веса и межстрочные интервалы:

| Стиль | Кегль | Вес | height | Где применяется |
|---|---|---|---|---|
| `headlineMedium` | 28 | w700 | 1.22 | заголовок онбординга |
| `headlineSmall` | 24 | w600 | 1.28 | «Вход в систему», заголовок диалога |
| `titleLarge` | 22 | w600 | 1.27 | заголовок AppBar (переопределён на w700), заголовок `EmptyState` |
| `titleMedium` | 16 | w600 | 1.5 | название карточки, заголовок уведомления |
| `titleSmall` | 14 | w600 | 1.43 | подзаголовок секции («Сервис») |
| `bodyLarge` | 16 | w400 | 1.5 | основной текст, `ListTile.title` |
| `bodyMedium` | 14 | w400 | 1.43 | описание, подсказка |
| `bodySmall` | 12 | w400 | 1.33 | вторичный текст (цвет `onSurfaceVariant` по умолчанию) |
| `labelLarge` | 14 | w600 | 1.43 | текст кнопок, `HelpLink` |
| `labelMedium` | 12 | w600 | 1.33 | бейджи, значения chip |
| `labelSmall` | 11 | w600 | 1.45 | пилюли, отладочная полоса, тип уведомления |

Кастомных шрифтов нет — системный. `fontFamily: 'monospace'` встречается один раз,
в отладочной полосе (`main.dart:456`).

**Правило:** бери стиль из `tt.*` и модифицируй `copyWith(color:, fontWeight:)`.
Не собирай `TextStyle` с нуля.

---

## Готовые под-темы (уже настроены, не переопределяй локально)

`AppTheme._build` (`app_theme.dart:299-356`) настраивает: `appBarTheme`,
`elevatedButtonTheme`, `filledButtonTheme`, `outlinedButtonTheme`,
`textButtonTheme`, `iconButtonTheme`, `floatingActionButtonTheme`, `cardTheme`,
`dialogTheme`, `bottomSheetTheme`, `popupMenuTheme`, `navigationBarTheme`,
`bottomNavigationBarTheme`, `inputDecorationTheme`, `listTileTheme`, `chipTheme`,
`switchTheme`, `checkboxTheme`, `radioTheme`, `sliderTheme`, `dividerTheme`,
`tabBarTheme`, `snackBarTheme`, `progressIndicatorTheme`, `tooltipTheme`.

Что это значит на практике:

| Компонент | Уже из темы | Не нужно указывать |
|---|---|---|
| `ElevatedButton` | фон `primary`, текст `onPrimary`, высота ≥48, радиус 12, `elevation: 0` | цвет, радиус, стиль текста |
| `Card` | фон `surfaceContainerLow`, радиус 16, обводка `outlineVariant` 0.5, `margin: zero`, без тени | `color`, `shape`, `elevation` |
| `TextField` / `TextFormField` | `filled`, фон `surfaceContainerLow`, радиус 12, фокус `primary` 2px, ошибка `error` | `border`, `fillColor`, `contentPadding` — коммит `ba04ef2 ui: drop redundant TextField decoration overrides` их специально убрал |
| `AppBar` | фон `surface`, `elevation: 0`, нижняя граница `outlineVariant` 0.5, заголовок `titleLarge` w700 | фон, тень |
| `SnackBar` | `inverseSurface`, floating, радиус 12, отступ 16 | |
| `Chip` | `surfaceContainerLow`, радиус **8** (утилитарный, не pill), обводка | |
| `Dialog` | `surfaceContainerHigh`, радиус 24 | |
| `BottomSheet` | `surface`, верхний радиус 28, `showDragHandle: true` | |

Замеченное расхождение: `_buttonTextStyle` (`app_theme.dart:514-519`) намеренно
**без `color`** — иначе он перебивал бы `foregroundColor` и текст на тёмной
кнопке оставался тёмным. Не добавляй туда цвет.

---

## Переиспользуемые компоненты

Это то, что **надо переиспользовать вместо ручной сборки**.

| Компонент | Файл | Когда |
|---|---|---|
| `EmptyState` | `widgets/empty_state.dart` | Любой пустой список. Круг 96×96 `surfaceContainerHigh` + иконка 48 `onSurfaceVariant` + `titleLarge` + `bodyMedium` серым + опциональный `action` |
| `showAppModalSheet<T>(context, child:)` | `widgets/app_bottom_sheet.dart` | Модальный лист на 90% высоты в рамке `Modal`. 4 потребителя |
| `Modal` | `widgets/modal.dart` | Каркас листа: высота 90%, отступ 16, радиус 24, drag-handle 32×4, кнопка закрытия справа |
| `Dialogs.notify(ctx, title, desc)` | `utils/dialogs.dart` | Информационное окно с кнопкой «Понятно» |
| `Dialogs.notifyMD(ctx, title, desc, md)` | `utils/dialogs.dart` | То же, но тело — markdown |
| `Dialogs.areYouSure(ctx, onOk:)` | `utils/dialogs.dart` | Подтверждение «Да/Нет» |
| `HelpLink` | `widgets/help_link.dart` | Ссылка «Помощь» → `/knowledge_base` (SVG + текст `primary`) |
| `SquareButton` | `widgets/square_button.dart` | `ElevatedButton` с радиусом 8 и вертикальным паддингом 16 |
| `SelectImageButton` | `widgets/select_image_button.dart` | Кнопка «сделать фото» → base64 в контроллер |
| `SelectTaskButton.showModal(...)` | `widgets/select_task_button.dart` | Модалка выбора задачи по оборудованию |
| `ControllerListenerMixin` | `widgets/controller_listener_mixin.dart` | Подписка на один `Listenable` контроллера |
| `showSnackBar(String)` | `style/snack_bar.dart` | Снекбар без `BuildContext` (через `scaffoldMessengerKey`) |
| `MyAppBar.build(context)` | `app_bar/app_bar.dart` | AppBar экрана — **не создавай свой `AppBar`**, добавь ветку сюда. Исключение: заголовок зависит от данных (карточки ремонта и ЗИП строят свой) |
| `OfflineBanner` | `widgets/offline_banner.dart` | Полоса «нет связи» над содержимым экрана. Сама следит за доступностью сервера |
| `SparePartRow` | `widgets/spare_part_row.dart` | Строка позиции ЗИП: значок, название, артикул, остаток. Используется в справочнике и в пикере |
| `showSingleDateSheet(...)`, `showDateRangeSheet(...)` | `widgets/date_range_sheet.dart` | Выбор даты и диапазона дат. **Вместо `showDatePicker`** — штатный без `flutter_localizations` англоязычный |
| `RepairStatusPill`, `RepairFreePill` | `repairs/repair_status_pill.dart` | Пилюля статуса ремонта и метка свободного ролевого ремонта |

**Не переиспользовать (мертво):** `theme_extensions.dart` (`context.gapMD`,
`context.paddingLG`), `select_priority_button`, `select_problem_button`,
`select_state_button`, `select_usage_button`, `button_with_select_dialog`,
`scanned_barcode_label`, `dependent_multi`, `self_cancel_timer`.

---

## Однократные (one-off) реализации — образцы, но не библиотека

Живут внутри своих экранов как приватные виджеты. Копируй форму, но не пытайся
импортировать:

| Виджет | Файл | Паттерн |
|---|---|---|
| `_PrimaryActionCard` | `qr/qa_actions.dart:195` | Hero-CTA на `primary` |
| `_SecondaryActionCard`, `_IconCircle` | `qr/qa_actions.dart:268,336` | Плитка действия, иконка 44×44 на `secondaryContainer` радиус 12 |
| `_NotificationsCard` | `qr/qa_actions.dart:359` | Плитка со счётчиком-badge на `cs.error` |
| `_ServiceSection`, `_ServiceTile` | `qr/qa_actions.dart:477,565` | Сворачиваемая секция + строки с `destructive`-вариантом |
| `_EquipmentTile` | `tasks/equipment_list_screen.dart:139` | Карточка списка: иконка 48 + текст + badge/chevron |
| `_HeroPassport`, `_Thumb`, `_StateChip` | `qr/qr_result_screen.dart:486,635,675` | Паспорт оборудования, превью 64px с лайтбоксом, chip-селектор состояния |
| `_SubmitBar` | `qr/qr_result_screen.dart:807` | **Липкая нижняя панель** — эталон |
| `_SectionLabel`, `_CountChip`, `_ActionCard`, `_ActionRow` | `qr/result_controls.dart:373,403,426,458` | Секционная форма |
| `_PhotoStrip`, `_PhotoSlot` | `qr/result_controls.dart:828,983` | Полоса из 3 фото-слотов равной высоты |
| `_UsageList`, `_UsageRow` | `qr/result_controls.dart:558,674` | Список счётчиков наработки |
| `_StatusPill`, `_PriorityPill`, `_DeadlinePill` | `notifications/notification_card.dart:190,226,272` | **Пилюли** — эталон |
| `_HeaderRow` | `notifications/notifications_screen.dart:522` | Шапка списка с счётчиком и переключателем |
| `_PillChip`, `_MultiChoiceChips`, `_SingleChoiceChips`, `_DateRangeSelector` | `tasks/tasks_filter_sheet.dart:368,302,338,422` | Фильтр (экран выключен, но код — образец) |
| `_RepairTile`, `_DraftTile`, `_DashedBorderPainter` | `repairs/repairs_list_screen.dart:375,605,772` | Карточка списка + карточка неотправленного черновика (пунктирная обводка своим `CustomPainter`) |
| `_FilterChip`, `_GroupLabel` | `repairs/repairs_list_screen.dart:833,810` | Чипы фильтра статусов и заголовок группы в списке |
| `_QuantityStepper`, `_StepperButton`, `_QuantityInputFormatter` | `repairs/repair_detail_screen.dart:1803,2097,1989` | **Крупный счётчик количества** — образец ввода числа под перчатки |
| `_ConsumptionSection`, `_ConsumptionRow` | `repairs/repair_detail_screen.dart:1508,1679` | Секция фактического расхода с нормой и подсветкой отклонений |
| `_PhotoStrip`, `_PhotoSlot`, `_AddPhotoSlot` | `repairs/repair_detail_screen.dart:1228,1384,1469` | Сетка фото с добавлением и удалением (вариант полосы из `result_controls.dart`) |
| `_SubmitConfirmDialog`, `_SummaryTile` | `repairs/repair_detail_screen.dart:2128,2297` | Диалог подтверждения со сводкой — образец «объясни последствия перед необратимым» |
| `_Banner` | `repairs/repair_detail_screen.dart:2405` | Плашка состояния над содержимым карточки |
| `_StockPill`, `_StockBlock`, `_MovementRow`, `_DayHeader` | `spare_parts/spare_part_detail_screen.dart:581,627,934,888` | Остаток и лента истории движения, сгруппированная по дням |
| `_SegmentedToggle`, `_ChipGroup`, `_MoreChip` | `spare_parts/spare_parts_screen.dart:619,705,759` | Фильтр справочника — рабочий (в отличие от выключенного фильтра задач) |

---

## Ключевые UI-паттерны

### Карточка списка

```dart
Card(                                   // тема даёт фон/радиус/обводку
  child: InkWell(
    borderRadius: BorderRadius.circular(AppConstants.radiusLG),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      child: Row(children: [ иконка 48×48, текст, badge или chevron ]),
    ),
  ),
)
```
Эталон — `_EquipmentTile`. Вариант без `Card`: `Material(color:, shape:
RoundedRectangleBorder(side: BorderSide(color: cs.outlineVariant, width: 0.5),
borderRadius: circular(radiusLG)), clipBehavior: Clip.antiAlias)` +
`InkWell` — так сделаны плитки хаба и `NotificationCard`.

### Пилюля-статус

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(AppConstants.radiusSM),
  ),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    точка 5×5 или Icon size 11, SizedBox(width: 4-5),
    Text(label, style: tt.labelSmall?.copyWith(color: color, fontWeight: w600)),
  ]),
)
```
Эталон — `_StatusPill`/`_PriorityPill`/`_DeadlinePill`. **Заливка всегда
`цвет.withValues(alpha: 0.12)`, текст и иконка — тот же цвет на полной
непрозрачности.**

`_StateChip` (`qr_result_screen.dart:760-801`) — интерактивный вариант пилюли:
радиус 20 (pill), фон `primaryContainer` при заполненном значении и
`surfaceContainerHigh` при пустом, точка 8×8 + текст + `expand_more_rounded`.

### Badge-счётчик

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
  decoration: BoxDecoration(color: cs.primary,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
  child: Text('$count', style: tt.labelMedium?.copyWith(
      color: cs.onPrimary, fontWeight: FontWeight.w700)),
)
```
На плитке уведомлений — тот же приём, но `cs.error`, обводка `cs.surface` 2px,
позиционирование `Positioned(right: -4, top: -4)` в `Stack(clipBehavior: Clip.none)`,
переполнение `count > 99 ? '99+' : '$count'` (`qa_actions.dart:404-432`).

### Липкая нижняя панель

`Scaffold.bottomNavigationBar` = `SafeArea` → `Container` с
`color: cs.surface`, `border: Border(top: BorderSide(color: cs.outlineVariant,
width: 0.5))`, паддинг 16/12, внутри `SizedBox(height: 56, width: double.infinity)`
+ `ElevatedButton.icon`. Эталон — `_SubmitBar`.

### Секционный заголовок формы

`_SectionLabel` — `labelSmall`, `letterSpacing: 0.6`, `fontWeight: w600`,
цвет `onSurfaceVariant`, текст **прописными**. Тот же приём в
`_StateChip._pick` («СОСТОЯНИЕ ОБОРУДОВАНИЯ»), `_pickProblem`
(«ВЫБЕРИТЕ ПРОБЛЕМУ»), `NotificationCard` (тип уведомления `.toUpperCase()`).

### Список выбора в нижнем листе

```dart
showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,       // если содержимое высокое
  builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
    Padding(child: Text('ЗАГОЛОВОК ПРОПИСНЫМИ', style: labelSmall …)),
    ListTile(leading: Icon(Icons.circle, size: 12, color: cs.primary),
             title: Text(...),
             trailing: selected ? Icon(Icons.check_rounded, color: cs.primary) : null,
             onTap: () => Navigator.of(ctx).pop(value)),
  ])),
)
```
Эталоны: `_StateChip._pick` (`qr_result_screen.dart:704-750`),
`_ResultControlsState._pickProblem` / `_pickPriority` (`result_controls.dart:87-211`).

Для листов на 90% высоты с рамкой — `showAppModalSheet` вместо голого вызова.

---

## Состояния экрана

| Состояние | Как выглядит | Где |
|---|---|---|
| **Загрузка (первичная)** | `Center(child: CircularProgressIndicator())`. На `/tasks` — крупный: `strokeWidth: 8`, `constraints: minHeight/minWidth 128` | `notifications_screen.dart:138`, `equipment_list_screen.dart:102-107` |
| **Загрузка (кнопка)** | Кнопка не исчезает: внутрь ставится `SizedBox(22×22, CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary))`, поля `enabled: !_busy` | `login_screen.dart:185-200` |
| **Догрузка страницы** | Дополнительный элемент в конце `ListView` с `Padding(vertical: 16) + Center(CircularProgressIndicator())` | `notifications_screen.dart:174-179` |
| **Пусто** | `EmptyState(icon:, title:, hint:)`. Внутри `RefreshIndicator` оборачивается в `ListView` с `AlwaysScrollableScrollPhysics`, чтобы жест работал | `notifications_screen.dart:140-161` |
| **Ошибка (экран)** | Круг 96×96 `errorContainer.withValues(alpha: 0.4)` + иконка 48 `cs.error` + `titleLarge` + `bodyMedium` серым + `FilledButton.icon` с действием восстановления | `knowledge_base_screen.dart:40-82` |
| **Ошибка (действие)** | `Dialogs.notify(context, title, desc)` | `login_screen.dart:73-92` |
| **Ошибка (поле формы)** | `errorText` в `InputDecoration` + флаг подсветки в `State` (`_highlightDescError`) | `result_controls.dart:335-337` |
| **Успех** | Снекбар с `backgroundColor: cs.success`, иконкой `check_circle_rounded` 18px и текстом `cs.onSuccess` | `qr_result_screen.dart:52-78` |
| **Неуспех операции** | Тот же снекбар, но `cs.error` / `cs.onError` / `error_outline_rounded` | там же |
| **Нет связи (список)** | `OfflineBanner` над содержимым; сам список остаётся рабочим, если данные есть в кэше | `widgets/offline_banner.dart`, `repairs/repairs_list_screen.dart` |
| **Данные не отправлены** | Пилюля «Не отправлено» на карточке + пунктирная обводка у локального черновика | `repairs/repairs_list_screen.dart:605-808` |
| **Отправка отклонена сервером** | Причина по-русски прямо на карточке; автоповтора нет, действие выбирает пользователь | `repairs/repair_error_messages.dart` |
| **Disabled** | Тема: фон `onSurface.withValues(alpha: 0.12)`, текст `alpha: 0.38`. У кастомных строк — `enabled: false` + `onTap: null` (`_ActionRow`) | `app_theme.dart:528-529` |
| **Деструктивное** | Цвет текста и иконки `cs.error`, флаг `destructive: true` | `qa_actions.dart:565-597` |

**Правило первичной загрузки:** если данные приходят асинхронно, заводи флаг
«хоть раз загрузили» (`hasLoadedOnce`) и показывай спиннер, а не `EmptyState`,
пока он `false` — иначе на холодном старте мигает «ничего нет».

---

## Формы и валидация

- `TextFormField` с `validator` есть только на `/login`, и **валидация не
  вызывается** — `GlobalKey<FormState>` отсутствует. Фактический паттерн
  валидации в проекте другой: **флаги подсветки в `State`**
  (`_highlightDescError`, `_highlightPriorityError`) → передаются в дочерний
  виджет → `errorText`. Сбрасываются слушателем на изменение поля
  (`qr_result_screen.dart:347-354`).
- Числовая валидация — метод модели: `UsageParameter.validate(value,
  {allowCurrentValue})` возвращает `String?` (`inventory_record.dart:278-298`).
- `textInputAction: TextInputAction.next / done`, `onFieldSubmitted` вызывает
  сабмит, `autofillHints` заданы — `login_screen.dart:137-183`. Повторяй.
- Многострочное поле: `minLines: 3, maxLines: 6, alignLabelWithHint: true`.
- Показ/скрытие пароля — `obscureText: !_passwordVisible` + `suffixIcon`
  `IconButton` с `visibility_outlined` / `visibility_off_outlined`.
- `windowSoftInputMode="adjustResize"` в манифесте — клавиатура сжимает контент,
  поэтому формы всегда внутри `SingleChildScrollView`.

---

## Иконки и изображения

- **Material Icons, вариант `_rounded` или `_outlined`.** Доминирует `_rounded`:
  `qr_code_scanner_rounded`, `checklist_rounded`, `sync_rounded`,
  `chevron_right_rounded`, `expand_more_rounded`, `check_rounded`,
  `warning_amber_rounded`, `close_rounded`. `_outlined` — для «неактивного»
  состояния и сервисных пунктов: `notifications_outlined` vs
  `notifications_rounded`, `settings_outlined`, `info_outline_rounded`,
  `precision_manufacturing_outlined`.
- Размеры: 24 (по умолчанию из `iconTheme`), 48 в `EmptyState`, 36 в hero-карточке,
  18–22 в строках, 11–12 в пилюлях.
- **Один SVG** — `assets/images/ix_user-manual.svg`, рендерится `flutter_svg`
  с `colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn)`
  (`help_link.dart:24-29`).
- Логотип — `assets/images/icon.png`, в `ClipRRect` с радиусом 32 (логин) и 16
  (сплэш).
- Фото оборудования — `Image.network(machine.imageData)` с обязательным
  `errorBuilder` → `Icons.broken_image_outlined`. Нет фото → иконка-заглушка.
  `cached_network_image` в зависимостях есть, но **не используется**.
- Фото осмотра — base64 в памяти, `Image.memory(base64Decode(...))`.
- Лайтбокс — `Dialog(backgroundColor: Colors.transparent, barrierColor:
  Colors.black87)` + `InteractiveViewer` + круглая кнопка закрытия
  (`qr_result_screen.dart:508-548`).

---

## Анимация и переходы

| Что | Параметры | Где |
|---|---|---|
| Переход между страницами | **Отсутствует.** Все 21 маршрут отдают `NoTransitionPage` | `main.dart`, раздел `routes` |
| Раскрытие секции «Сервис» | `AnimatedSize` 200 мс `easeOutCubic` + `AnimatedRotation` 180 мс | `qa_actions.dart:516-531` |
| Диалоги `awesome_dialog` | `animType: AnimType.scale`, `dialogType: DialogType.noHeader`, `reverseBtnOrder: true` | `utils/dialogs.dart` |
| Splash | `InkSparkle.splashFactory` глобально | `app_theme.dart:307` |

Кастомных `AnimationController` в `lib/` нет. **Хаптики отсутствуют полностью** —
`HapticFeedback` не вызывается ни разу.

---

## Доступность

Слабое место, фиксируй честно:

- `Semantics(...)` — **0 вхождений**.
- `semanticLabel` — **0 вхождений**.
- `tooltip:` — 5 вхождений (кнопки AppBar в `notifications_screen`,
  `knowledge_base_screen`).
- Размер шрифта не масштабируется под системные настройки специально
  (`ScreenUtilInit(minTextAdapt: true)` есть, но `.sp` не используется).
- Контраст закладывался как AAA (`app_theme.dart:24`), инструментально не проверялся.

При добавлении иконочных кнопок **ставь `tooltip:`** — это текущий минимум проекта.

---

## Адаптивность и safe area

- Ориентация зафиксирована портретной, брейкпоинты не используются.
- `SafeArea` применяется точечно: обёртка всего приложения (`main.dart:424`),
  логин, онбординг, нижние листы, `_SubmitBar`, `_SettingsSheet`.
  На онбординге — `SafeArea(bottom: false)`, чтобы картинка уходила под низ.
- Ручные отступы под системные зоны: `MediaQuery.of(context).padding.top + 8`
  (`login_screen.dart:209`, `onboarding_video_player.dart:136`).
- Ограничение ширины формы — `ConstrainedBox(maxWidth: 380)` на логине.
- Все длинные экраны — `SingleChildScrollView` или `ListView`; горизонтального
  скролла страницы нет.

---

## Отладочная полоса статуса

Постоянный элемент внизу **каждого** экрана (`main.dart:428-464`): полоса на
`cs.inverseSurface` с текстом `labelSmall` моноширинным, обновляется раз в 15
секунд из `GlobalState.updateDebug()`. Формат:

```
Сервер: доступен  |  Осмотров не отправлено: 0  |  Пользователь: 123
```

Это **не временный отладочный элемент, а часть продукта** — по нему обходчик и
поддержка понимают, есть ли связь и всё ли отправлено. Не убирай и не ломай
разметку `MyApp.build` (`SafeArea → Column → Expanded(app) + полоса`).

---

## Эталонные экраны для новых задач

| Тип задачи | Ориентир |
|---|---|
| Новая плитка/действие на главной | `lib/src/qr/qa_actions.dart` |
| Новый список сущностей | `lib/src/tasks/equipment_list_screen.dart` |
| Список с пагинацией и pull-to-refresh | `lib/src/notifications/notifications_screen.dart` |
| Карточка сущности с метаданными | `lib/src/notifications/notification_card.dart` |
| Экран-форма с липким CTA | `lib/src/qr/qr_result_screen.dart` + `result_controls.dart` |
| Экран настроек (переключатели) | `_SettingsSheet` в `qa_actions.dart`, `notifications_settings_screen.dart` |
| Экран с внешним контентом и ошибкой загрузки | `lib/src/knowledge_base/knowledge_base_screen.dart` |
| Модалка выбора из списка | `_StateChip._pick` в `qr_result_screen.dart` |
| Фильтр-лист с чипами | `lib/src/spare_parts/spare_parts_screen.dart` (рабочий) или `lib/src/tasks/tasks_filter_sheet.dart` (выключен) |
| Список с офлайн-состоянием и очередью | `lib/src/repairs/repairs_list_screen.dart` |
| Экран-карточка с режимами «сервер / черновик / есть неотправленная правка» | `lib/src/repairs/repair_detail_screen.dart` |
| Ввод числа крупными кнопками | `_QuantityStepper` в `repairs/repair_detail_screen.dart` |
| Диалог подтверждения необратимого действия | `_SubmitConfirmDialog` в `repairs/repair_detail_screen.dart` |
| Экран разрешения конфликта / модальный тупик | `lib/src/repairs/repair_conflict_screen.dart` (открывается `Navigator.push`, не `GoRoute`) |
| Выбор даты и диапазона | `showSingleDateSheet` / `showDateRangeSheet` в `widgets/date_range_sheet.dart` |

---

## Расхождение документации и кода

`lib/src/design/README.md` описывает структуру, которой **нет**: папку
`lib/theme/`, `darkTheme` + `ThemeMode.system`, расширения `context.gapMD` /
`context.paddingLG` / `context.colorScheme`. Это боилерплейт генератора тем.
**Не следуй ему и не цитируй как проектную конвенцию.**

Наиболее полное текстовое описание фактической дизайн-системы — не он, а
`ПЛАН_РЕМОНТЫ_ЗИП.md`, раздел «Промт 0 — дизайн-система»: там перечислены
палитра, токены и принятые паттерны в том виде, в каком их согласовали с
заказчиком и дизайнером.
