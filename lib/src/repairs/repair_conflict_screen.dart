import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
// Импорт библиотеки целиком, а не part-файла: transferDraftToRepair и
// retryPendingRepairUpdate объявлены в extension DataProviderOutbox.
import '../../strings.dart';
import '../data/data_provider.dart';
import '../design/app_constants.dart';
import '../model/pending_repair.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../model/repair_conflict.dart';
import '../utils/go_router_ext.dart';
import '../widgets/spare_part_row.dart';
import 'repair_status_pill.dart';

/// Экран разрешения конфликта при отправке — по макету «Рисунок 13».
///
/// Открывается на два разных отказа, и оба выглядят одинаково по строению:
/// красная плашка с причиной, карточка «Ваши данные», при наличии — карточка
/// того ремонта, который помешал, и липкая пара кнопок внизу.
///
/// Различаются только действия, и различает их [RepairConflictKind]:
/// * оборудование занято **моим** ремонтом — можно перенести данные в него;
/// * занято чужим, ремонт закрыт или передан другому — переносить нечего и
///   некуда, остаётся скопировать введённое и удалить.
///
/// Автоматически здесь не удаляется ничего: пока обходчик не нажал кнопку,
/// его данные лежат на устройстве.
class RepairConflictScreen extends StatefulWidget {
  /// Черновик создания, который сервер отклонил. Взаимоисключим с [update].
  final PendingRepair? draft;

  /// Отклонённая правка существующего ремонта.
  final PendingRepairUpdate? update;

  const RepairConflictScreen({super.key, this.draft, this.update});

  @override
  State<RepairConflictScreen> createState() => _RepairConflictScreenState();
}

class _RepairConflictScreenState extends State<RepairConflictScreen> {
  bool _isBusy = false;

  PendingRepair? get _draft => widget.draft;

  PendingRepairUpdate? get _update => widget.update;

  /// Ремонт, помешавший отправке: для черновика — занявший оборудование, для
  /// правки — тот самый, который правили.
  Repair? get _blocking {
    final uuid = _draft?.conflictRepairUuid ?? _update?.repairUuid;
    if (uuid == null) return null;
    for (final repair in GlobalState.dataProvider.repairs) {
      if (repair.uuid == uuid) return repair;
    }
    return null;
  }

  /// Вид конфликта. У правки он определён очередью в момент отказа, у
  /// черновика выводится из того, чей ремонт занял оборудование: сервер
  /// сообщает только сам факт занятости.
  RepairConflictKind get _kind {
    final update = _update;
    if (update != null) return update.kind;
    final blocking = _blocking;
    if (blocking == null) {
      // Ремонт не нашёлся в доступных обходчику — значит он чужой.
      return RepairConflictKind.equipmentBusyOther;
    }
    final me = GlobalState.authUser?.uuid;
    final owner = blocking.responsibleUserUuid;
    final mine = me != null && owner != null && owner.isNotEmpty && owner == me;
    return mine
        ? RepairConflictKind.equipmentBusyMine
        : RepairConflictKind.equipmentBusyOther;
  }

  String get _reason =>
      _draft?.lastError ?? _update?.lastError ?? ConflictStrings.defaultReason;

  String get _comment => _draft?.comment ?? _update?.comment ?? '';

  List<RepairConsumption> get _consumptions =>
      _draft?.consumptions ?? _update?.consumptions ?? const [];

  void _close() {
    // Экран открывают из списка ремонтов и из карточки, но всегда через push,
    // так что возвращаться есть куда. Страховка — на случай прихода по
    // прямой ссылке из уведомления.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.of(context).clearStackAndNavigate('/repairs');
    }
  }

  Future<void> _transfer() async {
    final draft = _draft;
    final target = _blocking;
    if (draft == null || target == null || _isBusy) return;
    setState(() => _isBusy = true);
    await GlobalState.dataProvider.transferDraftToRepair(draft, target);
    if (!mounted) return;
    // Уходим сразу в карточку ремонта, куда перенесли: обходчику дальше
    // работать именно там. Экран конфликта при этом закрываем, а карточку
    // кладём на его место — стек сохраняется, и «назад» из карточки вернёт
    // в список, а не выбросит на главную.
    final router = GoRouter.of(context);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    router.push('/repairs/${target.uuid}');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _plainText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(ConflictStrings.copied),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Текст для буфера обмена: то же, что на экране, только строками — его
  /// пересылают администратору, чтобы он внёс расход руками.
  String _plainText() {
    final update = _update;
    final draft = _draft;
    final lines = <String>[
      if (update != null)
        RepairCardStrings.titleWithId(update.repairId) +
            ' · ${update.equipmentName}'
      else if (draft != null)
        '${ConflictStrings.clipboardNewRepair} · ${draft.equipmentName}',
      if (draft != null)
        '${ConflictStrings.clipboardStartedAt} ${_dateTime(draft.startedAt)}'
      else if (update != null)
        '${ConflictStrings.clipboardChangedAt} ${_dateTime(update.createdAt)}',
      if (_comment.trim().isNotEmpty)
        '${ConflictStrings.clipboardComment} ${_comment.trim()}',
      if (_consumptions.isNotEmpty) ConflictStrings.clipboardConsumption,
      for (final item in _consumptions)
        '  ${item.sparePartName} × ${formatSparePartQuantity(item.quantity)}'
            '${item.unitName == null || item.unitName!.isEmpty ? '' : ' ${item.unitName}'}',
    ];
    return lines.join('\n');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(ConflictStrings.deleteTitle),
        content: const Text(
          ConflictStrings.deleteBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(RepairStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(RepairStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final draft = _draft;
    if (draft != null) {
      await GlobalState.dataProvider.deletePendingRepair(draft.localId);
    } else if (_update != null) {
      await GlobalState.dataProvider
          .deletePendingRepairUpdate(_update!.repairUuid);
    }
    if (!mounted) return;
    _close();
  }

  Future<void> _retry() async {
    final update = _update;
    final draft = _draft;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    if (update != null) {
      await GlobalState.dataProvider
          .retryPendingRepairUpdate(update.repairUuid);
    } else if (draft != null) {
      await GlobalState.dataProvider.retryPendingRepair(draft.localId);
    }
    if (!mounted) return;
    setState(() => _isBusy = false);
    // Уехало — очереди больше нечего показывать, конфликта нет.
    final stillQueued = update != null
        ? GlobalState.dataProvider.pendingUpdateFor(update.repairUuid) != null
        : GlobalState.dataProvider.pendingRepairs
            .any((item) => item.localId == draft?.localId);
    if (!stillQueued) _close();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocking = _blocking;
    final kind = _kind;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: ConflictStrings.close,
          onPressed: _close,
        ),
        title: const Text(ConflictStrings.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingXL,
        ),
        children: [
          _ReasonBanner(text: _reason),
          const SizedBox(height: AppConstants.spacingMD),
          _MyDataCard(
            badge: _draft != null
                ? ConflictStrings.badgeDraft
                : ConflictStrings.badgeUnsent,
            timestampLabel: _draft != null
                ? ConflictStrings.stampCreated
                : ConflictStrings.stampChanged,
            timestamp: _dateTime(_draft?.startedAt ?? _update!.createdAt),
            comment: _comment,
            consumptions: _consumptions,
          ),
          // Карточку помешавшего ремонта показываем только когда есть что
          // показать: чужой ремонт обходчику не отдают, и выдумывать его
          // содержимое нельзя.
          if (_draft != null && blocking != null) ...[
            const SizedBox(height: AppConstants.spacingMD),
            _ExistingRepairCard(repair: blocking),
          ],
          if (_hintFor(kind) != null) ...[
            const SizedBox(height: AppConstants.spacingMD),
            _HintCard(text: _hintFor(kind)!),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeightLarge,
                child: _primaryAction(kind, blocking),
              ),
              const SizedBox(height: AppConstants.spacingSM),
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeightLarge,
                child: _DangerButton(
                  icon: Icons.delete_outline_rounded,
                  label: _draft != null && kind.canTransfer
                      ? ConflictStrings.deleteMyData
                      : RepairStrings.delete,
                  onPressed: _isBusy ? null : _delete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Главная кнопка зависит от вида конфликта: перенести (только в свой
  /// ремонт), повторить (если отказ не окончательный) или скопировать.
  Widget _primaryAction(RepairConflictKind kind, Repair? blocking) {
    if (kind.canTransfer && _draft != null && blocking != null) {
      return ElevatedButton.icon(
        onPressed: _isBusy ? null : _transfer,
        icon: const Icon(Icons.move_down_rounded, size: 20),
        label: Text(ConflictStrings.transferTo(blocking.id)),
      );
    }
    if (!kind.isFinal) {
      return ElevatedButton.icon(
        onPressed: _isBusy ? null : _retry,
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text(ConflictStrings.retry),
      );
    }
    return ElevatedButton.icon(
      onPressed: _isBusy ? null : _copy,
      icon: const Icon(Icons.copy_rounded, size: 20),
      label: const Text(ConflictStrings.copyToClipboard),
    );
  }

  /// Серая подсказка под карточками — объясняет, что делать дальше, когда
  /// отправить уже нельзя.
  String? _hintFor(RepairConflictKind kind) {
    switch (kind) {
      case RepairConflictKind.equipmentBusyMine:
        return null;
      case RepairConflictKind.equipmentBusyOther:
        return ConflictStrings.hintBusyOther;
      case RepairConflictKind.repairClosed:
        return ConflictStrings.hintClosed;
      case RepairConflictKind.repairReassigned:
        return ConflictStrings.hintReassigned;
      case RepairConflictKind.other:
        return null;
    }
  }
}

String _dateTime(DateTime value) =>
    DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());

// ─────────────────────────────────────────────────────────────────────────
// Части экрана
// ─────────────────────────────────────────────────────────────────────────

/// Красная плашка с причиной отказа — первое, что читает обходчик.
class _ReasonBanner extends StatelessWidget {
  final String text;

  const _ReasonBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 22, color: cs.error),
          const SizedBox(width: AppConstants.spacingMD),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка «Ваши данные»: заголовок с пилюлей, время, комментарий и список
/// позиций расхода — по макету.
class _MyDataCard extends StatelessWidget {
  final String badge;
  final String timestampLabel;
  final String timestamp;
  final String comment;
  final List<RepairConsumption> consumptions;

  const _MyDataCard({
    required this.badge,
    required this.timestampLabel,
    required this.timestamp,
    required this.comment,
    required this.consumptions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _ConflictCard(
      title: ConflictStrings.myDataTitle,
      badge: _NeutralPill(badge),
      subtitle: '$timestampLabel $timestamp',
      children: [
        if (comment.trim().isNotEmpty)
          Text(comment.trim(), style: tt.bodyLarge)
        else
          Text(
            ConflictStrings.commentEmpty,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (consumptions.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spacingMD),
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
          const SizedBox(height: AppConstants.spacingMD),
          for (final item in consumptions) _ConsumptionLine(item: item),
        ],
      ],
    );
  }
}

/// Карточка ремонта, занявшего оборудование.
class _ExistingRepairCard extends StatelessWidget {
  final Repair repair;

  const _ExistingRepairCard({required this.repair});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final started =
        DateFormat('dd.MM.yyyy, HH:mm').format(repair.startedAt.toLocal());
    final owner = repair.responsibleUserFullname;

    return _ConflictCard(
      title: ConflictStrings.existingRepair(repair.id),
      badge: RepairStatusPill(status: repair.status, compact: true),
      subtitle: owner == null || owner.isEmpty
          ? ConflictStrings.startedAt(started)
          : ConflictStrings.startedAtBy(started, owner),
      children: [
        if (repair.actualConsumptions.isEmpty)
          Text(
            ConflictStrings.consumptionEmpty,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          for (final item in repair.actualConsumptions)
            _ConsumptionLine(item: item),
      ],
    );
  }
}

/// Общая рамка карточек экрана: заголовок с пилюлей справа, серая строка
/// времени, разделитель и содержимое.
class _ConflictCard extends StatelessWidget {
  final String title;
  final Widget badge;
  final String subtitle;
  final List<Widget> children;

  const _ConflictCard({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppConstants.spacingSM),
              badge,
            ],
          ),
          const SizedBox(height: AppConstants.spacingXS),
          Text(
            subtitle,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingMD),
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
          const SizedBox(height: AppConstants.spacingMD),
          ...children,
        ],
      ),
    );
  }
}

/// Строка расхода: название слева, «× 2» справа — как в макете.
class _ConsumptionLine extends StatelessWidget {
  final RepairConsumption item;

  const _ConsumptionLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(item.sparePartName, style: tt.bodyLarge)),
          const SizedBox(width: AppConstants.spacingMD),
          Text('×', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(width: AppConstants.spacingSM),
          Text(
            formatSparePartQuantity(item.quantity),
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Серая подсказка со значком — «что делать дальше».
class _HintCard extends StatelessWidget {
  final String text;

  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: AppConstants.spacingMD),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Нейтральная пилюля заголовка — «Черновик» / «Не отправлено».
class _NeutralPill extends StatelessWidget {
  final String label;

  const _NeutralPill(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSM,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Кнопка удаления: бледно-красная заливка и красный текст, как в макете, —
/// заметная, но не такая же весомая, как главное действие.
class _DangerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _DangerButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.error,
        disabledBackgroundColor: cs.errorContainer.withValues(alpha: 0.5),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}
