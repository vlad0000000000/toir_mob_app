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
import '../widgets/spare_part_consumption.dart';

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

  Scan get _scan => widget.scan;

  String get _reason => _scan.lastError ?? ScanQueueStrings.errorGeneric;

  /// Отказ именно из-за остатков — тогда показываем, чего и сколько не хватает.
  ///
  /// Признаком считаем наличие серверного списка нехватки; текст проверяем
  /// только как запасной вариант — для осмотров, отклонённых до того, как
  /// бэкенд начал отдавать `shortages`.
  bool get _isStockShortage =>
      (_scan.lastShortages ?? '').isNotEmpty ||
      _reason.contains('Недостаточно ЗИП на складе');

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
    await GlobalState.dataProvider.retryRejectedScan(_scan.key());
    if (!mounted) return;
    _close();
  }

  Future<void> _delete() async {
    if (_isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ScanConflictStrings.deleteTitle),
        content: const Text(ScanConflictStrings.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(RepairStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(RepairStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                const SizedBox(width: AppConstants.spacingSM),
                Expanded(
                  child: Text(
                    _reason,
                    style: tt.bodyMedium?.copyWith(color: cs.error),
                  ),
                ),
              ],
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
                  const SizedBox(height: AppConstants.spacingSM),
                  for (final item in shortages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        ScanConflictStrings.needShortage(
                          item.$1,
                          _withUnit(item.$2, item.$4),
                          _withUnit(item.$3, item.$4),
                        ),
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppConstants.spacingSM),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _copy(_shortageText(shortages)),
                      icon: const Icon(Icons.copy_rounded, size: 20),
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
                Text(_equipmentName(), style: tt.titleMedium),
                const SizedBox(height: AppConstants.spacingSM),
                Text(
                  ScanConflictStrings.commentLabel,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  (_scan.comment ?? '').trim().isEmpty
                      ? ScanConflictStrings.noComment
                      : _scan.comment!.trim(),
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: AppConstants.spacingSM),
                Text(
                  ScanConflictStrings.consumptionLabel,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (consumptions.isEmpty)
                  Text(ScanConflictStrings.noConsumption, style: tt.bodyMedium)
                else
                  for (final line in consumptions)
                    Text(
                      ScanConflictStrings.position(
                        line.sparePartName,
                        _withUnit(line.quantity, line.unitName ?? ''),
                      ),
                      style: tt.bodyMedium,
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
              SizedBox(
                height: AppConstants.buttonHeight,
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isBusy ? null : _delete,
                  icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                  label: Text(
                    ScanConflictStrings.delete,
                    style: tt.labelLarge?.copyWith(color: cs.error),
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
