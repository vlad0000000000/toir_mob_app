import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import 'package:qr_scan_industry/settings.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/data/data_provider.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/priority.dart';
import '../../src/model/scan.dart';
import '../../src/tasks/tasks.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../src/widgets/select_image_button.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../model/periodic_task_request.dart';
import '../update_manager.dart';
import '../utils/any_controller.dart';
import '../../src/onboarding/demo_equipment.dart';
import 'result_controls.dart';

class QRResultScreen extends StatefulWidget {
  final InventoryRecord machine;
  final String openDateTime;

  const QRResultScreen(this.machine, {super.key, required this.openDateTime});

  @override
  State<QRResultScreen> createState() => _QRResultScreenState();
}

class _QRResultScreenState extends State<QRResultScreen> {
  final descController = TextEditingController();
  final imageData1Controller = SelectImageButtonController();
  final imageData2Controller = SelectImageButtonController();
  final imageData3Controller = SelectImageButtonController();
  final priorityController = AnyController<Priority>();
  final problemController = AnyController<TypicalProblem>();
  final equipmentController = EquipmentDetailController();
  final usageController = AnyController<List<UsageUpdate>>();
  final stateController = AnyController<String>();
  String? _previousState;
  bool _highlightDescError = false;
  bool _highlightPriorityError = false;

  void _showStateSnack({required String message, required bool ok}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final fg = ok ? cs.onSuccess : cs.onError;
    final bg = ok ? cs.success : cs.error;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: fg)),
          ),
        ],
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool _isOfflineError(Object e) {
    if (e is SocketException || e is HttpException) return true;
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused') ||
        s.contains('Network is unreachable') ||
        s.contains('TimeoutException');
  }

  void _onStateChanged() async {
    final newState = stateController.value;
    if (newState == null ||
        newState.isEmpty ||
        newState == _previousState) {
      return;
    }
    const successMsg = 'Состояние оборудования успешно изменено';
    const offlineMsg = 'Состояние не обновлено: нет интернета';
    const otherMsg = 'Не удалось изменить состояние оборудования';

    if (widget.machine.uuid == DemoEquipment.demoUuid) {
      _previousState = newState;
      _showStateSnack(message: successMsg, ok: true);
      return;
    }
    try {
      await GlobalState.dataProvider
          .updateEquipmentState(widget.machine.uuid, newState);
      _previousState = newState;
      _showStateSnack(message: successMsg, ok: true);
    } catch (e) {
      _showStateSnack(
        message: _isOfflineError(e) ? offlineMsg : otherMsg,
        ok: false,
      );
    }
  }

  Widget passport() {
    return _HeroPassport(
      machine: widget.machine,
      stateController: stateController,
      showDetails: !Settings.qrResultShowSimplifiedView,
    );
  }

  List<UsageUpdate> createUsageScans() {
    List<UsageUpdate> result = [];
    if (usageController.value != null) {
      for (var usageParameter in usageController.value!) {
        result.add(usageParameter);
      }
    }
    return result;
  }

  List<Scan>? createScans() {
    List<Scan> result = [];

    var images = [
      imageData1Controller.value,
      imageData2Controller.value,
      imageData3Controller.value,
    ].where((v) {
      return v.length > 0;
    }).toList();

    var faultUUID =
        problemController.value != null && problemController.value!.id != 0
            ? problemController.value!.uuid
            : '';
    var priority = priorityController.value == null
        ? null
        : priorityController.value!.value;
    if (problemController.value != null && priority == null) {
      priority = (problemController.value!).defaultPriority;
    }
    var hasDesc = descController.text.length > 0;
    var hasPriority = priority != null;
    var hasOtherProblem = (problemController.value == TypicalProblem.other);
    var hasTypicalProblem = (problemController.value != null &&
        problemController.value != TypicalProblem.other);

    var hasTasks = false;
    for (var task in equipmentController.value) {
      if (task.resultStatus == 'scheduled') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: images,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: task.periodicTask!.uuid));
        hasTasks = true;
      }
      if (task.resultStatus == 'open') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: images,
            comment: descController.text,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            periodicTaskUuid: ''));
        hasTasks = true;
      }
    }


    if (hasOtherProblem) {
      var returnEmpty = false;
      if (!hasDesc) {
        returnEmpty = true;
      }
      if (!hasPriority) {
        returnEmpty = true;
      }
      if (returnEmpty) {
        if (mounted) {
          setState(() {
            _highlightDescError = !hasDesc;
            _highlightPriorityError = !hasPriority;
          });
        }
        return null;
      }
    }

    if (mounted) {
      setState(() {
        _highlightDescError = false;
        _highlightPriorityError = false;
      });
    }

    if ((hasDesc && hasOtherProblem && hasPriority) ||
        (hasTypicalProblem) ||
        (hasDesc && !hasOtherProblem && !hasPriority && !hasTypicalProblem && !hasTasks)) {
      result.add(Scan(
          taskUuid: '',
          resultStatus:
              (hasOtherProblem && faultUUID.length == 0) ? 'open' : 'closed',
          files: images,
          comment: descController.text,
          priority: priority,
          equipmentUuid: widget.machine.uuid,
          closedAt: GlobalState.nowUTCDate,
          createdAt: widget.openDateTime,
          faultUuid: faultUUID,
          isOtherFault: hasOtherProblem,
          periodicTaskUuid: ''));
    }
    return result;
  }

  addScans(List<Scan> scans, List<UsageUpdate> usageScans) async {
    for (var usageParameter in usageScans) {
      await GlobalState.dataProvider.addUsageScan(usageParameter);
    }

    for (var scan in scans) {
      if (scan.resultStatus == 'open') {
        scan.resultStatus = 'closed';
        var periodicTask = PeriodicTaskRequest(
          equipmentUuid: widget.machine.uuid,
          node: null,
          title: 'Проблема',
          description:
              descController.text.isNotEmpty ? descController.text : null,
          periodicityRule: 'once',
          customRoleIds: null,
          nextDueAt: GlobalState.nowUTCDate,
          photos: scan.files,
          params: {
            'target_type': 'ad_hoc',
            'priority': scan.priority,
          },
        );
        await GlobalState.dataProvider.addPeriodicTask(periodicTask);
      }
      await GlobalState.dataProvider.addScan(scan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = context.watch<DataProvider>();

    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        UpdateManager.checkForUpdate(context);
      },
    );

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          spacing: 8,
          children: [
            passport(),
            ResultControls(
              machine: widget.machine,
              descController: descController,
              imageData1Controller: imageData1Controller,
              imageData2Controller: imageData2Controller,
              imageData3Controller: imageData3Controller,
              priorityController: priorityController,
              problemController: problemController,
              equipmentDetailController: equipmentController,
              usageController: usageController,
              highlightDescError: _highlightDescError,
              highlightPriorityError: _highlightPriorityError,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SubmitBar(
        onSubmit: () => _submit(dataProvider),
      ),
    );
  }

  void _submit(DataProvider dataProvider) {
    final isDemoMode = widget.machine.uuid == DemoEquipment.demoUuid;
    if (isDemoMode) {
      Settings.onboardingStep = 4;
      GoRouter.of(context).clearStackAndNavigate('/onboarding_video');
      return;
    }
    final scans = createScans();
    final usageScans = createUsageScans();
    if (scans == null) return;
    if (scans.length + usageScans.length == 0) {
      Dialogs.notify(context, 'Не отправлено',
          'Укажите данные обхода (комментарий, проблему, задачу или наработку)');
      return;
    }
    Dialogs.areYouSure(context, onOk: () async {
      await addScans(scans, usageScans);
      dataProvider.mainSync();
      for (var usageScan in usageScans) {
        if (usageScan.usageParameterValue == null) continue;
        for (var usageParam in widget.machine.usageParameters) {
          if (usageScan.usageParameterUuid == usageParam.uuid) {
            usageParam.currentValue = usageScan.usageParameterValue!;
          }
        }
      }
      if (!mounted) return;
      if (GoRouter.of(context).location == '/qr_result_problems') {
        GoRouter.of(context).clearStackAndNavigate('/problems');
      } else {
        GoRouter.of(context).clearStackAndNavigate('/qr_scanner');
      }
    }, rewriteMessage: null, desc: null);
  }

  void _clearValidationHighlights() {
    if (_highlightDescError || _highlightPriorityError) {
      setState(() {
        _highlightDescError = false;
        _highlightPriorityError = false;
      });
    }
  }

  bool _isProcessingConflict = false;

  void _onProblemChanged() async {
    if (_isProcessingConflict) return;

    final problem = problemController.value;

    if (problem != null && problem != TypicalProblem.empty) {
      if (equipmentController.selectedTasks.isNotEmpty) {
        if (!mounted) return;

        final cancelTask = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Задача и проблема'),
            content: const Text(
              'Нельзя одновременно выбрать задачу и проблему.\n\nОтменить задачу?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (cancelTask == true) {
          equipmentController.clearSelection();
        } else {
          _isProcessingConflict = true;
          problemController.value = null;
          _isProcessingConflict = false;
          return;
        }
      }
    }

    final currentProblem = problemController.value;
    if (currentProblem != TypicalProblem.other &&
        priorityController.value != null) {
      priorityController.value = null;
    }
  }

  void _onTaskChanged() async {
    if (_isProcessingConflict) return;

    if (equipmentController.selectedTasks.isNotEmpty) {
      if (problemController.value != null) {
        if (!mounted) return;

        final cancelProblem = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Задача и проблема'),
            content: const Text(
              'Нельзя одновременно выбрать задачу и проблему.\n\nОтменить проблему?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (cancelProblem == true) {
          _isProcessingConflict = true;
          problemController.value = null;
          _isProcessingConflict = false;
        } else {
          _isProcessingConflict = true;
          equipmentController.clearSelection();
          _isProcessingConflict = false;
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _previousState = widget.machine.state;
    stateController.valueNotifier.addListener(_onStateChanged);
    descController.addListener(_clearValidationHighlights);
    priorityController.valueNotifier.addListener(_clearValidationHighlights);
    problemController.valueNotifier.addListener(_onProblemChanged);
    equipmentController.valueNotifier.addListener(_onTaskChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // stateController.valueNotifier.removeListener(_onStateChanged);
    descController.removeListener(_clearValidationHighlights);
    priorityController.valueNotifier.removeListener(_clearValidationHighlights);
    problemController.valueNotifier.removeListener(_onProblemChanged);
    equipmentController.valueNotifier.removeListener(_onTaskChanged);
    stateController.dispose();
    descController.dispose();
    imageData1Controller.dispose();
    imageData2Controller.dispose();
    imageData3Controller.dispose();
    equipmentController.dispose();
    super.dispose();
  }
}

/// Компактный паспорт оборудования: 64px превью слева, имя + подзаголовок
/// (модель / S/N) + chip состояния — справа. Полная разметка свёрнута в
/// `ExpansionTile «Подробнее»`. Тап по превью открывает lightbox.
class _HeroPassport extends StatelessWidget {
  final InventoryRecord machine;
  final AnyController<String> stateController;
  final bool showDetails;

  const _HeroPassport({
    required this.machine,
    required this.stateController,
    required this.showDetails,
  });

  String? _subtitle() {
    final parts = <String>[];
    if (machine.typeModel != null && machine.typeModel!.isNotEmpty) {
      parts.add(machine.typeModel!);
    }
    if (machine.serialNumber != null && machine.serialNumber!.isNotEmpty) {
      parts.add('S/N ${machine.serialNumber}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  void _showLightbox(BuildContext context) {
    if (machine.imageData.isEmpty) return;
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
                child: Image.network(
                  machine.imageData,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = _subtitle();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(
                  imageData: machine.imageData,
                  onTap: () => _showLightbox(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _StateChip(
                        controller: stateController,
                        initialValue: machine.state,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDetails)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  'Подробнее об оборудовании',
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Icon(Icons.expand_more_rounded, color: cs.primary),
                childrenPadding:
                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MarkdownBody(data: machine.descriptionText),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String imageData;
  final VoidCallback onTap;
  const _Thumb({required this.imageData, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = imageData.isNotEmpty;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasImage ? onTap : null,
        child: SizedBox(
          width: 64,
          height: 64,
          child: hasImage
              ? Image.network(
                  imageData,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                )
              : Icon(
                  Icons.precision_manufacturing_outlined,
                  color: cs.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

/// Chip с текущим состоянием оборудования. Тап открывает bottom-sheet со
/// списком состояний из `GlobalState.dataProvider.equipmentState`. Если
/// состояний нет — chip не рендерится.
class _StateChip extends StatefulWidget {
  final AnyController<String> controller;
  final String? initialValue;

  const _StateChip({required this.controller, this.initialValue});

  @override
  State<_StateChip> createState() => _StateChipState();
}

class _StateChipState extends State<_StateChip> {
  String? _value;

  @override
  void initState() {
    super.initState();
    final iv = widget.initialValue;
    if (iv != null && iv.isNotEmpty) {
      _value = iv;
      widget.controller.value = iv;
    }
  }

  String? _label(String? id) {
    if (id == null) return null;
    final states = GlobalState.dataProvider.equipmentState?.states;
    return states?[id];
  }

  Future<void> _pick() async {
    final eq = GlobalState.dataProvider.equipmentState;
    if (eq == null || eq.states.isEmpty) return;
    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'СОСТОЯНИЕ ОБОРУДОВАНИЯ',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.remove_circle_outline_rounded,
                  color: cs.onSurfaceVariant),
              title: const Text('Без состояния'),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            for (final entry in eq.states.entries)
              ListTile(
                leading: Icon(Icons.circle, size: 12, color: cs.primary),
                title: Text(entry.value),
                trailing: _value == entry.key
                    ? Icon(Icons.check_rounded, color: cs.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final next = selected.isEmpty ? null : selected;
    widget.controller.value = selected;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final states = GlobalState.dataProvider.equipmentState?.states;
    if (states == null || states.isEmpty) return const SizedBox.shrink();
    final hasValue = _value != null;
    final label = _label(_value);
    return Material(
      color: hasValue ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pick,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasValue ? cs.primary : cs.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label ?? 'Состояние',
                style: tt.labelMedium?.copyWith(
                  color: hasValue
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: hasValue
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom CTA для отправки осмотра. Surface фон + тонкая верхняя
/// граница из outlineVariant, primary FilledButton 56px высоты с иконкой.
class _SubmitBar extends StatelessWidget {
  final VoidCallback onSubmit;
  const _SubmitBar({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text('Отправить'),
          ),
        ),
      ),
    );
  }
}

