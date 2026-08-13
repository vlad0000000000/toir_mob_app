import 'dart:async';

import 'package:flutter/material.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../model/spare_part.dart';
import '../widgets/empty_state.dart';
import '../widgets/spare_part_row.dart';

/// Окно выбора позиции ЗИП для строки фактического расхода.
///
/// Ищет по локальному справочнику — тому же, что показывает раздел «ЗИП».
/// Серверный поиск не используем: экран должен работать и без сети, а на
/// устройстве уже лежит весь каталог.
///
/// Возвращает выбранную позицию или `null`, если окно закрыли.
Future<SparePart?> showSparePartPicker(
  BuildContext context, {
  required Set<String> alreadyAddedUuids,
}) {
  return showModalBottomSheet<SparePart>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SparePartPickerSheet(alreadyAdded: alreadyAddedUuids),
  );
}

class _SparePartPickerSheet extends StatefulWidget {
  final Set<String> alreadyAdded;

  const _SparePartPickerSheet({required this.alreadyAdded});

  @override
  State<_SparePartPickerSheet> createState() => _SparePartPickerSheetState();
}

class _SparePartPickerSheetState extends State<_SparePartPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  /// Результат держим полем: build вызывается на каждое касание листа, а
  /// проход по каталогу в десятки тысяч позиций там недопустим.
  late List<SparePart> _results = _filterNow();

  /// Фильтруем не на каждый символ, а после паузы — иначе набор слова
  /// «подшипник» дал бы девять полных проходов по каталогу.
  Timer? _debounce;
  static const Duration _searchDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<SparePart> _filterNow() {
    // Запрос приводим к нижнему регистру один раз; позиции сравниваются по
    // заранее подготовленным полям (`SparePart.matchesQuery`).
    // Не сортируем — каталог уже отсортирован при синхронизации.
    final query = _query.trim().toLowerCase();
    final all = GlobalState.dataProvider.spareParts;
    if (query.isEmpty) return all;
    final result = <SparePart>[];
    for (final part in all) {
      if (part.matchesQuery(query)) result.add(part);
    }
    return result;
  }

  void _onQueryChanged(String value) {
    // Текст обновляем сразу — от него зависит крестик очистки.
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, () {
      if (!mounted) return;
      setState(() => _results = _filterNow());
    });
  }

  void _clearQuery() {
    _controller.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _results = _filterNow();
    });
  }

  /// Дата выгрузки справочника — обходчик должен понимать, насколько свежие
  /// остатки он видит при выборе.
  String? get _catalogAsOf => GlobalState.dataProvider.sparePartsFreshness();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final asOf = _catalogAsOf;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Text(RepairStrings.pickerTitle, style: tt.titleLarge),
            const SizedBox(height: AppConstants.spacingMD),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMD,
              ),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: RepairStrings.pickerHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: RepairStrings.clearSearch,
                          onPressed: _clearQuery,
                        ),
                ),
              ),
            ),
            if (asOf != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingMD,
                  AppConstants.spacingSM,
                  AppConstants.spacingMD,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    RepairStrings.pickerAsOf(asOf),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            const SizedBox(height: AppConstants.spacingSM),
            Expanded(
              child: _results.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: RepairStrings.nothingFound,
                      hint: GlobalState.dataProvider.spareParts.isEmpty
                          ? RepairStrings.pickerCatalogEmpty
                          : RepairStrings.pickerRefine,
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        color: cs.outlineVariant,
                      ),
                      itemBuilder: (context, index) {
                        final part = _results[index];
                        final added = widget.alreadyAdded.contains(part.uuid);
                        return SparePartRow(
                          part: part,
                          dimmed: added,
                          onTap: added
                              ? null
                              : () => Navigator.of(context).pop(part),
                          trailing: added
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded,
                                        size: 18, color: cs.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      RepairStrings.pickerAdded,
                                      style: tt.labelMedium
                                          ?.copyWith(color: cs.primary),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
