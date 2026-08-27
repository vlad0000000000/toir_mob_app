import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../data/data_provider.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../exceptions/app_exceptions.dart';
import '../model/scan.dart';
import '../repairs/repair_delete_dialog.dart';
import '../repairs/spare_part_picker_sheet.dart';
import '../widgets/spare_part_consumption.dart';
import 'scan_error_messages.dart';

/// Экран разрешения конфликта при отправке осмотра.
///
/// Открывается, когда сервер отказался принять осмотр по существу — чаще
/// всего потому, что фактического расхода ЗИП не хватило на складе: задачу
/// закрыли в цеху без связи, а к моменту отправки позиции уже разобрали.
///
/// Устроен как `repairs/repair_conflict_screen.dart` и по той же причине
/// открывается через `Navigator.push`, а не `GoRoute`: это модальный тупик,
/// из которого возвращаются назад, а не ветка навигации.
///
/// Автоматически здесь не удаляется ничего: пока обходчик не нажал кнопку,
/// его осмотр лежит на устройстве.
class ScanConflictScreen extends StatefulWidget {
  /// Отклонённый осмотр. Ключ в боксе — `scan.key()`.
  final Scan scan;

  const ScanConflictScreen({super.key, required this.scan});

  @override
  State<ScanConflictScreen> createState() => _ScanConflictScreenState();
}

class _ScanConflictScreenState extends State<ScanConflictScreen> {
  bool _isBusy = false;

  /// Расход, который правит обходчик.
  ///
  /// Отдельно от осмотра в очереди: пока правку не отправили, очередь должна
  /// видеть исходные количества. Заполняется один раз при открытии — экран
  /// перечитывает осмотр из бокса, но набранные позиции при этом обязаны
  /// уцелеть.
  late List<ConsumptionLine> _lines = _consumptionsFromScan();

  /// Количества, с которыми осмотр сейчас лежит в очереди, — чтобы понять,
  /// правил ли обходчик что-нибудь. Пересобираются вместе с [_lines]: после
  /// повторного отказа «исходным» становится уже исправленный расход, иначе
  /// кнопка так и предлагала бы «отправить исправленное», когда исправлять
  /// заново нечего.
  late Map<String, double> _originalQuantities = _quantitiesOf(_lines);

  static Map<String, double> _quantitiesOf(List<ConsumptionLine> lines) => {
        for (final line in lines) line.sparePartUuid: line.quantity,
      };

  /// Расход изменён — значит отправлять надо исправленный, а не тот же самый.
  bool get _hasChanges {
    if (_lines.length != _originalQuantities.length) return true;
    for (final line in _lines) {
      final original = _originalQuantities[line.sparePartUuid];
      if (original == null || original != line.quantity) return true;
    }
    return false;
  }

  /// Правку предлагаем только при нехватке на складе — единственном отказе,
  /// который обходчик может устранить сам, уменьшив количества. У остальных
  /// причин («задача не найдена», «нет доступа») расход ни при чём, и
  /// редактируемый блок только сбивал бы с толку.
  ///
  /// Пустой список правку не отключает: убрав последнюю позицию, обходчик
  /// иначе остался бы без кнопки «Добавить позицию» и не смог бы вернуть её
  /// обратно.
  bool get _canEditConsumption => _isStockShortage;

  @override
  void initState() {
    super.initState();
    // Каталог нужен окну выбора позиции: без него «Добавить позицию» открыло
    // бы пустой список. Не ждём — экран рисуется по данным самого осмотра, а
    // каталог понадобится только если обходчик полезет добавлять строку.
    GlobalState.dataProvider.ensureSparePartsLoaded();
  }

  /// Осмотр перечитываем из очереди, а не держим переданный объект.
  ///
  /// После повтора отправки сервер мог отказать заново и с другой причиной —
  /// с копией из аргумента экран показывал бы прежнюю. Если записи в боксе
  /// уже нет (уехала), откатываемся на переданную: экран в этот момент как
  /// раз закрывается, и рисовать пустоту не нужно.
  Scan get _scan =>
      GlobalState.dataProvider.scanBox.get(widget.scan.key()) ?? widget.scan;

  /// Причину прогоняем через словарь переводов: в очереди могла остаться
  /// английская строка сервера, записанная прежней версией приложения.
  String get _reason => scanStoredReason(_scan.lastError);

  /// Отказ именно из-за остатков — тогда показываем, чего и сколько не хватает.
  ///
  /// Признаком считаем наличие серверного списка нехватки; текст проверяем
  /// только как запасной вариант — для осмотров, отклонённых до того, как
  /// бэкенд начал отдавать `shortages`.
  bool get _isStockShortage =>
      (_scan.lastShortages ?? '').isNotEmpty ||
      _reason == ScanQueueStrings.errorInsufficientStock;

  /// Названия позиций, сохранённые вместе с осмотром. Разбираем один раз на
  /// построение экрана: список короткий, а обращений к нему несколько.
  late final Map<String, String> _names = _parseNames();

  Map<String, String> _parseNames() {
    final raw = _scan.consumptionNames;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      // Строку писало само приложение — сюда можно попасть только при
      // повреждении базы. Экран должен остаться рабочим.
      return const {};
    }
  }

  String? _storedName(String uuid) {
    final name = _names[uuid];
    return (name == null || name.isEmpty) ? null : name;
  }

  String _equipmentName() {
    final uuid = _scan.equipmentUuid;
    if (uuid != null && uuid.isNotEmpty) {
      for (final record in GlobalState.dataProvider.inventoryRecords) {
        if (record.uuid == uuid) return record.name;
      }
    }
    return ScanQueueStrings.rejectedUnknownEquipment;
  }

  /// Позиции расхода из осмотра. В очереди они лежат строкой JSON — ровно той,
  /// что уходит на сервер, — поэтому названия и остатки подтягиваем из
  /// локального справочника ЗИП по uuid.
  List<ConsumptionLine> _consumptionsFromScan() {
    final raw = _scan.actualConsumptions;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            () {
              final uuid = item['spare_part_uuid'] as String? ?? '';
              final part = GlobalState.dataProvider.sparePartByUuid(uuid);
              return ConsumptionLine(
                sparePartUuid: uuid,
                // Сохранённое имя — первым: справочник мог потерять позицию,
                // если её удалили на сервере, а отказ «на складе 0» ровно об
                // этом обычно и говорит.
                sparePartName: _storedName(uuid) ?? part?.name ?? uuid,
                unitName:
                    (part?.unitLabel ?? '').isEmpty ? null : part!.unitLabel,
                quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
              );
            }(),
      ];
    } catch (_) {
      // Строку собирало само приложение, так что сюда попасть можно только
      // при повреждении базы. Экран должен остаться рабочим: кнопки
      // «повторить» и «удалить» важнее списка позиций.
      return const [];
    }
  }

  /// Чего не хватает: позиция, сколько нужно, сколько есть.
  ///
  /// Числа берём **от сервера** (`shortages` из ответа 409) — он единственный
  /// знает остаток на момент отказа. Названия и единицы подставляем из
  /// локального справочника: в отказе их нет, только uuid.
  ///
  /// Запасной путь — расчёт по локальному справочнику. Нужен для осмотров,
  /// отклонённых до появления серверного формата, и на случай, если тело
  /// отказа пришло без `shortages`. Он менее точен: справочник между
  /// синхронизациями отстаёт.
  List<(String, double, double, String)> _shortages(
    List<ConsumptionLine> consumptions,
  ) {
    final fromServer = _serverShortages(consumptions);
    if (fromServer != null) return fromServer;

    final result = <(String, double, double, String)>[];
    for (final line in consumptions) {
      final part = GlobalState.dataProvider.sparePartByUuid(line.sparePartUuid);
      final available = part?.quantity ?? 0;
      if (line.quantity > available) {
        result.add((
          line.sparePartName,
          line.quantity,
          available,
          part?.unitLabel ?? '',
        ));
      }
    }
    return result;
  }

  /// Нехватка по данным сервера. `null` — их нет, считаем сами.
  List<(String, double, double, String)>? _serverShortages(
    List<ConsumptionLine> consumptions,
  ) {
    final raw = _scan.lastShortages;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final names = {
        for (final line in consumptions) line.sparePartUuid: line,
      };
      final rows = <(String, double, double, String)>[
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            () {
              final parsed = InsufficientStockItem.fromJson(item);
              final line = names[parsed.sparePartUuid];
              final part = GlobalState.dataProvider
                  .sparePartByUuid(parsed.sparePartUuid);
              return (
                // Название сервера — первым: оно взято из той же записи
                // склада, по которой он и посчитал нехватку, и приезжает
                // вместе с отказом. Остальные источники остаются запасными:
                // у отказов старого формата поля нет, и сервер может прислать
                // `null`, если позицию удалили между проверкой и ответом.
                parsed.sparePartName.isNotEmpty
                    ? parsed.sparePartName
                    : line?.sparePartName ??
                        _storedName(parsed.sparePartUuid) ??
                        part?.name ??
                        parsed.sparePartUuid,
                // «Нужно» — из текущего списка, а не из отказа: обходчик правит
                // количества прямо здесь, и блок обязан показывать то, что он
                // набрал сейчас. Позиции, которой в списке уже нет, оставляем
                // серверное число — иначе строку нечем подписать.
                line?.quantity ?? parsed.required,
                // «Есть» — только серверное: локальный справочник между
                // синхронизациями отстаёт, а это то самое число, из-за
                // которого отказали.
                parsed.available,
                line?.unitName ?? part?.unitLabel ?? '',
              );
            }(),
      ];
      // Позиции, которых уже хватает, из блока убираем: обходчик уменьшил
      // количество — строка про нехватку обязана исчезнуть, иначе непонятно,
      // что ещё осталось поправить.
      return [
        for (final row in rows)
          if (row.$2 > row.$3) row,
      ];
    } catch (_) {
      return null;
    }
  }

  /// Остатки на складе по uuid — так, как их назвал сервер в отказе.
  ///
  /// Сопоставлять по uuid, а не по названию: названия у позиций повторяются, и
  /// склеить две разные строки расхода в одну было бы легко. Пустая карта —
  /// сервер чисел не прислал, тогда остаток берётся из локального справочника.
  Map<String, double> get _availableByUuid {
    final raw = _scan.lastShortages;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            InsufficientStockItem.fromJson(item).sparePartUuid:
                InsufficientStockItem.fromJson(item).available,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Сколько этой позиции есть на складе. Если сервер про неё не сказал —
  /// считаем, что хватает: трогать такую строку незачем.
  double _availableFor(ConsumptionLine line, Map<String, double> available) {
    final fromServer = available[line.sparePartUuid];
    if (fromServer != null) return fromServer;
    if (available.isNotEmpty) return line.quantity;
    return GlobalState.dataProvider
            .sparePartByUuid(line.sparePartUuid)
            ?.quantity ??
        line.quantity;
  }

  String _shortageText(List<(String, double, double, String)> shortages) {
    return [
      _equipmentName(),
      for (final item in shortages)
        ScanConflictStrings.needShortage(
          item.$1,
          _withUnit(item.$2, item.$4),
          _withUnit(item.$3, item.$4),
        ),
    ].join('\n');
  }

  static String _withUnit(double value, String unit) {
    final formatted = formatConsumptionQuantity(value);
    return unit.isEmpty ? formatted : '$formatted $unit';
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(ScanConflictStrings.copied)),
    );
  }

  // ── правка расхода ────────────────────────────────────────────────────

  void _changeQuantity(int index, double delta) {
    final next = _lines[index].quantity + delta;
    if (next <= 0) return;
    _setQuantity(index, next);
  }

  /// Ноль и отрицательные не принимаем — как и в форме осмотра: позиция с
  /// нулём не списалась бы, а в списке выглядела бы заполненной. Убрать
  /// позицию совсем можно корзиной.
  ///
  /// Округление до четырёх знаков — то же, что в карточке ремонта и в форме
  /// осмотра, и по той же причине: шаг счётчика для дробного количества равен
  /// 0,1, а `0.25 - 0.1` в double даёт `0.15000000000000002`. Без округления
  /// это число и печаталось бы на экране, и уходило бы на сервер — причём
  /// именно здесь, где количества правят чаще всего: экран открывается после
  /// отказа по нехватке ЗИП.
  void _setQuantity(int index, double value) {
    value = roundConsumptionQuantity(value);
    if (value <= 0) return;
    final item = _lines[index];
    if (item.quantity == value) return;
    setState(() {
      _lines = [..._lines];
      _lines[index] = ConsumptionLine(
        sparePartUuid: item.sparePartUuid,
        sparePartName: item.sparePartName,
        unitName: item.unitName,
        quantity: value,
        normQuantity: item.normQuantity,
      );
    });
  }

  void _removePosition(int index) {
    setState(() => _lines = [..._lines]..removeAt(index));
  }

  Future<void> _addPosition() async {
    final picked = await showSparePartPicker(
      context,
      alreadyAddedUuids: _lines.map((item) => item.sparePartUuid).toSet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lines = [
        ..._lines,
        ConsumptionLine(
          sparePartUuid: picked.uuid,
          sparePartName: picked.name,
          unitName: picked.unitLabel.isEmpty ? null : picked.unitLabel,
          quantity: 1,
        ),
      ];
    });
  }

  /// Уменьшает всё, чего не хватает, до остатка на складе.
  ///
  /// Числа берём те же, что показаны в списке нехватки, — серверные, если они
  /// пришли с отказом. Нажать одну кнопку вместо перебора счётчиков: обычно
  /// обходчику и нужно ровно это — списать столько, сколько на складе есть.
  ///
  /// Позиции с нулевым остатком убираем: списывать нечего, а строка с нулём на
  /// сервер всё равно не уйдёт.
  void _reduceToAvailable() {
    final available = _availableByUuid;
    final reduced = <ConsumptionLine>[];
    for (final line in _lines) {
      // Остаток считаем один раз на строку: в списочном литерале он выходил
      // трижды — в условии и в обеих ветках тернарника.
      final left = _availableFor(line, available);
      // Нулевой остаток — позицию убираем целиком: списывать нечего, а строка
      // с нулём на сервер всё равно не уйдёт.
      if (left <= 0) continue;
      reduced.add(
        line.quantity <= left
            ? line
            : ConsumptionLine(
                sparePartUuid: line.sparePartUuid,
                sparePartName: line.sparePartName,
                unitName: line.unitName,
                quantity: left,
                normQuantity: line.normQuantity,
              ),
      );
    }
    setState(() => _lines = reduced);
  }

  /// Есть ли что уменьшать — иначе кнопка бессмысленна.
  bool get _canReduce {
    final available = _availableByUuid;
    for (final line in _lines) {
      if (line.quantity > _availableFor(line, available)) return true;
    }
    return false;
  }

  /// Отправляет исправленный расход: переписывает позиции в очереди и снимает
  /// отметку об отказе.
  Future<void> _sendEdited() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final kept = _lines.where((line) => line.quantity > 0).toList();
    await GlobalState.dataProvider.retryRejectedScanWithConsumption(
      widget.scan.key(),
      // Пустой список нельзя отправлять строкой: сервер разбирает поле как
      // JSON и на пустом значении списание не выполнит, а прежние позиции
      // сотрёт. `null` означает «поля в запросе нет».
      actualConsumptions: kept.isEmpty
          ? null
          : jsonEncode([
              for (final line in kept)
                {
                  'spare_part_uuid': line.sparePartUuid,
                  'quantity': line.quantity,
                },
            ]),
      consumptionNames: kept.isEmpty
          ? null
          : jsonEncode({
              for (final line in kept) line.sparePartUuid: line.sparePartName,
            }),
    );
    if (!mounted) return;
    _closeIfSettled();
  }

  /// Повтор отправки: снимаем отметку об отказе, и очередь берёт осмотр снова.
  ///
  /// Осмысленно ровно после того, как администратор пополнил склад. Если он
  /// этого не сделал, сервер откажет тем же текстом, и экран откроется опять.
  Future<void> _retry() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    await GlobalState.dataProvider.retryRejectedScan(widget.scan.key());
    if (!mounted) return;
    _closeIfSettled();
  }

  /// Закрываем экран, только когда разбирать больше нечего: осмотр уехал либо
  /// ждёт связи в очереди. Если сервер отказал снова — остаёмся здесь и
  /// показываем свежую причину. Раньше экран закрывался всегда, и повторный
  /// отказ обходчик находил заново в списке, уже без связи с нажатием.
  ///
  /// После правки расхода перечитываем и сами позиции: сервер мог отказать
  /// снова, и в списке нехватки должны стоять уже исправленные количества.
  void _closeIfSettled() {
    final left = GlobalState.dataProvider.scanBox.get(widget.scan.key());
    if (left == null || !left.isRejected) {
      _close();
      return;
    }
    setState(() {
      _isBusy = false;
      _lines = _consumptionsFromScan();
      _originalQuantities = _quantitiesOf(_lines);
    });
  }

  Future<void> _delete() async {
    if (_isBusy) return;
    // Тот же диалог, что у черновика ремонта: значок в красном квадрате,
    // заголовок, что пропадёт, плашка с необратимостью и две кнопки.
    final confirmed = await confirmRepairDelete(
      context,
      title: ScanConflictStrings.deleteTitle,
      body: ScanConflictStrings.deleteBody,
      note: RepairStrings.deleteIrreversible,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isBusy = true);
    await GlobalState.dataProvider.deleteRejectedScan(_scan.key());
    if (!mounted) return;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Нехватку считаем по правленому списку: обходчик уменьшает количества
    // прямо здесь, и блок «чего не хватает» обязан гаснуть по мере правки —
    // иначе непонятно, достаточно ли уже исправлено.
    final shortages = _isStockShortage
        ? _shortages(_lines)
        : const <(String, double, double, String)>[];

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: const Text(ScanConflictStrings.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingXL,
        ),
        children: [
          _Label(ScanConflictStrings.reasonLabel),
          const SizedBox(height: AppConstants.spacingSM),
          // Без значка и по центру — как все полосы-пояснения в приложении:
          // значок повторял бы подпись «ПРИЧИНА ОТКАЗА», стоящую прямо над
          // ним, а прижатый влево текст оставлял справа пустое поле.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Text(
              _reason,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.error),
            ),
          ),

          // Что просить у администратора. Блок только при нехватке остатков:
          // на прочих отказах пополнять нечего.
          if (shortages.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingLG),
            _Label(ScanConflictStrings.shortageLabel),
            const SizedBox(height: AppConstants.spacingSM),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              decoration: BoxDecoration(
                color: cs.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ScanConflictStrings.askAdminTitle,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ScanConflictStrings.askAdminBody,
                    style: tt.bodySmall?.copyWith(color: cs.warning),
                  ),
                  // Список отделён от обращения к администратору: выше —
                  // что делать, ниже — что именно просить. Слитно они
                  // читались как один абзац, и позиции терялись.
                  const SizedBox(height: AppConstants.spacingMD),
                  Divider(
                    height: 1,
                    color: cs.warning.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: AppConstants.spacingMD),
                  Text(
                    ScanConflictStrings.shortageListLabel,
                    style: tt.bodySmall?.copyWith(color: cs.warning),
                  ),
                  const SizedBox(height: AppConstants.spacingXS),
                  for (final item in shortages)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppConstants.spacingXS),
                      child: Text(
                        ScanConflictStrings.needShortage(
                          item.$1,
                          _withUnit(item.$2, item.$4),
                          _withUnit(item.$3, item.$4),
                        ),
                        style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                      ),
                    ),
                  const SizedBox(height: AppConstants.spacingSM),
                  // Кнопка та же, что на карточке черновика: во всю ширину,
                  // обводкой, значок чёрным.
                  SizedBox(
                    width: double.infinity,
                    height: AppConstants.buttonHeight,
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(_shortageText(shortages)),
                      icon: Icon(Icons.copy_rounded,
                          size: 20, color: cs.onSurface),
                      label: const Text(ScanConflictStrings.copy),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: AppConstants.spacingMD),
            Text(
              ScanConflictStrings.genericHint,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],

          const SizedBox(height: AppConstants.spacingLG),
          _Label(ScanConflictStrings.dataLabel),
          const SizedBox(height: AppConstants.spacingSM),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              border: Border.all(color: cs.outlineVariant, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Подписи полей — теми же прописными, что секции карточки
                // ремонта: блок читается как её слепок, а не как отдельный
                // стиль внутри одного приложения.
                Text(_equipmentName(), style: tt.titleMedium),
                const SizedBox(height: AppConstants.spacingMD),
                _Label(ScanConflictStrings.commentLabel),
                const SizedBox(height: AppConstants.spacingXS),
                Text(
                  (_scan.comment ?? '').trim().isEmpty
                      ? ScanConflictStrings.noComment
                      : _scan.comment!.trim(),
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: AppConstants.spacingMD),
                _Label(ScanConflictStrings.consumptionLabel),
                const SizedBox(height: AppConstants.spacingXS),
                // При нехватке на складе расход не показываем, а даём править:
                // это единственный отказ, который обходчик устраняет сам,
                // уменьшив количества до того, что на складе есть. Остальные
                // причины к расходу отношения не имеют — там он остаётся
                // справкой, простым текстом.
                if (_canEditConsumption)
                  SparePartConsumptionSection(
                    lines: _lines,
                    editable: !_isBusy,
                    // Плана у осмотра в очереди нет: он приходит с задачей, а
                    // не с осмотром. Значит и сравнивать не с чем — без нормы
                    // счётчик превышений всегда нулевой.
                    hasNorm: false,
                    canFillFromNorm: false,
                    // Остатки в справочнике отстают от серверных, а точные
                    // числа уже показаны выше отдельным блоком — вторая,
                    // менее точная тревога рядом только путала бы.
                    showStockWarnings: false,
                    writeOffNote: InspectionConsumptionStrings.writeOffNote,
                    emptyNote: ScanConflictStrings.noConsumption,
                    onAdd: _addPosition,
                    onFillFromNorm: () {},
                    onChangeQuantity: _changeQuantity,
                    onSetQuantity: _setQuantity,
                    onRemove: _removePosition,
                    // Место кнопки нормы занимает «Уменьшить до остатка»:
                    // нормы у осмотра в очереди нет, а действие тут ровно того
                    // же порядка — второе после «Добавить позицию». Гаснет,
                    // когда уменьшать нечего, — как и кнопка нормы, когда
                    // добавлять уже нечего.
                    secondaryAction: ConsumptionSecondaryAction(
                      icon: Icons.south_rounded,
                      label: ScanConflictStrings.reduceToAvailable,
                      onPressed:
                          _isBusy || !_canReduce ? null : _reduceToAvailable,
                    ),
                  )
                else if (_lines.isEmpty)
                  Text(ScanConflictStrings.noConsumption, style: tt.bodyMedium)
                else
                  for (final line in _lines)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppConstants.spacingXS),
                      child: Text(
                        ScanConflictStrings.position(
                          line.sparePartName,
                          _withUnit(line.quantity, line.unitName ?? ''),
                        ),
                        style: tt.bodyMedium,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                width: double.infinity,
                // Правил расход — отправляем исправленное, не правил —
                // повторяем прежнее. Разные действия и подписаны по-разному:
                // повтор без правки при неизменившемся складе даст тот же
                // отказ, и обходчик должен это понимать до нажатия.
                child: ElevatedButton.icon(
                  onPressed:
                      _isBusy ? null : (_hasChanges ? _sendEdited : _retry),
                  icon: Icon(
                    _hasChanges ? Icons.check_rounded : Icons.refresh_rounded,
                  ),
                  label: Text(
                    _hasChanges
                        ? ScanConflictStrings.retryEdited
                        : ScanConflictStrings.retry,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingSM),
              // Заливкой, а не текстом: удаление необратимо, и рядом с
              // зелёной «Повторить отправку» бледная надпись читалась как
              // второстепенная ссылка, а не как опасное действие.
              SizedBox(
                height: AppConstants.buttonHeight,
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: _isBusy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text(ScanConflictStrings.delete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Секционная подпись формы: прописными, с разрядкой — как `_SectionLabel`
/// на экране результата скана.
class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Text(
      text,
      style: tt.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
