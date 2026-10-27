import 'package:flutter/material.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import 'filter_controls.dart';

/// Общие элементы поиска и фильтров: строка поиска с кнопкой фильтров, лист
/// «Фильтры», заголовок раздела и чипы.
///
/// Сначала были написаны внутри справочника ЗИП. Список оборудования и
/// задачи оборудования собраны на них же — чтобы фильтры во всех трёх
/// разделах выглядели и вели себя одинаково, а не расходились копиями.

/// Поле поиска и кнопка фильтров в одну строку, над списком.
///
/// Крестик очистки следит за текстом поля сам, через [controller]. Экрану
/// не нужно перестраиваться на каждый символ ради крестика: раньше каждая
/// буква перестраивала весь экран, и список оборудования заново проходил
/// по всем задачам — на сотнях единиц набор подтормаживал.
class SearchFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Число активных условий фильтра для кнопки.
  final int activeCount;
  final VoidCallback onFilter;

  const SearchFilterBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    required this.activeCount,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight + stretch: кнопка фильтра принимает ровно ту же
    // высоту, что и поле поиска. Задавать ей высоту числом нельзя —
    // фактическая высота TextField зависит от темы и кегля.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: FilterStrings.clearSearch,
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingSM),
          FilterButton(activeCount: activeCount, onTap: onFilter),
        ],
      ),
    );
  }
}

/// Каркас листа «Фильтры»: шапка со «Сбросить», прокручиваемые разделы и
/// липкая кнопка с живым счётчиком.
///
/// Кнопка обещает ровно то число, которое обходчик увидит после закрытия
/// листа, — вызывающий считает его той же функцией отбора, что и список.
/// Если не подходит ничего — «Ничего не найдено», и кнопка неактивна:
/// применять фильтр, после которого список окажется пустым, незачем.
class FilterSheet extends StatelessWidget {
  /// `null` — сбрасывать нечего, «Сбросить» приглушена.
  final VoidCallback? onReset;
  final List<Widget> children;
  final int resultCount;

  /// Подпись кнопки при ненулевом результате: «Показать 5 единиц».
  final String Function(int count) resultLabel;
  final VoidCallback onApply;

  const FilterSheet({
    super.key,
    required this.onReset,
    required this.children,
    required this.resultCount,
    required this.resultLabel,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    FilterStrings.title,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onReset,
                  child: const Text(FilterStrings.reset),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMD,
                AppConstants.spacingSM,
                AppConstants.spacingMD,
                AppConstants.spacingMD,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMD,
              AppConstants.spacingSM,
              AppConstants.spacingMD,
              AppConstants.spacingMD,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: SizedBox(
              height: AppConstants.buttonHeightLarge,
              child: ElevatedButton(
                onPressed: resultCount == 0 ? null : onApply,
                child: Text(
                  resultCount == 0
                      ? FilterStrings.nothingFound
                      : resultLabel(resultCount),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Раздел листа: заголовок, под ним содержимое и отступ до следующего.
class FilterSection extends StatelessWidget {
  final String label;

  /// Сколько значений выбрано. Ноль — счётчик не рисуется.
  final int count;
  final Widget child;

  const FilterSection({
    super.key,
    required this.label,
    this.count = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterSectionLabel(label, count: count),
          const SizedBox(height: AppConstants.spacingSM),
          child,
        ],
      ),
    );
  }
}

/// Заголовок раздела — прописными, с зелёным «· N» выбранного.
class FilterSectionLabel extends StatelessWidget {
  final String text;

  /// Сколько значений выбрано в разделе. Ноль — счётчик не рисуется.
  final int count;

  const FilterSectionLabel(this.text, {super.key, this.count = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final labelStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
    final title = Text(text.toUpperCase(), style: labelStyle);
    if (count == 0) return title;
    return Row(
      children: [
        title,
        const SizedBox(width: 6),
        Text(
          '· $count',
          style: labelStyle?.copyWith(color: cs.primary),
        ),
      ],
    );
  }
}

/// Чипы множественного выбора, по нескольку в ряд.
///
/// Выбранные — наверху, остальные по порядку [options]. Длинный раздел
/// после [collapsedLimit] чипов сворачивается в «Ещё N»: помещений бывает
/// два-три десятка, и все сразу растянули бы лист на несколько экранов.
class FilterChipGroup extends StatefulWidget {
  /// Ключ значения → подпись, в порядке показа.
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final int collapsedLimit;

  const FilterChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.collapsedLimit = 8,
  });

  @override
  State<FilterChipGroup> createState() => _FilterChipGroupState();
}

class _FilterChipGroupState extends State<FilterChipGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final entries = [
      // Выбранные поднимаем наверх: иначе после сворачивания активный фильтр
      // мог бы оказаться спрятанным под «Ещё N».
      for (final entry in widget.options.entries)
        if (selected.contains(entry.key)) entry,
      for (final entry in widget.options.entries)
        if (!selected.contains(entry.key)) entry,
    ];

    final hidden = _expanded ? 0 : entries.length - widget.collapsedLimit;
    final visible = hidden > 0 ? entries.take(widget.collapsedLimit) : entries;

    return Wrap(
      spacing: AppConstants.spacingSM,
      runSpacing: AppConstants.spacingSM,
      children: [
        for (final entry in visible)
          FilterPillChip(
            label: entry.value,
            selected: selected.contains(entry.key),
            onTap: () {
              final next = {...selected};
              if (!next.remove(entry.key)) next.add(entry.key);
              widget.onChanged(next);
            },
          ),
        if (hidden > 0)
          _MoreChip(
            count: hidden,
            onTap: () => setState(() => _expanded = true),
          ),
      ],
    );
  }
}

/// Чип «Ещё N» — раскрывает спрятанные варианты. Обратно не сворачивается:
/// свернуть уже увиденное посреди выбора только сбивает.
class _MoreChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MoreChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppConstants.buttonHeightSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FilterStrings.more(count),
                style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Чип-«пилюля»: выбранный — зелёный с галочкой.
class FilterPillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          // Общая минимальная высота: чипы в строке одинаковые независимо
          // от того, показана ли галочка. Без неё выбранные становились выше.
          constraints: const BoxConstraints(
            minHeight: AppConstants.buttonHeightSmall,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: AppConstants.spacingSM,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border:
                Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 16, color: cs.onPrimary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: selected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
