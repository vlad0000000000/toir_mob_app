import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';

/// Месяцы: именительный для выпадающего списка в календаре, родительный для
/// подписей вида «12 марта 2026».
///
/// Свой список, а не `DateFormat(..., 'ru_RU')`: русские данные intl нужно
/// сначала асинхронно подгрузить (`initializeDateFormatting`), а
/// `flutter_localizations` в проект не поставить — пакет из SDK требует
/// intl 0.19, и понижение с 0.20 ломает сборку самого Flutter.
const List<String> monthsNominativeRu = [
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];

const List<String> monthsGenitiveRu = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// Дата словами: «12 марта 2026».
String formatDayLabelRu(DateTime at) =>
    '${at.day} ${monthsGenitiveRu[at.month - 1]} ${at.year}';

/// Лист выбора одной даты — тот же календарь, что в фильтре периода, только
/// панель одна.
///
/// Возвращает выбранный день или `null`, если лист закрыли.
Future<DateTime?> showSingleDateSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SingleDateSheet(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _SingleDateSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _SingleDateSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_SingleDateSheet> createState() => _SingleDateSheetState();
}

class _SingleDateSheetState extends State<_SingleDateSheet> {
  late DateTime _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      // «Сбросить» здесь нет: дата начала ремонта обязательна, сбрасывать её
      // не во что — в отличие от границы периода, которую можно не задавать.
      onDone: () => Navigator.of(context).pop(_selected),
      child: CalendarPanel(
        title: widget.title,
        selected: _selected,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        onSelected: (day) => setState(() => _selected = day),
      ),
    );
  }
}

/// Общая рамка листа выбора: прокручиваемое содержимое и липкая строка кнопок
/// снизу. Одна на выбор периода, одной даты и времени — чтобы все три листа
/// выглядели одинаково.
class SheetFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback onDone;

  /// Кнопка сброса слева. Её нет там, где сбрасывать нечего.
  final VoidCallback? onReset;

  const SheetFrame({
    super.key,
    required this.child,
    required this.onDone,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                0,
                AppConstants.spacingMD,
                AppConstants.spacingMD,
              ),
              child: child,
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingSM,
              AppConstants.spacingMD,
              AppConstants.spacingSM,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: onReset == null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (onReset != null)
                  TextButton(
                    onPressed: onReset,
                    child: const Text(SparePartStrings.reset),
                  ),
                TextButton(
                  onPressed: onDone,
                  child: const Text(SparePartStrings.done),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Выбранный период. Отдельный тип, а не пара дат: `null` от листа означает
/// «закрыл, ничего не меняя», и отличить это от «сбросил обе границы» иначе
/// нельзя.
class DateRange {
  final DateTime? from;
  final DateTime? to;

  const DateRange({this.from, this.to});

  bool get isEmpty => from == null && to == null;
}

/// Лист выбора периода с двумя календарями — «С даты» и «По дату», как в
/// карточке ЗИП веб-админки.
///
/// Календарь нарисован вручную, а не взят из `showDatePicker`: штатный без
/// `flutter_localizations` показывает английские месяцы и дни, а поставить
/// этот пакет нельзя — он требует intl 0.19 и ломает сборку самого Flutter
/// (подробности в `main.dart`).
///
/// На телефоне панели идут одна под другой и прокручиваются: рядом, как в
/// админке на широком экране, они не помещаются.
Future<DateRange?> showDateRangeSheet(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showModalBottomSheet<DateRange>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DateRangeSheet(
      from: from,
      to: to,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _DateRangeSheet extends StatefulWidget {
  final DateTime? from;
  final DateTime? to;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DateRangeSheet({
    this.from,
    this.to,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  late DateTime? _from = widget.from;
  late DateTime? _to = widget.to;

  bool get _active => _from != null || _to != null;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      onReset:
          _active ? () => Navigator.of(context).pop(const DateRange()) : null,
      onDone: () => Navigator.of(context).pop(DateRange(from: _from, to: _to)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CalendarPanel(
            title: SparePartStrings.periodFrom,
            selected: _from,
            firstDate: widget.firstDate,
            // Начало периода не может быть позже его конца — то же
            // ограничение, что у календарей в админке.
            lastDate: _to ?? widget.lastDate,
            onSelected: (day) => setState(() => _from = day),
          ),
          const SizedBox(height: AppConstants.spacingMD),
          CalendarPanel(
            title: SparePartStrings.periodTo,
            selected: _to,
            firstDate: _from ?? widget.firstDate,
            lastDate: widget.lastDate,
            onSelected: (day) => setState(() => _to = day),
          ),
        ],
      ),
    );
  }
}

/// Одна панель календаря: подпись, выбор месяца и года, сетка дней.
class CalendarPanel extends StatefulWidget {
  final String title;
  final DateTime? selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onSelected;

  const CalendarPanel({
    required this.title,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
  });

  @override
  State<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends State<CalendarPanel> {
  /// Месяц, открытый в сетке. Не то же, что выбранный день: листать можно
  /// свободно, ничего не выбирая.
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = _monthOf(widget.selected ?? _clamp(DateTime.now()));
  }

  @override
  void didUpdateWidget(CalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Границы могли сдвинуться после выбора в соседней панели — если открытый
    // месяц вышел за них, подтягиваем его обратно.
    final clamped = _clamp(_visibleMonth);
    if (_monthOf(clamped) != _visibleMonth) {
      _visibleMonth = _monthOf(clamped);
    }
  }

  static DateTime _monthOf(DateTime value) => DateTime(value.year, value.month);

  DateTime _clamp(DateTime value) {
    if (value.isBefore(widget.firstDate)) return widget.firstDate;
    if (value.isAfter(widget.lastDate)) return widget.lastDate;
    return value;
  }

  List<int> get _years => [
        for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
      ];

  /// Месяцы, доступные в выбранном году: в крайних годах диапазон обрезан.
  List<int> get _months {
    final first = _visibleMonth.year == widget.firstDate.year
        ? widget.firstDate.month
        : 1;
    final last =
        _visibleMonth.year == widget.lastDate.year ? widget.lastDate.month : 12;
    return [for (var m = first; m <= last; m++) m];
  }

  bool _isSelectable(DateTime day) =>
      !day.isBefore(_dayStart(widget.firstDate)) &&
      !day.isAfter(_dayStart(widget.lastDate));

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Сетка 6×7, начиная с понедельника: ведущие и хвостовые ячейки — дни
  /// соседних месяцев, они показываются приглушённо и не выбираются.
  List<DateTime> get _grid {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    // weekday: 1 — понедельник, значит сдвиг равен weekday - 1.
    final leading = first.weekday - 1;
    final start = first.subtract(Duration(days: leading));
    return [for (var i = 0; i < 42; i++) _addDays(start, i)];
  }

  /// Прибавляем дни через календарь, а не `Duration`: в сутках перехода на
  /// летнее время их не 24 часа, и арифметика с Duration сдвинула бы день.
  static DateTime _addDays(DateTime from, int days) =>
      DateTime(from.year, from.month, from.day + days);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selected =
        widget.selected == null ? null : _dayStart(widget.selected!);
    final grid = _grid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: tt.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSM),
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _PanelDropdown<int>(
                      value: _visibleMonth.month,
                      items: [
                        for (final m in _months)
                          DropdownMenuItem(
                            value: m,
                            child: Text(monthsNominativeRu[m - 1]),
                          ),
                      ],
                      onChanged: (m) => setState(
                        () => _visibleMonth = DateTime(_visibleMonth.year, m!),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSM),
                  Expanded(
                    flex: 2,
                    child: _PanelDropdown<int>(
                      value: _visibleMonth.year,
                      items: [
                        for (final y in _years)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (y) => setState(() {
                        // Год мог обрезать список месяцев — подтягиваем месяц
                        // в допустимые пределы, иначе Dropdown получит
                        // значение, которого нет в его items, и упадёт.
                        final next = DateTime(y!, _visibleMonth.month);
                        _visibleMonth = _monthOf(_clamp(next));
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingMD),
              Row(
                children: [
                  for (final name in _weekdayNames)
                    Expanded(
                      child: Center(
                        child: Text(
                          name,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingSM),
              for (var week = 0; week < 6; week++)
                Row(
                  children: [
                    for (var i = week * 7; i < week * 7 + 7; i++)
                      Expanded(
                        child: _DayCell(
                          day: grid[i],
                          inMonth: grid[i].month == _visibleMonth.month,
                          selected: selected != null &&
                              _dayStart(grid[i]) == selected,
                          enabled: grid[i].month == _visibleMonth.month &&
                              _isSelectable(_dayStart(grid[i])),
                          onTap: () => widget.onSelected(_dayStart(grid[i])),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

const List<String> _weekdayNames = [
  'пн',
  'вт',
  'ср',
  'чт',
  'пт',
  'сб',
  'вс',
];

/// Ячейка дня: выбранный — залитый плашкой, чужой месяц и недоступные дни —
/// приглушённые и не нажимаются.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final Color color;
    if (selected) {
      color = cs.primary;
    } else if (!inMonth || !enabled) {
      color = cs.onSurfaceVariant.withValues(alpha: 0.5);
    } else {
      color = cs.onSurface;
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            child: Center(
              child: Text(
                '${day.day}',
                style: tt.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Выпадающий список месяца и года — в рамке со скруглением, как в админке.
class _PanelDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _PanelDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      height: AppConstants.buttonHeightSmall,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSM),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          icon: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          style: tt.bodyMedium?.copyWith(color: cs.onSurface),
        ),
      ),
    );
  }
}
