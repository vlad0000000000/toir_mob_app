import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:image_picker/image_picker.dart';
import 'package:qr_scan_industry/settings.dart';
import '../../global_state.dart';
import '../../src/model/priority.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/usage_unit.dart';
import '../../src/tasks/tasks.dart';
import '../../src/widgets/select_image_button.dart';
import '../../src/widgets/select_task_button.dart';
import '../design/app_constants.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../utils/any_controller.dart';

class ResultControls extends StatefulWidget {
  final TextEditingController descController;
  final SelectImageButtonController imageData1Controller;
  final SelectImageButtonController imageData2Controller;
  final SelectImageButtonController imageData3Controller;
  final AnyController<Priority> priorityController;
  final AnyController<TypicalProblem> problemController;
  final EquipmentDetailController equipmentDetailController;
  final AnyController<List<UsageUpdate>> usageController;
  final InventoryRecord machine;
  final bool highlightDescError;
  final bool highlightPriorityError;

  const ResultControls({
    super.key,
    required this.descController,
    required this.imageData1Controller,
    required this.imageData2Controller,
    required this.imageData3Controller,
    required this.priorityController,
    required this.problemController,
    required this.machine,
    required this.equipmentDetailController,
    required this.usageController,
    this.highlightDescError = false,
    this.highlightPriorityError = false,
  });

  @override
  State<ResultControls> createState() => _ResultControlsState();
}

class _ResultControlsState extends State<ResultControls> {
  bool firstPaint = true;

  void _onValueChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.problemController.valueNotifier.addListener(_onValueChanged);
    widget.priorityController.valueNotifier.addListener(_onValueChanged);
    widget.equipmentDetailController.valueNotifier
        .addListener(_onValueChanged);
  }

  @override
  void dispose() {
    widget.problemController.valueNotifier.removeListener(_onValueChanged);
    widget.priorityController.valueNotifier.removeListener(_onValueChanged);
    widget.equipmentDetailController.valueNotifier
        .removeListener(_onValueChanged);
    super.dispose();
  }

  List<UsageParameter> get _matchingUsage {
    final role = GlobalState.authUser?.effectiveRole;
    return widget.machine.usageParameters
        .where((p) => p.maintenanceRole?.name == role)
        .toList();
  }

  bool get _hasMachineTasks {
    return GlobalState.dataProvider
        .getTasksForMachine(widget.machine.uuid)
        .isNotEmpty;
  }

  Future<void> _pickProblem() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final problems = [
      TypicalProblem.empty,
      ...GlobalState.dataProvider
          .getTypicalProblemsForMachine(widget.machine.uuid),
      TypicalProblem.other,
    ];
    final selected = await showModalBottomSheet<TypicalProblem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ВЫБЕРИТЕ ПРОБЛЕМУ',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: problems.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final p = problems[i];
                      final isCurrent =
                          widget.problemController.value == p ||
                              (widget.problemController.value == null &&
                                  p == TypicalProblem.empty);
                      final isOther = p == TypicalProblem.other;
                      final isEmpty = p == TypicalProblem.empty;
                      return ListTile(
                        leading: Icon(
                          isEmpty
                              ? Icons.remove_circle_outline_rounded
                              : isOther
                                  ? Icons.add_circle_outline_rounded
                                  : Icons.warning_amber_rounded,
                          color: isOther
                              ? cs.error
                              : isEmpty
                                  ? cs.onSurfaceVariant
                                  : cs.primary,
                        ),
                        title: Text(p.title),
                        trailing: isCurrent
                            ? Icon(Icons.check_rounded, color: cs.primary)
                            : null,
                        onTap: () => Navigator.of(ctx).pop(p),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    widget.problemController.value =
        selected == TypicalProblem.empty ? null : selected;
  }

  Future<void> _pickPriority() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final current = widget.priorityController.value;
    final selected = await showModalBottomSheet<Priority>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ВЫБЕРИТЕ ПРИОРИТЕТ',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final p in Priorities.ALL)
                  ListTile(
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: p.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(p.name as String),
                    trailing: current == p
                        ? Icon(Icons.check_rounded, color: cs.primary)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(p),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) widget.priorityController.value = selected;
  }

  @override
  Widget build(BuildContext context) {
    // Сохраняем поведение «при наличии задач — сразу показать модалку выбора».
    if (Settings.qrResultShowTasksFirst && firstPaint) {
      if (_hasMachineTasks) {
        scheduler.SchedulerBinding.instance.addPostFrameCallback((_) {
          firstPaint = false;
          SelectTaskButton.showModal(
              context, widget.machine, widget.equipmentDetailController);
        });
      }
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final usage = _matchingUsage;
    final selectedTasks = widget.equipmentDetailController.selectedTasks;
    final problem = widget.problemController.value;
    final priority = widget.priorityController.value;
    final showPriority = problem == TypicalProblem.other;

    String taskValue;
    Color? taskAccent;
    if (!_hasMachineTasks) {
      taskValue = 'Нет активных';
    } else if (selectedTasks.isEmpty) {
      taskValue = 'Выбрать';
    } else {
      taskValue = '${selectedTasks.length} выбрано';
      taskAccent = cs.primary;
    }

    String problemValue;
    Color? problemAccent;
    if (problem == null) {
      problemValue = 'Не выбрана';
    } else if (problem == TypicalProblem.other) {
      problemValue = 'Другое';
      problemAccent = cs.error;
    } else {
      problemValue = problem.title;
      problemAccent = cs.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Что сделано ──────────────────────────────────────
          const SizedBox(height: AppConstants.spacingMD),
          _SectionLabel('Что сделано во время обхода'),
          _ActionCard(
            children: [
              _ActionRow(
                icon: Icons.checklist_rounded,
                title: 'Задачи',
                value: taskValue,
                valueColor: taskAccent,
                enabled: _hasMachineTasks,
                onTap: _hasMachineTasks
                    ? () => SelectTaskButton.showModal(
                          context,
                          widget.machine,
                          widget.equipmentDetailController,
                        )
                    : null,
              ),
              _ActionRow(
                icon: Icons.warning_amber_rounded,
                title: 'Проблема',
                value: problemValue,
                valueColor: problemAccent,
                onTap: _pickProblem,
              ),
              if (showPriority)
                _ActionRow(
                  icon: Icons.flag_outlined,
                  title: 'Приоритет',
                  value: priority == null
                      ? 'Не выбран'
                      : priority.name as String,
                  valueColor: priority?.color,
                  error: widget.highlightPriorityError
                      ? 'Укажите приоритет'
                      : null,
                  onTap: _pickPriority,
                ),
            ],
          ),

          // ── Наработка ────────────────────────────────────────
          if (usage.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingMD),
            _SectionLabel(
              'Наработка',
              trailing: _CountChip(
                count: (widget.usageController.value?.length ?? 0),
                total: usage.length,
                label: 'обновлено',
              ),
            ),
            _UsageList(
              machine: widget.machine,
              controller: widget.usageController,
              parameters: usage,
            ),
          ],

          // ── Комментарий ──────────────────────────────────────
          const SizedBox(height: AppConstants.spacingMD),
          _SectionLabel('Комментарий'),
          TextFormField(
            minLines: 3,
            maxLines: 6,
            controller: widget.descController,
            decoration: InputDecoration(
              hintText: 'Опишите состояние, наблюдения или дефекты',
              hintStyle: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              alignLabelWithHint: true,
              errorText: widget.highlightDescError
                  ? 'Укажите комментарий'
                  : null,
            ),
          ),

          // ── Фото ─────────────────────────────────────────────
          const SizedBox(height: AppConstants.spacingMD),
          _SectionLabel(
            'Фото',
            trailing: _CountChip(
              count: [
                widget.imageData1Controller,
                widget.imageData2Controller,
                widget.imageData3Controller,
              ].where((c) => c.value.isNotEmpty).length,
              total: 3,
              label: 'из',
            ),
          ),
          _PhotoStrip(
            controllers: [
              widget.imageData1Controller,
              widget.imageData2Controller,
              widget.imageData3Controller,
            ],
          ),
          const SizedBox(height: AppConstants.spacingMD),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Section helpers
// ════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final int total;
  final String label;
  const _CountChip(
      {required this.count, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final active = count > 0;
    return Text(
      '$count $label $total',
      style: tt.labelSmall?.copyWith(
        color: active ? cs.primary : cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final List<Widget> children;
  const _ActionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        side: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: cs.outlineVariant,
                indent: 52,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final bool enabled;
  final String? error;

  const _ActionRow({
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.onTap,
    this.enabled = true,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final disabled = !enabled || onTap == null;
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: disabled
                      ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: tt.bodyLarge?.copyWith(
                      color: disabled
                          ? cs.onSurface.withValues(alpha: 0.5)
                          : cs.onSurface,
                    ),
                  ),
                ),
                if (value != null) ...[
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: tt.bodyMedium?.copyWith(
                        color: valueColor ?? cs.onSurfaceVariant,
                        fontWeight: valueColor != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (!disabled)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  error!,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Наработка — inline-список со встроенным редактором значения
// ════════════════════════════════════════════════════════════════════

class _UsageList extends StatefulWidget {
  final InventoryRecord machine;
  final AnyController<List<UsageUpdate>> controller;
  final List<UsageParameter> parameters;

  const _UsageList({
    required this.machine,
    required this.controller,
    required this.parameters,
  });

  @override
  State<_UsageList> createState() => _UsageListState();
}

class _UsageListState extends State<_UsageList> {
  final Map<String, TextEditingController> _edit = {};
  final Map<String, String?> _errors = {};
  String? _expanded;

  double? _draftValueFor(UsageParameter p) {
    final list = widget.controller.value;
    if (list == null) return null;
    for (final u in list) {
      if (u.usageParameterUuid == p.uuid) return u.usageParameterValue;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    for (final p in widget.parameters) {
      final tc = TextEditingController();
      final draft = _draftValueFor(p);
      tc.text = (draft ?? p.currentValue).toString();
      _edit[p.uuid] = tc;
    }
  }

  @override
  void dispose() {
    for (final c in _edit.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(UsageParameter p) {
    setState(() {
      _expanded = _expanded == p.uuid ? null : p.uuid;
    });
  }

  void _save(UsageParameter p) {
    final tc = _edit[p.uuid]!;
    final err = p.validate(tc.text, allowCurrentValue: true);
    if (err != null) {
      setState(() => _errors[p.uuid] = err);
      return;
    }
    final v = double.parse(tc.text);
    final list = (widget.controller.value ?? [])
        .where((u) => u.usageParameterUuid != p.uuid)
        .toList();
    if (v != p.currentValue) {
      list.add(UsageUpdate(
        equipmentUuid: widget.machine.uuid,
        usageParameterUuid: p.uuid,
        usageParameterValue: v,
      ));
    }
    widget.controller.value = list;
    setState(() {
      _errors.remove(p.uuid);
      _expanded = null;
    });
  }

  void _reset(UsageParameter p) {
    final tc = _edit[p.uuid]!;
    tc.text = p.currentValue.toString();
    final list = (widget.controller.value ?? [])
        .where((u) => u.usageParameterUuid != p.uuid)
        .toList();
    widget.controller.value = list;
    setState(() {
      _errors.remove(p.uuid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final units = GlobalState.dataProvider.usageUnits.toList();
    final rows = <Widget>[];
    for (final p in widget.parameters) {
      final unit = units.firstWhere(
        (u) => u.value == p.unitType,
        orElse: () => UsageUnit(value: p.unitType, displayName: p.unitType, shortName: ''),
      );
      rows.add(_UsageRow(
        param: p,
        unit: unit,
        edit: _edit[p.uuid]!,
        draft: _draftValueFor(p),
        expanded: _expanded == p.uuid,
        error: _errors[p.uuid],
        onTap: () => _toggle(p),
        onSave: () => _save(p),
        onReset: () => _reset(p),
      ));
    }
    return _ActionCard(children: rows);
  }
}

class _UsageRow extends StatelessWidget {
  final UsageParameter param;
  final UsageUnit unit;
  final TextEditingController edit;
  final double? draft;
  final bool expanded;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final VoidCallback onReset;

  const _UsageRow({
    required this.param,
    required this.unit,
    required this.edit,
    required this.draft,
    required this.expanded,
    required this.error,
    required this.onTap,
    required this.onSave,
    required this.onReset,
  });

  String _format(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final current = _format(param.currentValue);
    final isChanged = draft != null && draft != param.currentValue;
    final short = unit.shortName.isEmpty ? '' : ' ${unit.shortName}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(Icons.speed_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(unit.displayName,
                      style: tt.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (isChanged)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$current →',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      Text('${_format(draft!)}$short',
                          style: tt.bodyMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                else
                  Text('$current$short',
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: !expanded
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacingMD, 0, AppConstants.spacingMD, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Текущее: $current$short',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: edit,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              autofocus: true,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: 'Новое значение',
                                suffixText: unit.shortName,
                                errorText: error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: onSave,
                              child: const Icon(Icons.check_rounded),
                            ),
                          ),
                        ],
                      ),
                      if (isChanged)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TextButton.icon(
                            onPressed: onReset,
                            icon: const Icon(Icons.undo_rounded, size: 16),
                            label: const Text('Сбросить'),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Фото — компактная полоса миниатюр + одна кнопка «+»
// ════════════════════════════════════════════════════════════════════

class _PhotoStrip extends StatefulWidget {
  final List<SelectImageButtonController> controllers;
  const _PhotoStrip({required this.controllers});

  @override
  State<_PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<_PhotoStrip> {
  @override
  void initState() {
    super.initState();
    for (final c in widget.controllers) {
      c.valueNotifier.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.valueNotifier.removeListener(_onChange);
    }
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(SelectImageButtonController target) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 100,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    target.value = base64Encode(bytes);
  }

  void _preview(BuildContext context, SelectImageButtonController c) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.memory(
                  base64Decode(c.value),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    c.value = '';
                    Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Удалить'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final filledCount =
        widget.controllers.where((c) => c.value.isNotEmpty).length;
    final allEmpty = filledCount == 0;

    if (allEmpty) {
      // Большая «+ Добавить фото» — экономнее, чем 3 пустых ячейки.
      return Material(
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        child: InkWell(
          onTap: () => _pick(widget.controllers.first),
          child: SizedBox(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_rounded,
                    color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Добавить фото',
                  style: tt.titleMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 80,
      child: Row(
        children: [
          for (var i = 0; i < widget.controllers.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _PhotoSlot(
                controller: widget.controllers[i],
                onPick: () => _pick(widget.controllers[i]),
                onPreview: () => _preview(context, widget.controllers[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final SelectImageButtonController controller;
  final VoidCallback onPick;
  final VoidCallback onPreview;
  const _PhotoSlot({
    required this.controller,
    required this.onPick,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = controller.value.isNotEmpty;
    return Material(
      color: filled ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: filled ? onPreview : onPick,
        child: filled
            ? Image.memory(
                base64Decode(controller.value),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Icon(Icons.add_a_photo_outlined,
                color: cs.onSurfaceVariant, size: 22),
      ),
    );
  }
}
