import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../utils/quantity_format.dart';

/// Блок «Фактический расход ЗИП», общий для карточки ремонта и экрана
/// результата скана.
///
/// Раньше жил приватными виджетами внутри `repairs/repair_detail_screen.dart`.
/// Когда такой же расход понадобился при закрытии задачи ТО, копия на втором
/// экране означала бы два почти одинаковых куска на ~400 строк, которые
/// дальше расходились бы правка за правкой. Поэтому вынесен сюда целиком —
/// вместе со счётчиком количества и предупреждениями о нехватке на складе.
///
/// Что остаётся на стороне экрана: чем заполнен список, что считать нормой и
/// что делать с изменениями. Виджет только рисует и зовёт колбэки.

/// Строка фактического расхода в том виде, в каком её показывают.
///
/// Отдельный тип, а не `RepairConsumption`: у ремонта своя модель, лежащая в
/// Hive со своим `typeId`, у осмотра — своя. Общему виджету от них нужны одни
/// и те же пять полей, и завязывать его на любую из двух значило бы тащить
/// в чужой экран лишний домен.
class ConsumptionLine {
  final String sparePartUuid;
  final String sparePartName;

  /// Единица измерения. В составе нормы сервер её не присылает, экраны
  /// подставляют из локального справочника ЗИП.
  final String? unitName;

  final double quantity;

  /// Плановое количество по норме. `null` — позиции нет в норме либо нормы
  /// нет вовсе; тогда отклонение не считается и не подсвечивается.
  final double? normQuantity;

  const ConsumptionLine({
    required this.sparePartUuid,
    required this.sparePartName,
    this.unitName,
    this.quantity = 0,
    this.normQuantity,
  });
}

/// Вторая кнопка в ряду действий — та, что стоит справа от «Добавить позицию».
///
/// Её место в раскладке занято по умолчанию «Заполнить из нормы» (см.
/// [SparePartConsumptionSection.hasNorm]). Но норма есть не везде: на экране
/// разрешения конфликта плана у осмотра нет вовсе, зато нужно «Уменьшить до
/// остатка». Действие разное — место одно, поэтому кнопка описывается снаружи,
/// а не выбирается флагом внутри.
///
/// [onPressed] `null` — кнопка видна, но погашена: ровно как «Заполнить из
/// нормы», когда добавлять уже нечего. Гасим, а не прячем, чтобы ряд действий
/// не менял высоту и не «прыгал» под пальцем.
class ConsumptionSecondaryAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Поставить кнопку **под** «Добавить позицию», а не справа от неё.
  ///
  /// Справа кнопки делят ширину пополам, и длинная подпись переносится на
  /// вторую строку внутри самой кнопки. «Заполнить из нормы» это переживает —
  /// подпись короткая и привычная, — а «Уменьшить до остатка» в половине
  /// ширины разваливается, и читать ряд становится тяжело. Своя строка даёт
  /// подписи всю ширину: значок и текст остаются в одну линию.
  final bool below;

  const ConsumptionSecondaryAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.below = false,
  });
}

/// Количество расхода для показа — общий формат приложения: целое без дробной
/// части, дробное через запятую. См. `utils/quantity_format.dart`.
String formatConsumptionQuantity(double value) => formatQuantity(value);

/// Шаг кнопок «−» и «+» — по масштабу самого количества.
///
/// Количество на сервере — `Numeric(14, 4)`, то есть литры, килограммы и метры
/// вполне законны. Жёсткий шаг ±1 к ним не подходил: «Заполнить из нормы»
/// подставляло плановые 0,25, а «+» делал из них 1,25 — величину, которой
/// обходчик не имел в виду.
double consumptionStep(double quantity) =>
    quantity == quantity.roundToDouble() ? 1 : 0.1;

/// Округление до четырёх знаков — ровно столько хранит сервер.
///
/// Без него дробный шаг сразу даёт мусор: `0.3 - 0.1` в double равно
/// `0.19999999999999998`, и это уходило бы и на экран (`formatConsumptionQuantity`
/// печатает такие значения как есть), и на сервер.
double roundConsumptionQuantity(double value) =>
    (value * 10000).roundToDouble() / 10000;

/// Позиция расхода, которой на складе меньше указанного.
class ConsumptionShortage {
  final String sparePartUuid;
  final String sparePartName;

  /// Остаток по локальному справочнику. Ноль — списывать нечего вовсе, и это
  /// другая по тяжести беда, чем «есть, но меньше».
  final double available;

  final String unitLabel;

  const ConsumptionShortage({
    required this.sparePartUuid,
    required this.sparePartName,
    required this.available,
    required this.unitLabel,
  });

  /// «3 шт» — остаток с единицей измерения, если она известна.
  String get availableLabel => unitLabel.isEmpty
      ? formatConsumptionQuantity(available)
      : '${formatConsumptionQuantity(available)} $unitLabel';
}

/// Позиции расхода, которых на складе меньше, чем указано.
///
/// Считается по локальному справочнику — без сети это последние
/// синхронизированные остатки, и утверждать по ним, что списание не пройдёт,
/// нельзя. Поэтому результат годится на предупреждение, но не на запрет.
///
/// Общая для двух мест: блок расхода рисует по ней плашки, а форма осмотра
/// переспрашивает перед отправкой. Раньше это считалось только внутри
/// `build`, и обходчик видел красную плашку, отправлял осмотр и получал отказ
/// 409 — тот самый, который приложение уже умело предсказать, но никому об
/// этом не говорило.
List<ConsumptionShortage> consumptionShortages(List<ConsumptionLine> lines) {
  final result = <ConsumptionShortage>[];
  for (final item in lines) {
    if (item.quantity <= 0) continue;
    final part = GlobalState.dataProvider.sparePartByUuid(item.sparePartUuid);
    // Позиции нет в каталоге — сравнивать не с чем. Молчим: это не «не
    // хватает», это «не знаем».
    if (part == null || item.quantity <= part.quantity) continue;
    result.add(ConsumptionShortage(
      sparePartUuid: item.sparePartUuid,
      sparePartName: item.sparePartName,
      available: part.quantity,
      unitLabel: part.unitLabel,
    ));
  }
  return result;
}

class SparePartConsumptionSection extends StatelessWidget {
  final List<ConsumptionLine> lines;
  final bool editable;

  /// Показывать ли предупреждения о нехватке на складе.
  ///
  /// Ремонт передаёт сюда `false`, когда он уже закрыт: остаток в справочнике
  /// на этот самый расход уже уменьшен, и сравнение с ним даёт ложную тревогу
  /// про позицию, которая как раз и была списана. Осмотр передаёт `true`
  /// всегда — списание происходит в момент отправки, до неё остаток ещё цел.
  final bool showStockWarnings;

  /// Есть ли к чему привязывать норму. Без неё счётчик превышений всегда
  /// нулевой и только сбивает с толку, а кнопке «Заполнить из нормы» нечем
  /// заполнять.
  final bool hasNorm;

  /// Есть ли в норме позиции, которых ещё нет в расходе.
  final bool canFillFromNorm;

  /// Чем занять место второй кнопки вместо «Заполнить из нормы».
  ///
  /// `null` — прежнее поведение: кнопка нормы, и только при [hasNorm].
  final ConsumptionSecondaryAction? secondaryAction;

  /// Пояснение под замком — что произойдёт с указанными количествами.
  /// У ремонта и осмотра списание наступает в разные моменты.
  final String writeOffNote;

  /// Текст на месте пустого списка.
  final String emptyNote;

  final VoidCallback onAdd;
  final VoidCallback onFillFromNorm;
  final void Function(int index, double delta) onChangeQuantity;
  final void Function(int index, double value) onSetQuantity;
  final void Function(int index) onRemove;

  const SparePartConsumptionSection({
    super.key,
    required this.lines,
    required this.editable,
    required this.hasNorm,
    required this.canFillFromNorm,
    required this.onAdd,
    required this.onFillFromNorm,
    required this.onChangeQuantity,
    required this.onSetQuantity,
    required this.onRemove,
    this.secondaryAction,
    this.showStockWarnings = true,
    this.writeOffNote = RepairCardStrings.consumptionWriteOffNote,
    this.emptyNote = RepairCardStrings.consumptionEmptyNote,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final overNorm = lines
        .where((item) =>
            item.normQuantity != null && item.quantity > item.normQuantity!)
        .length;

    final shortages =
        showStockWarnings ? consumptionShortages(lines) : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок и значок строго в одну строку: значок прижат к тексту, а
        // не улетает к краю и не переносится вниз на узком экране.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                RepairCardStrings.consumptionTitle,
                style: tt.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Пояснение живёт только в тултипе — и у замка, и у «i»: постоянной
            // надписью оно занимало три строки экрана, а нужно один раз.
            // Замок при этом объясняет, почему расход нельзя править, а «i» —
            // зачем его вообще заполнять.
            _HintIcon(
              icon: editable
                  ? Icons.info_outline_rounded
                  : Icons.lock_outline_rounded,
              message: editable
                  ? RepairCardStrings.consumptionTooltip
                  : writeOffNote,
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSM),
        if (lines.isEmpty)
          Text(
            emptyNote,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingSM),
            _ConsumptionRow(
              // Ключ по позиции ЗИП: без него состояние поля ввода
              // количества привязано к индексу и после удаления строки
              // «переезжает» на соседнюю.
              key: ValueKey(lines[i].sparePartUuid),
              item: lines[i],
              editable: editable,
              onMinus: () =>
                  onChangeQuantity(i, -consumptionStep(lines[i].quantity)),
              onPlus: () =>
                  onChangeQuantity(i, consumptionStep(lines[i].quantity)),
              onChanged: (value) => onSetQuantity(i, value),
              onRemove: () => onRemove(i),
            ),
          ],
        if (editable) ...[
          const SizedBox(height: AppConstants.spacingSM),
          if (secondaryAction?.below == true) ...[
            // Кнопки друг под другом. Каждой достаётся вся ширина, поэтому
            // значок и подпись остаются в одну линию — ради этого раскладку и
            // разводят: «Уменьшить до остатка» в половине ширины переносилась
            // на вторую строку.
            //
            // `Align`, а не растянутая кнопка: заливки у неё нет, растянутая
            // на всю ширину она превратилась бы в полосу с текстом посередине.
            Align(
              alignment: Alignment.centerLeft,
              child: _ActionButton(
                icon: Icons.add_rounded,
                label: RepairCardStrings.addPosition,
                onPressed: onAdd,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _ActionButton(
                icon: secondaryAction!.icon,
                label: secondaryAction!.label,
                onPressed: secondaryAction!.onPressed,
              ),
            ),
          ] else
            // Две кнопки в одну строку, каждая на половине ширины: вторая
            // всегда стоит справа от «Добавить позицию» и никогда не уезжает
            // под неё. Первая прижата к левому краю блока, вторая — к правому
            // (см. `alignment` в [_ActionButton]): по центру своих половин они
            // сходились к середине и не совпадали ни с одним краем текста над
            // ними.
            //
            // Половина ширины вместо «по содержимому» — потому что подписи
            // длинные, и на узком экране (или при увеличенном системном
            // шрифте) они в строку по своей ширине не помещаются. Раньше это
            // решал Wrap, но он переносил вторую кнопку на отдельную строку,
            // ломая пару. Теперь тесноту разбирает сама кнопка: подпись
            // переносится по словам внутри неё (см. [_ActionButton]), а место
            // остаётся прежним.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.add_rounded,
                    label: RepairCardStrings.addPosition,
                    onPressed: onAdd,
                  ),
                ),
                // Вторая кнопка ряда. Экран мог подставить сюда своё действие;
                // если нет — это «Заполнить из нормы», и только при наличии
                // нормы: заполнять нечем, если она не привязана.
                //
                // Нет ни того, ни другого — пустая ячейка вместо кнопки:
                // «Добавить позицию» остаётся на своём месте слева, а не
                // растягивается на всю ширину.
                const SizedBox(width: AppConstants.spacingSM),
                Expanded(
                  child: secondaryAction != null
                      ? _ActionButton(
                          icon: secondaryAction!.icon,
                          label: secondaryAction!.label,
                          onPressed: secondaryAction!.onPressed,
                          alignment: Alignment.centerRight,
                        )
                      : hasNorm
                          ? _ActionButton(
                              icon: Icons.download_rounded,
                              label: RepairCardStrings.fillFromNorm,
                              onPressed:
                                  canFillFromNorm ? onFillFromNorm : null,
                              alignment: Alignment.centerRight,
                            )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
        if (lines.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spacingSM),
          Text(
            // Без нормы сравнивать не с чем — счётчик превышений был бы
            // всегда нулевым и только сбивал бы с толку.
            hasNorm
                ? RepairCardStrings.positionsWithOverNorm(
                    lines.length, overNorm)
                : RepairCardStrings.positions(lines.length),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        // Цвет по тяжести: позиции нет на складе совсем — красный, есть, но
        // меньше нужного — оранжевый. Нулевой остаток это не «пополнить бы», а
        // «списывать нечего», и выглядеть одинаково они не должны.
        for (final shortage in shortages) ...[
          const SizedBox(height: AppConstants.spacingSM),
          _ShortageBanner(
            title: shortage.sparePartName,
            text: shortage.available <= 0
                ? RepairCardStrings.outOfStock
                : RepairCardStrings.shortage(shortage.availableLabel),
            warning: shortage.available > 0,
            danger: shortage.available <= 0,
          ),
        ],
      ],
    );
  }
}

class _ConsumptionRow extends StatelessWidget {
  final ConsumptionLine item;
  final bool editable;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChanged;
  final VoidCallback onRemove;

  const _ConsumptionRow({
    super.key,
    required this.item,
    required this.editable,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final norm = item.normQuantity;
    final unit = item.unitName?.trim() ?? '';

    // Цвет количества: красный — больше нормы, зелёный — меньше, обычный —
    // ровно по норме или когда нормы нет.
    Color valueColor = cs.onSurface;
    if (norm != null) {
      if (item.quantity > norm) {
        valueColor = cs.error;
      } else if (item.quantity < norm) {
        valueColor = cs.success;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            ),
            child: SvgPicture.asset(
              'assets/images/spare_part.svg',
              width: 20,
              height: 20,
              colorFilter:
                  ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: AppConstants.spacingSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.sparePartName,
                  style: tt.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (norm != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    RepairCardStrings.norm(
                      '${formatConsumptionQuantity(norm)}'
                      '${unit.isEmpty ? '' : ' $unit'}',
                    ),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingSM),
          SparePartQuantityStepper(
            value: item.quantity,
            valueColor: valueColor,
            enabled: editable,
            onMinus: onMinus,
            onPlus: onPlus,
            onChanged: onChanged,
          ),
          if (editable) ...[
            IconButton(
              // Trash2 из lucide — та же иконка удаления, что в веб-админке
              // (SparePartMovementDialog, RepairDetailsDialog).
              icon: SvgPicture.asset(
                'assets/images/trash.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(cs.error, BlendMode.srcIn),
              ),
              tooltip: RepairCardStrings.removePosition,
              // Поджимаем до 40 px: строка и так тесная, а под длинное число
              // нужно место. 40 — всё ещё комфортная цель для пальца.
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// Счётчик «− значение +». Кнопки крупные намеренно: обходчик работает в
/// перчатках, поэтому тап-таргеты не меньше 36 px.
///
/// Число не только листается кнопками, но и вводится руками — иначе набрать
/// «250» означало бы 250 нажатий на «+».
class SparePartQuantityStepper extends StatefulWidget {
  final double value;
  final Color valueColor;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChanged;

  const SparePartQuantityStepper({
    super.key,
    required this.value,
    required this.valueColor,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
  });

  @override
  State<SparePartQuantityStepper> createState() =>
      _SparePartQuantityStepperState();
}

class _SparePartQuantityStepperState extends State<SparePartQuantityStepper> {
  /// Ширина поля под короткое значение — чтобы «5» не болталось в пустоте.
  static const double _minFieldWidth = 56;

  /// Верхний предел: помещает девятизначное число уменьшенным кеглем.
  /// Дальше растягивать нельзя — счётчик выдавит название позиции из строки.
  static const double _maxFieldWidth = 100;

  /// С какой длины значение показываем компактнее.
  static const int _compactAfterChars = 5;

  late final TextEditingController _controller =
      TextEditingController(text: formatConsumptionQuantity(widget.value));
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SparePartQuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Значение поменяли снаружи (кнопки «−»/«+», «Заполнить из нормы»).
    // Пока поле в фокусе, не трогаем его — иначе перебьём то, что печатают.
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = formatConsumptionQuantity(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Ушли из поля — приводим текст к тому, что реально лежит в модели.
  /// Пустое или мусорное значение просто откатывается, а не обнуляет позицию.
  void _onFocusChanged() {
    if (_focusNode.hasFocus || !mounted) return;
    // setState нужен не только ради текста: от его длины считается ширина
    // поля, а она пересчитывается только в build.
    setState(() => _controller.text = formatConsumptionQuantity(widget.value));
  }

  void _onChanged(String raw) {
    // Перерисовываем себя в любом случае — от длины текста зависит ширина
    // поля, и она должна меняться даже когда значение ещё не валидно
    // (например, пользователь стёр всё и набирает заново).
    setState(() {});
    // Запятая — обычный десятичный разделитель на русской раскладке.
    final parsed = parseQuantity(raw);
    if (parsed == null || parsed <= 0) return;
    widget.onChanged(parsed);
  }

  /// Ширина поля под текущее значение: короткие числа не растягивают строку,
  /// а девятизначное помещается целиком, не обрезаясь.
  ///
  /// Меряем реальным [TextPainter], а не «символ × N»: кегль и масштаб
  /// системного шрифта у разных обходчиков разные.
  double _fieldWidth(BuildContext context, TextStyle? style) {
    final text = _controller.text.isEmpty ? '0' : _controller.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // 12 px — воздух по бокам, чтобы цифры не липли к кнопкам.
    return (painter.width + 12).clamp(_minFieldWidth, _maxFieldWidth);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Длинные значения показываем мельче: девятизначное число крупным
    // кеглем выдавило бы название позиции из строки. Обычные «5» или «12»
    // остаются крупными — это подавляющее большинство случаев.
    final isLongValue = _controller.text.length > _compactAfterChars;
    final baseStyle = isLongValue ? tt.bodyLarge : tt.titleMedium;

    // Моноширинные цифры — локально, только для этого поля: глобально
    // tabularFigures в проекте запрещены, они ломают кириллицу на Samsung.
    final valueStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: widget.valueColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (!widget.enabled) {
      // Только чтение: та же пилюля, что и в редактируемом виде, но без
      // кнопок и приглушённая.
      return Opacity(
        opacity: 0.6,
        child: Container(
          constraints: const BoxConstraints(minWidth: _minFieldWidth),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: AppConstants.spacingSM,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            formatConsumptionQuantity(widget.value),
            style: valueStyle,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(icon: Icons.remove_rounded, onTap: widget.onMinus),
          SizedBox(
            width: _fieldWidth(context, valueStyle),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              textAlign: TextAlign.center,
              style: valueStyle,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: const [QuantityInputFormatter()],
              onTapOutside: (_) => _focusNode.unfocus(),
              // Поле сидит внутри пилюли счётчика, поэтому собственную рамку
              // и подложку из темы убираем.
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                counterText: '',
              ),
            ),
          ),
          _StepperButton(icon: Icons.add_rounded, onTap: widget.onPlus),
        ],
      ),
    );
  }
}

/// Пропускает в поле количества только цифры и **один** десятичный
/// разделитель, режет значение до 9 значащих цифр и до 4 знаков после
/// разделителя — ровно как `QuantityStepper` в веб-админке.
///
/// Раньше разделитель писался в буфер без проверки, и в поле набиралось
/// «1.2.3» или «1,,5». `double.tryParse` на таком возвращает `null`,
/// `onChanged` не вызывался, и при потере фокуса текст молча откатывался к
/// прежнему значению — без единого объяснения, почему введённое пропало.
///
/// Четыре знака — это `Numeric(14, 4)` на сервере. Без ограничения 1,23456
/// уходило туда и тихо округлялось: обходчик видел одно, в документе
/// оказывалось другое.
class QuantityInputFormatter extends TextInputFormatter {
  static const int _maxDigits = 9;

  /// Столько знаков после разделителя хранит сервер.
  static const int _maxDecimals = 4;
  static const String _digits = '0123456789';

  const QuantityInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var digits = 0;
    var hasSeparator = false;
    var decimals = 0;
    for (final char in newValue.text.split('')) {
      if (_digits.contains(char)) {
        if (digits >= _maxDigits) continue;
        if (hasSeparator && decimals >= _maxDecimals) continue;
        digits++;
        if (hasSeparator) decimals++;
        buffer.write(char);
      } else if (char == ',' || char == '.') {
        // Второй разделитель отбрасываем молча: набрать «1.2.3» нельзя, а
        // курсор при этом не прыгает — символ просто не появляется.
        if (hasSeparator) continue;
        hasSeparator = true;
        buffer.write(char);
      }
    }
    final text = buffer.toString();
    // Ничего не отфильтровали — отдаём как есть, чтобы не сбить позицию
    // курсора при обычном наборе.
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Иконки, а не текстовые глифы «+» и «−»: в шрифте они разной ширины и
    // высоты, и кнопки выглядели неодинаковыми. У иконок общая сетка 24×24.
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(child: Icon(icon, size: 22, color: cs.onSurface)),
      ),
    );
  }
}

/// Кнопка действия под списком расхода: значок и подпись строго в одну
/// строку, подпись при нехватке места ужимается сама.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// К какому краю отведённой половины прижимается содержимое.
  ///
  /// Кнопка занимает половину ширины (см. ряд действий), и по умолчанию
  /// `TextButton` центрует содержимое внутри неё — две кнопки сходились к
  /// середине блока и висели в воздухе. Левая прижимается к левому краю,
  /// правая — к правому, и обе встают по краям блока, как заголовок и текст
  /// над ними.
  final AlignmentGeometry alignment;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: alignment,
        // Без горизонтальных полей: содержимое обязано вставать вровень с краем
        // блока, а не отступать от него на ширину поля. Заодно кнопка живёт в
        // половине ширины экрана вместе с иконкой, и отступы съедали бы место
        // у подписи.
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, AppConstants.buttonHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 6),
          Flexible(
            // Перенос по словам вместо многоточия: подпись не влезает в
            // половину ширины на узком экране, и обрезать её нельзя —
            // «Заполнить из но…» не говорит ничего.
            child: Text(label, softWrap: true),
          ),
        ],
      ),
    );
  }
}

class _HintIcon extends StatelessWidget {
  final IconData icon;
  final String message;

  const _HintIcon({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: Padding(
        // Иконка 18 px сама по себе — слишком мелкая цель для работы в
        // перчатках, отступ доводит область нажатия до ~34 px.
        padding: const EdgeInsets.all(AppConstants.spacingSM),
        child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// Полоса предупреждения о нехватке ЗИП.
///
/// Повторяет оформление `_Banner` из карточки ремонта, но живёт здесь: там
/// `_Banner` умеет ещё кнопку и центрирование и используется для конфликтов
/// и очереди. Тащить его сюда целиком значило бы переносить чужую логику,
/// а полоса нехватки всегда одна и та же — заголовок, текст, цвет по тяжести.
class _ShortageBanner extends StatelessWidget {
  final String title;
  final String text;
  final bool warning;
  final bool danger;

  const _ShortageBanner({
    required this.title,
    required this.text,
    this.warning = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = danger
        ? cs.error
        : warning
            ? cs.warning
            : cs.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: tt.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(text, style: tt.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
