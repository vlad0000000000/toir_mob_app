import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';

/// Месяцы: именительный для колеса выбора, родительный для подписей вида
/// «12 марта 2026».
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

/// Выбор даты колёсами — русская замена `showDatePicker`.
///
/// Штатный пикер здесь не годится по той же причине, по которой в проекте уже
/// отказались от `showTimePicker`: без `flutter_localizations` он показывает
/// английский календарь посреди русского интерфейса, а поставить этот пакет
/// нельзя — он тянет intl 0.19 и ломает сборку Flutter.
///
/// Возвращает выбранный день или `null`, если лист закрыли.
Future<DateTime?> showDateWheelSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (_) => _DateWheelSheet(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _DateWheelSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? title;

  const _DateWheelSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    this.title,
  });

  @override
  State<_DateWheelSheet> createState() => _DateWheelSheetState();
}

class _DateWheelSheetState extends State<_DateWheelSheet> {
  late int _year;
  late int _month;
  late int _day;

  late final List<int> _years = [
    for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
  ];

  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    final start = _clamp(widget.initial);
    _year = start.year;
    _month = start.month;
    _day = start.day;
    _dayController = FixedExtentScrollController(initialItem: _day - 1);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
    _yearController =
        FixedExtentScrollController(initialItem: _years.indexOf(_year));
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime value) {
    if (value.isBefore(widget.firstDate)) return widget.firstDate;
    if (value.isAfter(widget.lastDate)) return widget.lastDate;
    return value;
  }

  /// Сколько дней в выбранном месяце: нулевой день следующего месяца — это
  /// последний день текущего.
  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  DateTime get _selected {
    // 31-е при переключении на февраль превратилось бы в 3 марта — подрезаем.
    final day = _day > _daysInMonth ? _daysInMonth : _day;
    return DateTime(_year, _month, day);
  }

  bool get _outOfRange =>
      _selected.isBefore(widget.firstDate) ||
      _selected.isAfter(widget.lastDate);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          0,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title ?? RepairStrings.dateSheetTitle,
                style: tt.titleLarge),
            const SizedBox(height: AppConstants.spacingMD),
            SizedBox(
              height: 176,
              child: Stack(
                children: [
                  // Подсветка выбранной строки — как у колеса времени.
                  Center(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusSM),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _DateWheel(
                          controller: _dayController,
                          count: _daysInMonth,
                          labelOf: (index) => '${index + 1}',
                          onChanged: (index) =>
                              setState(() => _day = index + 1),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: _DateWheel(
                          controller: _monthController,
                          count: 12,
                          labelOf: (index) => monthsNominativeRu[index],
                          onChanged: (index) =>
                              setState(() => _month = index + 1),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _DateWheel(
                          controller: _yearController,
                          count: _years.length,
                          labelOf: (index) => '${_years[index]}',
                          onChanged: (index) =>
                              setState(() => _year = _years[index]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            SizedBox(
              height: AppConstants.buttonHeightLarge,
              width: double.infinity,
              child: ElevatedButton(
                // Вне допустимого диапазона кнопка гаснет: колёса крутятся
                // свободно, и запрещать саму прокрутку было бы неудобнее, чем
                // не дать подтвердить негодную дату.
                onPressed: _outOfRange
                    ? null
                    : () => Navigator.of(context).pop(_selected),
                child: const Text(RepairStrings.done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateWheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) labelOf;
  final ValueChanged<int> onChanged;

  const _DateWheel({
    required this.controller,
    required this.count,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) => Center(
          child: Text(labelOf(index), style: tt.titleMedium),
        ),
      ),
    );
  }
}
