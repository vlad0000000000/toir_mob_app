import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../http/api.dart';
import '../model/consumption_norm.dart';
import '../model/inventory_record.dart';
import '../model/pending_repair.dart';
import '../model/repair.dart';
import '../utils/dialogs.dart';
import '../utils/go_router_ext.dart';
import '../widgets/date_range_sheet.dart';
import '../widgets/offline_banner.dart';
import 'repair_error_messages.dart';

/// Форма создания ремонта — по макету «Рисунок 11».
///
/// Открывается вместо смены состояния на «В ремонте»: состояние оборудованию
/// ставит сервер сам при создании ремонта и отклоняет создание, если
/// оборудование уже в этом состоянии. Поменяй состояние сначала — ремонт стало
/// бы невозможно создать. В веб-админке сделано так же.
class CreateRepairScreen extends StatefulWidget {
  final InventoryRecord equipment;

  const CreateRepairScreen({super.key, required this.equipment});

  @override
  State<CreateRepairScreen> createState() => _CreateRepairScreenState();
}

class _CreateRepairScreenState extends State<CreateRepairScreen> {
  static const int _commentLimit = 2000;

  final _commentController = TextEditingController();
  DateTime _startedAt = DateTime.now();
  ConsumptionNorm? _norm;
  bool _isSaving = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // Тот же календарь, что в фильтре периода карточки ЗИП, только панель
    // одна. Штатный showDatePicker не годится: без flutter_localizations он
    // английский, а поставить пакет нельзя — он ломает сборку (см. main.dart).
    //
    // Дату начала можно поставить и в будущем: ремонт заводят заранее, «на
    // завтра». Сервер `started_at` не ограничивает — валидаторов на будущее в
    // `RepairCreateSchema` нет, — поэтому и приложение не ограничивает.
    // Границы календаря широкие просто чтобы колесу лет было где крутиться.
    final picked = await showSingleDateSheet(
      context,
      initial: _startedAt,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
      title: RepairStrings.labelStartedAtField,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startedAt.hour,
        _startedAt.minute,
      );
    });
  }

  /// Время выбирается колёсами часов и минут — как `TimeWheelPicker` в
  /// веб-админке. Штатный `showTimePicker` здесь не годится: без
  /// `flutter_localizations` он показывает английский AM/PM-циферблат,
  /// совсем не похожий на админку.
  Future<void> _pickTime() async {
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TimeWheelSheet(
        initial: TimeOfDay.fromDateTime(_startedAt),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Время тоже не зажимаем «не позже сейчас»: ремонт заводят и на будущее,
      // и подрезка превращала бы 09:00 завтрашнего дня в текущий момент.
      _startedAt = DateTime(
        _startedAt.year,
        _startedAt.month,
        _startedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickNorm() async {
    final picked = await showModalBottomSheet<_NormChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NormPickerSheet(
        equipmentUuid: widget.equipment.uuid,
        selectedUuid: _norm?.uuid,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _norm = picked.norm);
  }

  Future<void> _create() async {
    if (_isSaving) return;
    // Второй черновик по тому же оборудованию сервер всё равно отклонит:
    // активный ремонт может быть только один. Проверка есть и на входе в
    // форму (карточка скана), но полагаться на вызывающего нельзя — сюда
    // можно вернуться «назад» и нажать «Создать» ещё раз, пока первый
    // черновик ждёт связи.
    final queued = GlobalState.dataProvider.pendingRepairs
        .any((item) => item.equipmentUuid == widget.equipment.uuid);
    if (queued) {
      Dialogs.notify(
        context,
        RepairStrings.draftAlreadyQueuedTitle,
        RepairStrings.draftAlreadyQueuedBody,
      );
      return;
    }
    setState(() => _isSaving = true);
    final draft = PendingRepair.create(
      equipmentUuid: widget.equipment.uuid,
      equipmentName: widget.equipment.name,
      startedAt: _startedAt,
      consumptionNormUuid: _norm?.uuid,
      consumptionNormName: _norm?.name,
      comment: _commentController.text.trim(),
      // Состав нормы кладём в черновик: без сети карточка не сможет ни
      // показать плановые количества, ни заполнить расход из нормы.
      normItems: _norm?.items ?? const [],
    );
    try {
      // Ключ идемпотентности берём у черновика с самого начала, даже когда
      // связь есть: если ответ потеряется по дороге, повтор из очереди уйдёт
      // с тем же ключом и второй ремонт не появится.
      final repair = await API().createRepair(
        equipmentUuid: draft.equipmentUuid,
        consumptionNormUuid: draft.consumptionNormUuid,
        startedAt: draft.startedAt,
        comment: draft.comment,
        idempotencyKey: draft.localId,
      );
      await GlobalState.dataProvider.upsertRepair(repair);
      if (!mounted) return;
      // Сразу открываем карточку, а не список: обходчик тут же заполняет
      // расход и отправляет. pushReplacement — форма своё отработала и в
      // стеке не нужна, «назад» из карточки уведёт туда, откуда её открыли.
      GoRouter.of(context).pushReplacement('/repairs/${repair.uuid}');
    } catch (e) {
      if (!mounted) return;
      // Связи нет — не теряем введённое, а кладём в очередь. Карточку при
      // этом не открываем: заполнять расход по несуществующему на сервере
      // ремонту нечем, сначала он должен доехать.
      if (isRetryableRepairError(e)) {
        await GlobalState.dataProvider.addPendingRepair(draft);
        if (!mounted) return;
        // Показываем список: там черновик виден с пометкой «Не отправлено», и
        // сразу понятно, что данные не потеряны. Форму заменяем, а не кладём
        // поверх — возвращаться в неё уже незачем.
        GoRouter.of(context).pushReplacement('/repairs');
        return;
      }
      setState(() => _isSaving = false);
      final cs = Theme.of(context).colorScheme;
      final messenger = ScaffoldMessenger.of(context);
      // Плашки копятся в очереди, а не заменяют друг друга: два нажатия
      // «Создать» подряд — два одинаковых сообщения одно за другим.
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text(
          _messageOf(e),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onError),
        ),
        backgroundColor: cs.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static String _messageOf(Object error) => repairErrorMessage(error);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final responsible = GlobalState.authUser?.username ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: RepairStrings.cancel,
          // Возвращаемся туда, откуда пришли: на карточку оборудования после
          // скана либо в список осмотров. Сканер — только запасной адрес, на
          // случай если форму открыли с пустым стеком.
          onPressed: () => GoRouter.of(context).backOr('/qr_scanner'),
        ),
        title: const Text(RepairStrings.createTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingMD,
          AppConstants.spacingXL,
        ),
        children: [
          const OfflineBanner(
            hint: RepairStrings.createOfflineHint,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMD),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: Icon(
                      Icons.precision_manufacturing_outlined,
                      size: 32,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Замок стоит у названия: он относится к самому
                        // выбору оборудования, а не к пояснению под ним.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.equipment.name,
                                style: tt.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            // Замка здесь нет: про то, что оборудование
                            // выбрано автоматически и не меняется, говорит
                            // подпись строкой ниже — значок это дублировал.
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          RepairStrings.createEquipmentLocked,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingLG),
          _Label(RepairStrings.labelResponsible),
          const SizedBox(height: AppConstants.spacingSM),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Text(
              responsible.isEmpty
                  ? RepairStrings.responsibleSelf
                  : RepairStrings.responsibleYou(responsible),
              style: tt.bodyLarge,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            RepairStrings.responsibleHint,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingLG),
          _Label(RepairStrings.labelNorm),
          const SizedBox(height: AppConstants.spacingSM),
          _PickerField(
            icon: Icons.checklist_rounded,
            value: _norm?.name ?? RepairStrings.normNotSet,
            muted: _norm == null,
            trailing: Icons.expand_more_rounded,
            onTap: _isSaving ? null : _pickNorm,
          ),
          const SizedBox(height: 4),
          Text(
            RepairStrings.normHint,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingLG),
          _Label(RepairStrings.labelStartedAt),
          const SizedBox(height: AppConstants.spacingSM),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  value: DateFormat('dd.MM.yyyy').format(_startedAt),
                  trailingAsset: 'assets/images/calendar.svg',
                  onTap: _isSaving ? null : _pickDate,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: _PickerField(
                  value: DateFormat('HH:mm').format(_startedAt),
                  trailingAsset: 'assets/images/clock.svg',
                  onTap: _isSaving ? null : _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLG),
          _Label(RepairStrings.labelComment),
          const SizedBox(height: AppConstants.spacingSM),
          TextField(
            controller: _commentController,
            enabled: !_isSaving,
            minLines: 3,
            maxLines: 6,
            maxLength: _commentLimit,
            decoration: const InputDecoration(
              hintText: RepairStrings.commentHint,
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
            border:
                Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _create,
                  icon: _isSaving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: cs.onPrimary,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(_isSaving
                      ? RepairStrings.createSubmitting
                      : RepairStrings.createSubmit),
                ),
              ),
              const SizedBox(height: AppConstants.spacingSM),
              Text(
                RepairStrings.createFooter,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  /// Значок слева от значения. У даты и времени его нет — там значок стоит
  /// справа и задаётся через [trailingAsset].
  final IconData? icon;
  final String value;
  final VoidCallback? onTap;

  /// Значение не выбрано — показываем его как подсказку, а не как данные.
  final bool muted;

  /// Значок в правом краю: шеврон у выпадающих полей.
  final IconData? trailing;

  /// Значок в правом краю картинкой — календарь и часы взяты из админки.
  final String? trailingAsset;

  const _PickerField({
    this.icon,
    required this.value,
    required this.onTap,
    this.muted = false,
    this.trailing,
    this.trailingAsset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      onTap: onTap,
      child: Container(
        height: AppConstants.textFieldHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: AppConstants.spacingSM),
            ],
            Expanded(
              child: Text(
                value,
                style: tt.bodyLarge?.copyWith(
                  color: muted ? cs.onSurfaceVariant : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingAsset != null)
              SvgPicture.asset(
                trailingAsset!,
                width: 18,
                height: 18,
                colorFilter:
                    ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn),
              ),
            if (trailing != null)
              Icon(trailing, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Результат листа выбора нормы. Отдельный тип нужен, чтобы отличить
/// «закрыли лист» (`null`) от «выбрали Не задана» (`norm == null`).
class _NormChoice {
  final ConsumptionNorm? norm;

  const _NormChoice(this.norm);
}

/// Лист выбора нормы расхода. Фильтр тот же, что в форме создания ремонта
/// в веб-админке: нормы этого оборудования с назначением «для ремонта».
class _NormPickerSheet extends StatefulWidget {
  final String equipmentUuid;
  final String? selectedUuid;

  const _NormPickerSheet({
    required this.equipmentUuid,
    required this.selectedUuid,
  });

  @override
  State<_NormPickerSheet> createState() => _NormPickerSheetState();
}

class _NormPickerSheetState extends State<_NormPickerSheet> {
  List<ConsumptionNorm>? _norms;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Сначала кэш: без связи это единственное, из чего можно выбрать, а при
    // живой — список рисуется сразу и через миг обновляется свежим.
    //
    // Исключение — оборвавшаяся запись справочника: между `clear()` и
    // `putAll()` в боксе могла остаться половина норм, и отличить её от
    // полного набора нельзя. Такой кэш не показываем вовсе — иначе обходчик
    // выбирал бы из неполного списка, не зная об этом. Запрос ниже вернёт
    // нормы этого оборудования и заодно починит их в кэше.
    final provider = GlobalState.dataProvider;
    final cached = provider.isNormsWriteIncomplete
        ? const <ConsumptionNorm>[]
        : provider.consumptionNormsFor(widget.equipmentUuid);
    setState(() {
      _failed = false;
      if (cached.isNotEmpty) _norms = cached;
    });
    try {
      final norms = await API().getConsumptionNorms(
        equipmentUuid: widget.equipmentUuid,
      );
      // Ответ сохраняем в кэш: следующий заход в форму может случиться уже без
      // связи, и выбирать тогда будет не из чего.
      await GlobalState.dataProvider
          .cacheConsumptionNorms(widget.equipmentUuid, norms);
      if (!mounted) return;
      setState(() => _norms = norms);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _norms = cached;
        // Ошибку показываем, только когда показать больше нечего: с кэшем на
        // руках обходчику важнее список, чем сообщение о сбое.
        _failed = cached.isEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final norms = _norms;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Text(RepairStrings.normSheetTitle, style: tt.titleLarge),
          const SizedBox(height: AppConstants.spacingMD),
          Expanded(
            child: norms == null
                ? Center(
                    child: CircularProgressIndicator(color: cs.primary),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacingMD,
                      0,
                      AppConstants.spacingMD,
                      AppConstants.spacingXL,
                    ),
                    children: [
                      _NormTile(
                        title: RepairStrings.normNotSet,
                        selected: widget.selectedUuid == null,
                        onTap: () =>
                            Navigator.of(context).pop(const _NormChoice(null)),
                      ),
                      if (norms.isEmpty) ...[
                        const SizedBox(height: AppConstants.spacingLG),
                        Text(
                          _failed
                              ? RepairStrings.normLoadFailed
                              : RepairStrings.normsEmpty,
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      for (final norm in norms) ...[
                        const SizedBox(height: AppConstants.spacingSM),
                        _NormTile(
                          title: norm.name,
                          // Состав нормы прямо в строке: он и есть главный
                          // критерий выбора, прятать его в подсказку на
                          // телефоне бессмысленно — наведения нет.
                          items: norm.items,
                          selected: widget.selectedUuid == norm.uuid,
                          onTap: () =>
                              Navigator.of(context).pop(_NormChoice(norm)),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NormTile extends StatelessWidget {
  final String title;

  /// Состав нормы. Показывается маркированным списком, по позиции на строку:
  /// одной строкой через разделитель состав из четырёх позиций упирался в
  /// многоточие, а именно по нему норму и выбирают.
  final List<RepairNormItem> items;

  final bool selected;
  final VoidCallback onTap;

  const _NormTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.items = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacingSM),
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '•  ',
                                style: tt.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              Expanded(
                                child: Text(
                                  '${item.sparePartName} × '
                                  '${_formatNormQuantity(item.quantity)}',
                                  style: tt.bodyMedium
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppConstants.spacingSM),
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Колёса часов и минут — мобильный аналог `TimeWheelPicker` из админки.
class _TimeWheelSheet extends StatefulWidget {
  final TimeOfDay initial;

  const _TimeWheelSheet({required this.initial});

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;

  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Та же рамка, что у календаря: подпись, содержимое в панели с обводкой,
    // «Готово» липкой строкой снизу. Лист времени и лист даты должны
    // выглядеть одинаково — их открывают из соседних полей.
    return SheetFrame(
      onDone: () => Navigator.of(context).pop(
        TimeOfDay(hour: _hour, minute: _minute),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            RepairStrings.timeSheetTitle,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSM),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingMD),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SizedBox(
              height: 176,
              child: Stack(
                children: [
                  // Подсветка выбранной строки — как рамка выбора в админке.
                  Center(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusSM),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Wheel(
                        controller: _hourController,
                        count: 24,
                        onChanged: (value) => setState(() => _hour = value),
                      ),
                      Text(':', style: tt.titleLarge),
                      _Wheel(
                        controller: _minuteController,
                        count: 60,
                        onChanged: (value) => setState(() => _minute = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final ValueChanged<int> onChanged;

  const _Wheel({
    required this.controller,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 72,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.4,
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) => Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: tt.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Плановое количество без хвоста: «2», а не «2.0». Сервер отдаёт
/// `Numeric(14, 4)`, и «2.0000» в списке норм читать неудобно.
String _formatNormQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
