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
  List<ConsumptionLine> _consumptions() {
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
                sparePartName: part?.name ?? uuid,
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
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            () {
              final parsed = InsufficientStockItem.fromJson(item);
              final line = names[parsed.sparePartUuid];
              final part = GlobalState.dataProvider
                  .sparePartByUuid(parsed.sparePartUuid);
              return (
                line?.sparePartName ?? part?.name ?? parsed.sparePartUuid,
                parsed.required,
                parsed.available,
                line?.unitName ?? part?.unitLabel ?? '',
              );
            }(),
      ];
    } catch (_) {
      return null;
    }
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

  /// Повтор отправки: снимаем отметку об отказе, и очередь берёт осмотр снова.
  ///
  /// Осмысленно ровно после того, как администратор пополнил склад. Если он
  /// этого не сделал, сервер откажет тем же текстом, и экран откроется опять.
  Future<void> _retry() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    await GlobalState.dataProvider.retryRejectedScan(widget.scan.key());
    if (!mounted) return;
    // Экран закрываем только когда разбирать больше нечего: осмотр уехал либо
    // ждёт связи в очереди. Если сервер отказал снова — остаёмся здесь и
    // показываем свежую причину. Раньше экран закрывался всегда, и повторный
    // отказ обходчик находил заново в списке, уже без связи с нажатием.
    final left = GlobalState.dataProvider.scanBox.get(widget.scan.key());
    if (left == null || !left.isRejected) {
      _close();
      return;
    }
    setState(() => _isBusy = false);
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
    final consumptions = _consumptions();
    final shortages = _isStockShortage
        ? _shortages(consumptions)
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
                if (consumptions.isEmpty)
                  Text(ScanConflictStrings.noConsumption, style: tt.bodyMedium)
                else
                  for (final line in consumptions)
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
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(ScanConflictStrings.retry),
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
