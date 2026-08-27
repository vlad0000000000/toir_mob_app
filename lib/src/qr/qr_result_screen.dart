import 'dart:convert';

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
import '../../src/widgets/controller_listener_mixin.dart';
import '../../src/widgets/select_image_button.dart';
import '../../src/widgets/spare_part_consumption.dart';
import '../../strings.dart';
import '../model/repair.dart';
import '../model/typical_problem.dart';
import '../model/usage_update.dart';
import '../model/periodic_task_request.dart';
import '../update_manager.dart';
import '../utils/any_controller.dart';
import '../utils/offline_error.dart';
import '../../src/onboarding/demo_equipment.dart';
import 'result_controls.dart';

/// Код состояния «В ремонте» на сервере (`EquipmentState.IN_REPAIR`).
/// Нужен и экрану (перехват смены состояния), и списку состояний.
const String _inRepairState = 'in_repair';

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
  final consumptionController = AnyController<List<ConsumptionLine>>();
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

  // Детект офлайна переехал в `utils/offline_error.dart`: та же проверка
  // понадобилась очереди осмотров, а четвёртой копии в проекте быть не должно.
  bool _isOfflineError(Object e) => isOfflineError(e);

  /// Оборудование уже в ремонте — вместо сырого отказа объясняем ситуацию и
  /// даём перейти в существующий ремонт (п. 4.4.5 плана).
  ///
  /// По макету: круглый значок сверху,
  /// заголовок, строка «Ремонт №N — «статус»» с цветом этого статуса,
  /// пояснение плашкой и две кнопки в столбик.
  void _showAlreadyInRepair(Repair repair) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Цвет статуса тот же, что у пилюли в списке: открытый — красный,
    // на рассмотрении — оранжевый, закрытый — зелёный.
    final statusColor = repair.isClosed
        ? cs.success
        : repair.isOpen
            ? cs.error
            : cs.warning;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cs.surfaceContainerLowest,
        insetPadding: const EdgeInsets.all(AppConstants.spacingMD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLG),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Вся гамма окна — по статусу ремонта: открыт красным, на
              // рассмотрении оранжевым. Обходчик должен различать «ремонт ещё
              // идёт» и «работа сдана, ждём администратора» с одного взгляда,
              // не вчитываясь в подпись.
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.handyman_rounded, size: 32, color: statusColor),
              ),
              const SizedBox(height: AppConstants.spacingMD),
              Text(
                'Оборудование в ремонте',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacingXS),
              Text.rich(
                TextSpan(
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  children: [
                    TextSpan(text: 'Ремонт №${repair.id} — '),
                    TextSpan(
                      text: '«${RepairStatuses.displayName(repair.status)}»',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacingMD),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spacingMD),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: Text(
                  'Состояние вернётся автоматически, когда администратор '
                  'закроет ремонт.',
                  style: tt.bodySmall?.copyWith(color: statusColor),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppConstants.spacingMD),
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeightLarge,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // Ремонт уже найден в кэше — отдаём его карточке, чтобы
                    // та не ждала ответа сервера.
                    GoRouter.of(context)
                        .push('/repairs/${repair.uuid}', extra: repair);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  label: const Text('Открыть ремонт'),
                ),
              ),
              const SizedBox(height: AppConstants.spacingSM),
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeightLarge,
                child: ElevatedButton(
                  // Вторичная кнопка серой заливкой, а не обводкой — как в
                  // окне завершения ремонта: обе кнопки одной «плотности».
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.surfaceContainer,
                    foregroundColor: cs.onSurface,
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ремонт по этому оборудованию уже заведён без связи и ждёт отправки.
  /// Кнопка ведёт в список ремонтов — там черновик виден с пометкой
  /// «Не отправлено» и его можно отправить вручную или удалить.
  void _showDraftAlreadyQueued() {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(RepairStrings.draftAlreadyQueuedTitle),
        content: Container(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          // Красным, как у открытого ремонта: черновик и есть будущий
          // «Открыт», и оборудование он занимает так же.
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 18, color: cs.error),
              const SizedBox(width: AppConstants.spacingSM),
              Expanded(
                child: Text(
                  RepairStrings.draftAlreadyQueuedBody,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.error),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              GoRouter.of(context).push('/repairs');
            },
            child: const Text('К ремонтам'),
          ),
        ],
      ),
    );
  }

  void _onStateChanged() async {
    final newState = stateController.value;
    if (newState == null || newState.isEmpty || newState == _previousState) {
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

    // Оборудование в ремонте — состояние не меняется вообще никак, пока
    // ремонт не закрыт. Проверка стоит до разбора самого состояния: раньше
    // она была только в ветке «В ремонте», и любое другое состояние
    // («Исправно», «Неисправно») уходило на сервер, ломая логику «состояние
    // вернётся само при закрытии ремонта».
    final active = _activeRepairForMachine();
    if (active != null) {
      // Пилюлю возвращаем к прежнему значению: ничего не поменялось.
      stateController.value = _previousState;
      if (!mounted) return;
      _showAlreadyInRepair(active);
      return;
    }

    // То же самое для черновика: ремонта на сервере ещё нет, но оборудование
    // уже считается занятым — иначе состояние уехало бы на сервер, а следом
    // очередь создала бы по нему ремонт и снова переставила состояние.
    final hasDraft = GlobalState.dataProvider.pendingRepairs
        .any((draft) => draft.equipmentUuid == widget.machine.uuid);
    if (hasDraft) {
      stateController.value = _previousState;
      if (!mounted) return;
      _showDraftAlreadyQueued();
      return;
    }

    // «В ремонте» — особый случай: состояние ставит сервер сам при создании
    // ремонта и отклоняет создание для оборудования, которое уже в этом
    // состоянии. Поменяем состояние сами — ремонт создать станет нельзя.
    // Поэтому вместо смены открываем форму создания. В веб-админке так же.
    if (newState == _inRepairState) {
      // Возвращаем пилюлю к прежнему значению: состояние поменяется только
      // после успешного создания ремонта, и сделает это сервер.
      stateController.value = _previousState;
      if (!mounted) return;
      // push: карточка оборудования остаётся под формой, и закрытие формы
      // возвращает обходчика ровно туда, откуда он её открыл.
      //
      // Ждём возврата и перестраиваем экран: пока форма была открыта, ремонт
      // мог появиться — на сервере или черновиком в очереди. Пилюля читает
      // это в `build`, и без перестроения она осталась бы прежней.
      await GoRouter.of(context).push('/repair_create', extra: widget.machine);
      if (!mounted) return;
      setState(() {});
      return;
    }

    try {
      await GlobalState.dataProvider
          .updateEquipmentState(widget.machine.uuid, newState);
      _previousState = newState;
      _showStateSnack(message: successMsg, ok: true);
    } catch (e) {
      if (!mounted) return;
      // Ремонт мог появиться, пока обходчик стоял на экране: локальная
      // проверка его не увидела, а сервер отказал. Показываем то же
      // объяснение, а не сырую ошибку (п. 4.4.5 отчёта).
      final blocking = await _reloadBlockingRepair();
      if (blocking != null) {
        if (!mounted) return;
        stateController.value = _previousState;
        _showAlreadyInRepair(blocking);
        return;
      }
      if (!mounted) return;
      stateController.value = _previousState;
      _showStateSnack(
        message: _isOfflineError(e) ? offlineMsg : otherMsg,
        ok: false,
      );
    }
  }

  /// Активный ремонт по этому оборудованию из офлайн-кэша. Работает без сети —
  /// в кэше лежат все активные ремонты обходчика.
  Repair? _activeRepairForMachine() {
    for (final repair in GlobalState.dataProvider.repairs) {
      if (repair.equipmentUuid == widget.machine.uuid && repair.isActive) {
        return repair;
      }
    }
    return null;
  }

  /// Перечитывает ремонты с сервера и ищет тот, что занял оборудование.
  /// Нужен после отказа: локальный кэш мог отстать.
  Future<Repair?> _reloadBlockingRepair() async {
    try {
      await GlobalState.dataProvider.syncMyRepairs();
    } catch (_) {
      // Без связи остаёмся на том, что есть в кэше.
    }
    return _activeRepairForMachine();
  }

  /// Оборудование занято ремонтом — состояние менять нельзя.
  ///
  /// Четыре признака, любого достаточно:
  /// * `has_open_repair` от сервера — единственный, который видит **чужие**
  ///   ремонты: `syncMyRepairs` приносит только ремонты этого обходчика;
  /// * состояние уже «В ремонте»;
  /// * активный ремонт в кэше — работает без связи, когда серверный признак
  ///   успел устареть;
  /// * черновик в очереди — ремонта на сервере ещё нет, но он вот-вот будет.
  bool get _isLockedByRepair =>
      widget.machine.hasOpenRepair ||
      stateController.value == _inRepairState ||
      _activeRepairForMachine() != null ||
      GlobalState.dataProvider.pendingRepairs
          .any((draft) => draft.equipmentUuid == widget.machine.uuid);

  /// Объясняет, почему состояние заблокировано. Молчаливо неактивная пилюля
  /// вернула бы ровно ту жалобу, с которой всё началось: «нажимаю — ничего
  /// не происходит».
  void _explainLockedState() {
    final active = _activeRepairForMachine();
    if (active != null) {
      _showAlreadyInRepair(active);
      return;
    }
    final hasDraft = GlobalState.dataProvider.pendingRepairs
        .any((draft) => draft.equipmentUuid == widget.machine.uuid);
    if (hasDraft) {
      _showDraftAlreadyQueued();
      return;
    }
    // Остался единственный случай: ремонт есть, но чужой — его видит только
    // сервер, в кэше обходчика таких ремонтов нет. Говорить про черновик
    // здесь нельзя: черновика не существует.
    _showBusyByOtherRepair();
  }

  /// Оборудование занято ремонтом другого сотрудника.
  void _showBusyByOtherRepair() {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(RepairStrings.busyByOtherTitle),
        content: Container(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: Text(
            RepairStrings.busyByOtherBody,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(RepairStrings.understand),
          ),
        ],
      ),
    );
  }

  Widget passport() {
    return _HeroPassport(
      machine: widget.machine,
      stateController: stateController,
      showDetails: !Settings.qrResultShowSimplifiedView,
      lockedByRepair: () => _isLockedByRepair,
      onLockedTap: _explainLockedState,
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

  /// Фактический расход для отправки — готовая строка поля
  /// `actual_consumptions` формы `PATCH /v1/company/fault_inspections/{uuid}`.
  ///
  /// `null` — расход не заполнен. Поле тогда не отправляем вовсе: пустой
  /// список сервер понял бы как «расхода нет» и стёр бы уже сохранённые
  /// позиции, а списание не выполнил бы.
  String? _consumptionsPayload() {
    final lines = (consumptionController.value ?? const <ConsumptionLine>[])
        .where((line) => line.quantity > 0)
        .toList();
    if (lines.isEmpty) return null;
    return jsonEncode([
      for (final line in lines)
        {'spare_part_uuid': line.sparePartUuid, 'quantity': line.quantity},
    ]);
  }

  /// Названия позиций расхода — для показа, а не для сервера.
  ///
  /// Кладём их в осмотр вместе с расходом, потому что в самой очереди имён
  /// нет: `actual_consumptions` — это формат запроса, там только uuid. Если
  /// позицию удалят на сервере (а отказ «на складе 0» ровно об этом и
  /// говорит), справочник её потеряет, и подписать расход будет нечем.
  String? _consumptionNamesPayload() {
    final lines = (consumptionController.value ?? const <ConsumptionLine>[])
        .where((line) => line.quantity > 0)
        .toList();
    if (lines.isEmpty) return null;
    return jsonEncode({
      for (final line in lines) line.sparePartUuid: line.sparePartName,
    });
  }

  List<Scan>? createScans() {
    List<Scan> result = [];
    // Считаем один раз: расход относится к единственной выбранной задаче.
    final consumptionTask = consumptionTaskOf(equipmentController);
    final consumptionsPayload =
        consumptionTask == null ? null : _consumptionsPayload();
    final consumptionNames =
        consumptionTask == null ? null : _consumptionNamesPayload();

    // Если у компании включён множественный выбор задач и выбрано 2+ —
    // поля фото и комментария в UI заблокированы, поэтому не отправляем их
    // значения вместе с задачами, даже если они остались в контроллерах.
    final tasksLocked = equipmentController.allowMultiSelect &&
        equipmentController.value.length >= 2;

    var images = tasksLocked
        ? <String>[]
        : [
            imageData1Controller.value,
            imageData2Controller.value,
            imageData3Controller.value,
          ].where((v) {
            return v.length > 0;
          }).toList();
    var taskComment = tasksLocked ? '' : descController.text;

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

    // Снимки прикладываем ровно к одной записи пачки, а не к каждой.
    //
    // Раньше `files: images` стояло и у осмотра задачи, и у заявки, а
    // `sendScan` грузит файлы отдельно на каждый запрос — одни и те же кадры
    // уезжали дважды. В цеху со слабой связью очередь из-за этого разбиралась
    // вдвое дольше.
    //
    // Отдаём их **заявке**, а не первой записи пачки, как предлагал план:
    // заявка — это сообщение о неисправности, и снимок там доказательство, а
    // у закрытой периодической задачи он иллюстрация. Если заявки нет, снимки
    // остаются у осмотра.
    //
    // Третья ветка условия создания заявки (`hasDesc && … && !hasTasks`) сюда
    // не входит намеренно: она срабатывает только когда задач нет вовсе, и
    // делить снимки не с кем.
    final willCreateProblem =
        (hasDesc && hasOtherProblem && hasPriority) || hasTypicalProblem;
    final taskImages = willCreateProblem ? const <String>[] : images;

    var hasTasks = false;
    for (var task in equipmentController.value) {
      if (task.resultStatus == 'scheduled') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: taskImages,
            comment: taskComment,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            actualConsumptions:
                task.uuid == consumptionTask?.uuid ? consumptionsPayload : null,
            consumptionNames:
                task.uuid == consumptionTask?.uuid ? consumptionNames : null,
            periodicTaskUuid: task.periodicTask!.uuid));
        hasTasks = true;
      }
      if (task.resultStatus == 'open') {
        result.add(Scan(
            taskUuid: task.uuid,
            resultStatus: 'closed',
            files: taskImages,
            comment: taskComment,
            priority: '',
            equipmentUuid: widget.machine.uuid,
            faultUuid: '',
            closedAt: GlobalState.nowUTCDate,
            createdAt: widget.openDateTime,
            actualConsumptions:
                task.uuid == consumptionTask?.uuid ? consumptionsPayload : null,
            consumptionNames:
                task.uuid == consumptionTask?.uuid ? consumptionNames : null,
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
        (hasDesc &&
            !hasOtherProblem &&
            !hasPriority &&
            !hasTypicalProblem &&
            !hasTasks)) {
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
    // `read`, а не `watch`: DataProvider не ChangeNotifier и положен в дерево
    // обычным Provider, так что подписываться тут не на что — `watch` лишь
    // выглядел реактивным. За изменениями данных следят ревизии кэша
    // (`repairsRevision`, `sparePartsRevision`).
    final dataProvider = context.read<DataProvider>();

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
              consumptionController: consumptionController,
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
    // Задача с настроенным расходом закрывается без единой позиции — значит
    // со склада ничего не спишется. Не запрещаем: ТО не всегда требует ЗИП.
    // Но переспрашиваем — забытый расход всплыл бы только у администратора,
    // в разъехавшихся остатках, и задним числом его уже не поправить.
    //
    // Спрашиваем только по настроенной задаче. Раздел расхода теперь есть у
    // каждой периодической задачи, и без этой проверки подтверждение вылезало
    // бы при закрытии любого обычного осмотра — там пустой расход не забывчивость,
    // а норма жизни.
    //
    // Считаем по всем выбранным задачам, а не по единственной. Раньше проверка
    // начиналась с `consumptionTask != null`, а он пуст при двух и более
    // выбранных, — и предупреждение молчало ровно там, где нужнее всего:
    // расход в этом случае не только не заполнен, но и заполнить его негде.
    final consumptionTask = consumptionTaskOf(equipmentController);
    final configuredTasks = configuredConsumptionTasksOf(equipmentController);
    final skipsWriteOff = configuredTasks.isNotEmpty &&
        (consumptionTask == null || _consumptionsPayload() == null);
    // Причина разная — «забыли заполнить» или «выбрано несколько задач», — и
    // текст подтверждения тоже.
    final multipleTasks = equipmentController.selectedTasks.length > 1;

    // Второй повод переспросить: расход заполнен, но на складе столько нет.
    // С первым он не пересекается — при пустом расходе нехватке взяться
    // неоткуда, — поэтому это не «или/или», а два независимых случая.
    //
    // Считаем по локальному справочнику, и потому именно спрашиваем, а не
    // запрещаем: без сети остатки могли устареть, и «сервер откажет» здесь
    // предположение, пусть и почти всегда верное.
    final shortages = consumptionTask == null
        ? const <ConsumptionShortage>[]
        : consumptionShortages(
            consumptionController.value ?? const <ConsumptionLine>[]);
    final shortageList = [
      for (final shortage in shortages)
        shortage.available <= 0
            ? InspectionConsumptionStrings.shortagePositionEmpty(
                shortage.sparePartName)
            : InspectionConsumptionStrings.shortagePosition(
                shortage.sparePartName, shortage.availableLabel),
    ].join(', ');

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
      // Осмотр отправлен — закрываем карточку и возвращаемся туда, откуда её
      // открыли: к камере или в список осмотров. Запасной адрес нужен, если
      // карточку открыли с пустым стеком.
      GoRouter.of(context).backOr(
        GoRouter.of(context).location == '/qr_result_problems'
            ? '/problems'
            : '/qr_scanner',
      );
    },
        rewriteMessage: skipsWriteOff
            ? (multipleTasks
                ? InspectionConsumptionStrings.confirmMultiTaskTitle
                : InspectionConsumptionStrings.confirmEmptyTitle)
            : (shortages.isEmpty
                ? null
                : InspectionConsumptionStrings.confirmShortageTitle),
        desc: skipsWriteOff
            ? (multipleTasks
                ? InspectionConsumptionStrings.confirmMultiTaskBody
                : InspectionConsumptionStrings.confirmEmptyBody)
            : (shortages.isEmpty
                ? null
                : InspectionConsumptionStrings.confirmShortageBody(
                    shortageList)));
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
    // Локальная пометка «В ремонте» (п. 4.5.7 отчёта): состояние ставит
    // сервер при создании ремонта, но пока черновик лежит в очереди, сервер о
    // нём не знает, и справочник оборудования показывал бы прежнее состояние.
    // Отдельного хранилища пометок не заводим — очередь черновиков и есть
    // хранилище, независимое от справочника: синхронизация перезаписывает
    // справочник целиком, а очередь не трогает.
    final hasDraft = GlobalState.dataProvider.pendingRepairs
        .any((draft) => draft.equipmentUuid == widget.machine.uuid);
    _previousState = hasDraft ? _inRepairState : widget.machine.state;
    stateController.value = _previousState;
    stateController.valueNotifier.addListener(_onStateChanged);
    descController.addListener(_clearValidationHighlights);
    priorityController.valueNotifier.addListener(_clearValidationHighlights);
    problemController.valueNotifier.addListener(_onProblemChanged);
    equipmentController.valueNotifier.addListener(_onTaskChanged);

    // Справочник ЗИП нужен разделу фактического расхода: и для подбора
    // позиций, и для остатков в предупреждениях о нехватке. В общей
    // синхронизации его нет, а на карточку попадают прямо со сканера —
    // поэтому подтягиваем здесь. Экран этого не ждёт.
    GlobalState.dataProvider.ensureSparePartsLoaded();

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
    consumptionController.dispose();
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

  /// Оборудование в ремонте — пилюля состояния заперта.
  ///
  /// Функция, а не готовое значение: пилюля пересчитывает признак на каждое
  /// изменение списка ремонтов. Иначе она застывала бы в том виде, в каком
  /// экран построился, — а ремонт появляется, пока экран уже открыт.
  final bool Function() lockedByRepair;

  /// Что делать по нажатию на запертую пилюлю: объяснить причину.
  final VoidCallback onLockedTap;

  const _HeroPassport({
    required this.machine,
    required this.stateController,
    required this.showDetails,
    required this.lockedByRepair,
    required this.onLockedTap,
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
                      // Перестраиваем пилюлю на любое изменение списка
                      // ремонтов: создание, отправку черновика, закрытие.
                      // Так замок и подпись «В ремонте» появляются сразу
                      // после создания ремонта, не дожидаясь ни возврата на
                      // экран, ни синхронизации инвентаря.
                      ValueListenableBuilder<int>(
                        valueListenable:
                            GlobalState.dataProvider.activeRepairsCount,
                        builder: (context, _, __) => _StateChip(
                          controller: stateController,
                          initialValue: machine.state,
                          locked: lockedByRepair(),
                          onLockedTap: onLockedTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDetails)
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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

  /// Состояние менять нельзя — оборудование занято ремонтом.
  ///
  /// Так же ведёт себя админка: пока ремонт не закрыт, состояние принадлежит
  /// ему. Раньше список состояний открывался, «В ремонте» было подписано
  /// «Откроется форма создания ремонта», и нажатие ничего не давало — форма
  /// не открывалась, потому что ремонт уже есть.
  final bool locked;

  /// Нажатие на запертую пилюлю — объяснить причину, а не промолчать.
  final VoidCallback? onLockedTap;

  const _StateChip({
    required this.controller,
    this.initialValue,
    this.locked = false,
    this.onLockedTap,
  });

  @override
  State<_StateChip> createState() => _StateChipState();
}

class _StateChipState extends State<_StateChip> with ControllerListenerMixin {
  @override
  Listenable get controllerListenable => widget.controller.valueNotifier;

  /// Что показывать — берём из контроллера, своей копии значения у пилюли нет.
  ///
  /// Экран откатывает смену состояния сразу несколькими путями: оборудование
  /// в ремонте, черновик ремонта в очереди, отказ сервера, нет связи. Откат
  /// возвращает в контроллер прежнее значение, и собственная копия внутри
  /// пилюли осталась бы с выбранным — обходчик видел бы состояние, которого
  /// на самом деле нет.
  String? get _value {
    final value = widget.controller.value;
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  void initState() {
    super.initState();
    final iv = widget.initialValue;
    if (iv != null && iv.isNotEmpty) {
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
              // «В ремонте» — не обычный пункт списка: состояние ставит
              // сервер при создании ремонта, а приложение вместо смены
              // открывает форму. Поэтому строка выделена и подписана, чтобы
              // обходчик не удивился уходу на другой экран.
              if (entry.key == _inRepairState)
                Container(
                  color: cs.primaryContainer.withValues(alpha: 0.45),
                  child: ListTile(
                    leading: Icon(Icons.handyman_rounded, color: cs.primary),
                    title: Text(
                      entry.value,
                      style: Theme.of(ctx)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Откроется форма создания ремонта',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.arrow_forward_rounded,
                        color: cs.onSurfaceVariant),
                    onTap: () => Navigator.of(ctx).pop(entry.key),
                  ),
                )
              else
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
    // Своё значение не выставляем: пилюля перерисуется от контроллера. Если
    // экран откатит смену, она покажет прежнее состояние, а не выбранное.
    widget.controller.value = selected;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final states = GlobalState.dataProvider.equipmentState?.states;
    if (states == null || states.isEmpty) return const SizedBox.shrink();
    final locked = widget.locked;
    final hasValue = _value != null;
    // У запертой пилюли подпись всегда «В ремонте», а не то, что лежит в
    // контроллере. Состояние оборудования ставит сервер при создании ремонта,
    // и до ближайшей синхронизации инвентаря в кэше остаётся прежнее: сразу
    // после создания ремонта обходчик видел замок рядом со старым
    // состоянием. Раз замок висит — ремонт есть, а значит и состояние на
    // сервере уже «В ремонте».
    final label = locked
        ? (_label(_inRepairState) ?? RepairStrings.equipmentInRepair)
        : _label(_value);

    // Запертая пилюля — красная, с замком вместо шеврона и без точки:
    // точка отмечает выбранное состояние, а выбирать здесь не из чего.
    final foreground = locked
        ? cs.error
        : hasValue
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant;

    return Material(
      color: locked
          ? cs.error.withValues(alpha: 0.12)
          : hasValue
              ? cs.primaryContainer
              : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked ? widget.onLockedTap : _pick,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!locked) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: hasValue ? cs.primary : cs.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label ?? 'Состояние',
                style: tt.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                locked ? Icons.lock_outline_rounded : Icons.expand_more_rounded,
                size: locked ? 15 : 18,
                color: foreground,
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
