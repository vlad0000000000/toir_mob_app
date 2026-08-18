import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../global_state.dart';
import '../../strings.dart';
// Импорт библиотеки целиком, а не part-файла: ensureSparePartsLoaded
// объявлен в extension DataProviderSync и виден только через data_provider.dart.
import '../data/data_provider.dart';
import '../data/repair_photo_files.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../http/api.dart';
import '../model/pending_repair.dart';
import '../model/pending_repair_update.dart';
import '../model/repair.dart';
import '../model/repair_conflict.dart';
import '../utils/go_router_ext.dart';
import '../widgets/empty_state.dart';
import '../widgets/spare_part_consumption.dart';
import 'repair_clipboard.dart';
import 'repair_error_messages.dart';
import 'repair_status_pill.dart';
import 'spare_part_picker_sheet.dart';

/// Карточка ремонта — основной рабочий экран обходчика.
///
/// Собран по макету «Рисунок 5» из отчёта: паспорт оборудования, детали в две
/// колонки, комментарий со счётчиком, блок фактического расхода со счётчиками
/// и липкая панель «Сохранить» / «Отправить».
///
/// Редактируется только в статусе «Открыт»: сервер отклоняет правки ремонта,
/// уже отправленного на рассмотрение, поэтому и UI переходит в режим чтения.
///
/// Всегда перечитывает ремонт с сервера — в списке приходит урезанный
/// `RepairListSchema` без комментария, расхода и фотографий. Без связи
/// откатывается на офлайн-кэш активных ремонтов и накладывает поверх
/// неотправленную правку, если она есть.
class RepairDetailScreen extends StatefulWidget {
  final String repairUuid;
  final Repair? initial;

  /// Карточка открыта по локальному черновику: серверной записи ещё нет.
  /// Тогда [repairUuid] пуст, а всё, что обходчик заполнит, сохраняется
  /// обратно в очередь (п. 4.5.1 отчёта).
  final String? draftLocalId;

  const RepairDetailScreen({
    super.key,
    required this.repairUuid,
    this.initial,
    this.draftLocalId,
  });

  @override
  State<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends State<RepairDetailScreen> {
  static const int _commentLimit = 2000;

  final _commentController = TextEditingController();

  Repair? _repair;
  List<RepairConsumption> _consumptions = [];
  bool _isLoading = true;
  bool _failed = false;
  bool _isSaving = false;
  bool _isClaiming = false;
  bool _isPhotoBusy = false;

  /// Идёт действие из блока «Не отправлено»: перенос, повтор или удаление.
  bool _isUnsentBusy = false;

  /// Обходчик что-то менял в форме с момента последней загрузки с сервера.
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    if (_isDraft) {
      // У черновика нет ни серверной карточки, ни правок в очереди: он сам и
      // есть всё состояние. Грузить нечего.
      _applyRepair(_draftRepair());
      return;
    }
    // Рисуем сразу то, что уже есть: переданный из списка объект, а если его
    // не передали — запись из офлайн-кэша. Кэш читался и раньше, но только в
    // `catch` у [_load], то есть уже **после** отказа сети: без связи экран
    // висел со спиннером все 15 секунд таймаута и лишь потом показывал ремонт,
    // который всё это время лежал в Hive. Теперь запрос к серверу лишь
    // обновляет уже показанную карточку.
    _applyRepair(widget.initial ?? _cachedRepair());
    // Неотправленную правку накладываем сразу: если она есть, форма должна
    // открыться с цифрами обходчика, а не с серверными.
    _applyPendingUpdate();
    _load();
    // Каталог ЗИП нужен здесь для подбора позиций и остатков в расходе, а в
    // общей синхронизации его больше нет. В карточку попадают и напрямую —
    // из уведомления или после скана, минуя список ремонтов, — поэтому
    // подстраховываемся и тут. Экран загрузки не ждёт.
    GlobalState.dataProvider.ensureSparePartsLoaded();
  }

  bool get _isDraft => widget.draftLocalId != null;

  PendingRepair? get _draft =>
      GlobalState.dataProvider.pendingRepairBox.get(widget.draftLocalId ?? '');

  Repair? _draftRepair() {
    final draft = _draft;
    if (draft == null) return null;
    final user = GlobalState.authUser;
    return draft.toRepair(
      responsibleUuid: user?.uuid,
      responsibleName: user?.username,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Кладёт серверную версию ремонта в состояние экрана и сбрасывает форму —
  /// после сохранения или перезагрузки правки считаются принятыми.
  void _applyRepair(Repair? repair) {
    _repair = repair;
    _userEdited = false;
    if (repair == null) return;
    _commentController.text = repair.comment ?? '';
    _consumptions = List<RepairConsumption>.from(repair.actualConsumptions);
  }

  /// Отмечает, что обходчик трогал форму. Проверяется **после** ответа
  /// сервера, а не до запроса: иначе набранное, пока запрос был в полёте,
  /// затиралось бы ответом.
  void _markEdited() {
    _userEdited = true;
  }

  /// Правки доступны только по открытому ремонту, у которого обходчик —
  /// личный ответственный.
  ///
  /// Назначенный на должность и ещё никем не взятый ремонт сервер теперь
  /// разрешает только смотреть: менять его может лишь тот, кто уже указан
  /// ответственным (`_walker_can_modify_repair`). Раньше поля были активны, а
  /// кнопки «Сохранить» всё равно не было — правки просто пропадали. Теперь
  /// карточка сразу показывает, что сначала надо взять ремонт в работу.
  bool get _editable {
    final repair = _repair;
    if (repair == null) return false;
    return repair.isOpen && !repair.isUnassigned;
  }

  /// Кнопка «Сохранить» активна только при реальных изменениях — так обходчик
  /// видит, есть ли неотправленное.
  bool get _hasChanges {
    final repair = _repair;
    if (repair == null) return false;
    if (_commentController.text.trim() != (repair.comment ?? '').trim()) {
      return true;
    }
    if (_consumptions.length != repair.actualConsumptions.length) return true;
    for (final item in _consumptions) {
      RepairConsumption? original;
      for (final candidate in repair.actualConsumptions) {
        if (candidate.sparePartUuid == item.sparePartUuid) {
          original = candidate;
          break;
        }
      }
      if (original == null || original.quantity != item.quantity) return true;
    }
    return false;
  }

  int get _overNormCount => _consumptions
      .where((item) =>
          item.normQuantity != null && item.quantity > item.normQuantity!)
      .length;

  Future<void> _load() async {
    // Черновик перечитывать неоткуда — обновляем из очереди и выходим.
    if (_isDraft) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _repair = _draftRepair();
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    try {
      final repair = await API().getRepair(widget.repairUuid);
      if (!mounted) return;
      setState(() {
        // Заполненную форму серверными данными не перетираем. Признак
        // «трогали форму» и сами значения снимаем здесь, после ответа:
        // обходчик мог начать печатать, пока запрос летел.
        final keepLocalEdits = _userEdited;
        final localComment = _commentController.text;
        final localConsumptions = _consumptions;

        _applyRepair(repair);
        if (keepLocalEdits) {
          _commentController.text = localComment;
          _consumptions = localConsumptions;
          _userEdited = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Без связи показываем карточку из офлайн-кэша, а не пустой экран с
      // ошибкой: активные ремонты там лежат целиком, и обходчик в цеху
      // должен видеть ремонт и заполнять расход, а не упираться в «нет сети».
      final cached = _cachedRepair();
      setState(() {
        _isLoading = false;
        if (cached != null && !_userEdited) {
          _applyRepair(cached);
          _applyPendingUpdate();
        } else if (cached != null) {
          _repair = cached;
        } else {
          _failed = true;
        }
      });
    }
  }

  Repair? _cachedRepair() {
    for (final repair in GlobalState.dataProvider.repairs) {
      if (repair.uuid == widget.repairUuid) return repair;
    }
    return null;
  }

  /// Накладывает на форму неотправленную правку, если она есть: обходчик
  /// должен видеть **свои** цифры, а не серверные, пока правка не уехала.
  void _applyPendingUpdate() {
    final update = GlobalState.dataProvider.pendingUpdateFor(widget.repairUuid);
    if (update == null) return;
    _commentController.text = update.comment;
    _consumptions = List<RepairConsumption>.from(update.consumptions);
    // Неотправленная правка — это и есть «форма расходится с сервером».
    // Без этого признака ответ _load затёр бы её серверными значениями.
    _userEdited = true;
  }

  // ── действия ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    await _send(submitForReview: false);
  }

  Future<void> _submit() async {
    final confirmed = await _confirmSubmit();
    if (confirmed != true) return;
    await _send(submitForReview: true);
  }

  Future<void> _send({required bool submitForReview}) async {
    final repair = _repair;
    if (repair == null || _isSaving) return;
    // Черновик никуда не отправляем: правки ложатся обратно в очередь, а
    // очередь сама решит порядок — создание, фото, потом статус.
    if (_isDraft) {
      await _saveDraft(submitForReview: submitForReview);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = await API().updateRepair(
        repair.uuid,
        comment: _commentController.text.trim(),
        consumptions: _consumptions,
        submitForReview: submitForReview,
      );
      await GlobalState.dataProvider.upsertRepair(updated);
      // Уехало — очередь больше ни при чём, даже если правка там лежала.
      await GlobalState.dataProvider
          .deletePendingRepairUpdate(widget.repairUuid);
      if (!mounted) return;
      setState(() {
        _applyRepair(updated);
        _isSaving = false;
      });
      _showSnack(
        message: submitForReview
            ? RepairCardStrings.submitted
            : RepairCardStrings.saved,
        ok: true,
      );
    } catch (e) {
      if (!mounted) return;
      // Связи нет — не теряем заполненное, кладём правку в очередь. Форму при
      // этом оставляем как есть: обходчик видит свои цифры, а не серверные.
      if (isRetryableRepairError(e)) {
        await GlobalState.dataProvider.savePendingRepairUpdate(
          PendingRepairUpdate(
            repairUuid: repair.uuid,
            repairId: repair.id,
            equipmentName: repair.equipmentName,
            baseStatus: repair.status,
            createdAt: DateTime.now(),
            comment: _commentController.text.trim(),
            consumptions: List<RepairConsumption>.from(_consumptions),
            submitForReview: submitForReview,
          ),
        );
        if (!mounted) return;
        setState(() => _isSaving = false);
        _showSnack(
          message: submitForReview
              ? RepairCardStrings.queuedSubmit
              : RepairCardStrings.queuedSave,
          ok: true,
        );
        return;
      }
      setState(() => _isSaving = false);
      _showSnack(message: _messageOf(e), ok: false);
    }
  }

  /// Пишет форму обратно в черновик. При [submitForReview] помечает, что
  /// обходчик уже нажал «Отправить», и уводит в список: карточка черновика
  /// после этого только ждёт связи, править там больше нечего.
  Future<void> _saveDraft({required bool submitForReview}) async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _isSaving = true);
    await GlobalState.dataProvider.addPendingRepair(draft.copyWith(
      comment: _commentController.text.trim(),
      consumptions: List<RepairConsumption>.from(_consumptions),
      submitForReview: submitForReview ? true : draft.submitForReview,
      lastError: null,
    ));
    if (!mounted) return;
    if (submitForReview) {
      // Пытаемся отправить прямо сейчас, а не ждать фонового прохода очереди.
      // Обходчик нажал «Отправить» и должен увидеть исход здесь же — иначе
      // при живой связи карточка закрывалась раньше ответа сервера, и отказ
      // («по этому оборудованию уже есть ремонт») находился потом в списке,
      // без всякой связи с нажатием.
      //
      // Без связи проход отработает вхолостую: ошибка окажется временной,
      // пометки об отказе не появится, и мы уйдём в список — ровно как
      // обещало окно подтверждения.
      await GlobalState.dataProvider.syncPendingRepairs();
      if (!mounted) return;
      final left = _draft;
      if (left != null && left.isRejected) {
        // Сервер отказал по существу. Остаёмся на карточке: под расходом
        // появится блок с действиями — перенести в существующий ремонт или
        // скопировать данные. Причину показываем разово снекбаром: в самом
        // блоке текста нет, а тут обходчик только что нажал кнопку и ждёт
        // ответа именно на неё.
        setState(() {
          _isSaving = false;
          _applyRepair(_draftRepair());
        });
        _showSnack(message: left.lastError!, ok: false);
        return;
      }
      GoRouter.of(context).backOr('/repairs');
      return;
    }
    setState(() {
      _isSaving = false;
      _applyRepair(_draftRepair());
    });
    _showSnack(message: RepairCardStrings.queuedSave, ok: true);
  }

  Future<bool?> _confirmSubmit() async {
    final repair = _repair!;
    // Связь проверяем до показа окна: обещание «сохраним на устройстве»
    // должно быть в самом окне, а не всплыть снекбаром после нажатия.
    final offline = !await GlobalState.hasConnectionToServer;
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _SubmitConfirmDialog(
        repairId: repair.id,
        positions: _consumptions.length,
        overNorm: _overNormCount,
        offline: offline,
      ),
    );
  }

  Future<void> _claim() async {
    final repair = _repair;
    final userUuid = GlobalState.authUser?.uuid;
    if (repair == null || userUuid == null || userUuid.isEmpty) return;
    if (!await GlobalState.hasConnectionToServer) {
      _showSnack(
        message: RepairCardStrings.claimNeedsConnection,
        ok: false,
      );
      return;
    }
    setState(() => _isClaiming = true);
    try {
      final updated = await API().claimRepair(repair.uuid, userUuid);
      await GlobalState.dataProvider.upsertRepair(updated);
      if (!mounted) return;
      setState(() {
        _applyRepair(updated);
        _isClaiming = false;
      });
      _showSnack(message: RepairCardStrings.claimed, ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      _showSnack(message: _messageOf(e), ok: false);
    }
  }

  /// Добавляет недостающие позиции из состава нормы и **не перезаписывает**
  /// введённые вручную — так требует план: норма только ориентир.
  /// Позиции нормы, которых в расходе ещё нет. Считается и для кнопки
  /// «Заполнить из нормы» — она гаснет, когда добавлять нечего.
  List<RepairConsumption> get _missingNormItems {
    final repair = _repair;
    if (repair == null) return const [];
    final existing = _consumptions.map((item) => item.sparePartUuid).toSet();
    return [
      for (final normItem in repair.normItems)
        if (!existing.contains(normItem.sparePartUuid))
          RepairConsumption(
            sparePartUuid: normItem.sparePartUuid,
            sparePartName: normItem.sparePartName,
            unitName: _unitOf(normItem.sparePartUuid),
            quantity: normItem.quantity,
            normQuantity: normItem.quantity,
          ),
    ];
  }

  /// Расход в том виде, в каком его рисует общая секция.
  ///
  /// Порядок сохраняется один в один, поэтому колбэки секции продолжают
  /// приходить с индексом строки в [_consumptions].
  List<ConsumptionLine> get _consumptionLines => [
        for (final item in _consumptions)
          ConsumptionLine(
            sparePartUuid: item.sparePartUuid,
            sparePartName: item.sparePartName,
            unitName: item.unitName,
            quantity: item.quantity,
            normQuantity: item.normQuantity,
          ),
      ];

  void _fillFromNorm() {
    final added = _missingNormItems;
    if (added.isEmpty) return;
    setState(() {
      _markEdited();
      _consumptions = [..._consumptions, ...added];
    });
  }

  /// Единица измерения из локального справочника ЗИП: в составе нормы сервер
  /// её не присылает (`SparePartSchemaShort` — только uuid и название).
  static String? _unitOf(String sparePartUuid) {
    final part = GlobalState.dataProvider.sparePartByUuid(sparePartUuid);
    final unit = part?.unitLabel ?? '';
    return unit.isEmpty ? null : unit;
  }

  // ── фотографии ────────────────────────────────────────────────────────

  Future<void> _addPhoto() async {
    final repair = _repair;
    if (repair == null) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(RepairCardStrings.photoTakeShot),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(RepairCardStrings.photoFromGallery),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      // Сжимаем: снимок нужен для фотофиксации, а не для печати. Серверный
      // предел размера файла не должен быть целевым размером.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _isPhotoBusy = true);
    final bytes = await picked.readAsBytes();
    // У черновика отправлять снимок некуда — ремонта на сервере ещё нет
    // (п. 4.5.5). Кладём файл и путь сразу в очередь.
    final draft = _draft;
    if (draft != null) {
      final path = await RepairPhotoFiles.save(bytes);
      await GlobalState.dataProvider.addPendingRepair(
        draft.copyWith(photoPaths: [...draft.photoPaths, path]),
      );
      if (!mounted) return;
      setState(() => _isPhotoBusy = false);
      _showSnack(message: RepairCardStrings.photoQueued, ok: true);
      return;
    }
    try {
      // Ключ от содержимого кадра: если ответ потеряется и снимок уйдёт в
      // очередь (ветка ниже), повтор оттуда придёт с тем же ключом, и сервер
      // вернёт уже сохранённый снимок вместо второй копии.
      await API().uploadRepairPhotos(
        repair.uuid,
        [base64Encode(bytes)],
        idempotencyKey: RepairPhotoFiles.idempotencyKey(repair.uuid, bytes),
      );
      await _reloadAfterPhotoChange();
      _showSnack(message: RepairCardStrings.photoAdded, ok: true);
    } catch (e) {
      if (!mounted) return;
      // Связи нет — снимок кладём файлом на устройство и ставим в очередь.
      // Терять кадр, который обходчик уже сделал у станка, нельзя: второй раз
      // он туда не пойдёт.
      if (isRetryableRepairError(e)) {
        final path = await RepairPhotoFiles.save(bytes);
        await _queuePhotoChange(addPath: path);
        if (!mounted) return;
        setState(() => _isPhotoBusy = false);
        _showSnack(message: RepairCardStrings.photoQueued, ok: true);
        return;
      }
      setState(() => _isPhotoBusy = false);
      _showSnack(message: _messageOf(e), ok: false);
    }
  }

  Future<void> _removePhoto(RepairPhoto photo) async {
    final repair = _repair;
    if (repair == null) return;
    setState(() => _isPhotoBusy = true);
    try {
      await API().deleteRepairPhoto(repair.uuid, photo.uuid);
      await _reloadAfterPhotoChange();
    } catch (e) {
      if (!mounted) return;
      if (isRetryableRepairError(e)) {
        await _queuePhotoChange(deleteUuid: photo.uuid);
        if (!mounted) return;
        setState(() => _isPhotoBusy = false);
        return;
      }
      setState(() => _isPhotoBusy = false);
      _showSnack(message: _messageOf(e), ok: false);
    }
  }

  /// Снятый без связи снимок ждёт отправки прямо в очереди правок этого
  /// ремонта — отдельной очереди для фотографий нет: они всё равно уезжают
  /// вместе с комментарием и расходом, и порядок между ними важен.
  Future<void> _queuePhotoChange({String? addPath, String? deleteUuid}) async {
    final repair = _repair!;
    final provider = GlobalState.dataProvider;
    final existing = provider.pendingUpdateFor(repair.uuid);
    await provider.savePendingRepairUpdate(PendingRepairUpdate(
      repairUuid: repair.uuid,
      repairId: repair.id,
      equipmentName: repair.equipmentName,
      baseStatus: repair.status,
      createdAt: DateTime.now(),
      // Форму подхватываем как есть: если обходчик что-то набрал и ещё не
      // сохранил, снимок не должен эти правки затереть.
      comment: _commentController.text.trim(),
      consumptions: List<RepairConsumption>.from(_consumptions),
      submitForReview: existing?.submitForReview ?? false,
      photoPaths: [
        ...?existing?.photoPaths,
        if (addPath != null) addPath,
      ],
      deletedPhotoUuids: [
        ...?existing?.deletedPhotoUuids,
        if (deleteUuid != null) deleteUuid,
      ],
    ));
  }

  /// Снимки, ждущие отправки, и uuid'ы удалённых без связи — их прячем.
  PendingRepairUpdate? get _pendingPhotos =>
      GlobalState.dataProvider.pendingUpdateFor(widget.repairUuid);

  /// Что показать в полосе: принятые сервером снимки минус удалённые офлайн,
  /// плюс ещё не отправленные файлы.
  List<RepairPhotoView> get _photoViews {
    // У черновика снимки только локальные — серверных ещё нет.
    final draft = _draft;
    if (draft != null) {
      return [for (final path in draft.photoPaths) RepairPhotoView.local(path)];
    }
    final pending = _pendingPhotos;
    final hidden = pending?.deletedPhotoUuids.toSet() ?? const <String>{};
    return [
      for (final photo in _repair?.photos ?? const <RepairPhoto>[])
        if (!hidden.contains(photo.uuid)) RepairPhotoView.remote(photo),
      for (final path in pending?.photoPaths ?? const <String>[])
        RepairPhotoView.local(path),
    ];
  }

  /// Убрать снимок, который ещё не уехал: достаточно вычеркнуть путь и
  /// удалить файл — сервер о нём не знает.
  Future<void> _removeLocalPhoto(String path) async {
    final provider = GlobalState.dataProvider;
    final draft = _draft;
    if (draft != null) {
      await provider.addPendingRepair(draft.copyWith(
        photoPaths: draft.photoPaths.where((item) => item != path).toList(),
      ));
      await RepairPhotoFiles.delete(path);
      if (!mounted) return;
      setState(() {});
      return;
    }
    final existing = provider.pendingUpdateFor(widget.repairUuid);
    if (existing == null) return;
    final left = existing.photoPaths.where((item) => item != path).toList();
    await provider.savePendingRepairUpdate(existing.copyWith(
      lastError: existing.lastError,
      serverStatus: existing.serverStatus,
      conflictKind: existing.conflictKind,
      photoPaths: left,
    ));
    await RepairPhotoFiles.delete(path);
    if (!mounted) return;
    setState(() {});
  }

  /// Фотографии живут отдельными запросами, поэтому после их изменения
  /// перечитываем ремонт целиком — иначе список на экране разойдётся с
  /// сервером. Несохранённые правки формы при этом сохраняем.
  Future<void> _reloadAfterPhotoChange() async {
    final comment = _commentController.text;
    final consumptions = _consumptions;
    final updated = await API().getRepair(widget.repairUuid);
    await GlobalState.dataProvider.upsertRepair(updated);
    if (!mounted) return;
    setState(() {
      _repair = updated;
      _commentController.text = comment;
      _consumptions = consumptions;
      _isPhotoBusy = false;
    });
  }

  Future<void> _addPosition() async {
    final picked = await showSparePartPicker(
      context,
      alreadyAddedUuids:
          _consumptions.map((item) => item.sparePartUuid).toSet(),
    );
    if (picked == null || !mounted) return;
    // Если позиция есть в норме — подхватываем плановое количество, иначе
    // строка добавленная вручную не показывала бы «Норма N» и отклонение,
    // хотя норма для неё существует.
    double? norm;
    for (final normItem in _repair?.normItems ?? const <RepairNormItem>[]) {
      if (normItem.sparePartUuid == picked.uuid) {
        norm = normItem.quantity;
        break;
      }
    }
    setState(() {
      _markEdited();
      _consumptions = [
        ..._consumptions,
        RepairConsumption(
          sparePartUuid: picked.uuid,
          sparePartName: picked.name,
          unitName: picked.unitLabel.isEmpty ? null : picked.unitLabel,
          quantity: 1,
          normQuantity: norm,
        ),
      ];
    });
  }

  void _changeQuantity(int index, double delta) {
    final next = _consumptions[index].quantity + delta;
    if (next < 1) return;
    _setQuantity(index, next);
  }

  /// Ввод количества руками. Ноль и отрицательные не принимаем: сервер
  /// требует `quantity > 0`, а позиция с нулём молча пропала бы при отправке.
  void _setQuantity(int index, double value) {
    if (value <= 0) return;
    final item = _consumptions[index];
    if (item.quantity == value) return;
    setState(() {
      _markEdited();
      _consumptions = [..._consumptions];
      _consumptions[index] = RepairConsumption(
        sparePartUuid: item.sparePartUuid,
        sparePartName: item.sparePartName,
        unitName: item.unitName,
        quantity: value,
        normQuantity: item.normQuantity,
      );
    });
  }

  void _removePosition(int index) {
    setState(() {
      _markEdited();
      _consumptions = [..._consumptions]..removeAt(index);
    });
  }

  void _showSnack({required String message, required bool ok}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final fg = ok ? cs.onSuccess : cs.onError;
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
            child: Text(
              message,
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
      backgroundColor: ok ? cs.success : cs.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  static String _messageOf(Object error) => repairErrorMessage(error);

  // ── разметка ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repair = _repair;

    return Scaffold(
      // Свой AppBar, а не MyAppBar: в заголовке номер ремонта, справа пилюля
      // статуса — общий AppBar ветвится по строке маршрута и таких данных
      // не знает. Так же сделан экран уведомлений.
      appBar: AppBar(
        leading: BackButton(
          // Возврат туда, откуда открыли карточку: список ремонтов, карточка
          // оборудования после скана или уведомление. Список — запасной
          // адрес, когда стек пуст (переход по пуш-уведомлению).
          onPressed: () => GoRouter.of(context).backOr('/repairs'),
        ),
        // У черновика номера нет — сервер выдаст его при создании.
        title: Text(repair == null || repair.id == 0
            ? RepairCardStrings.title
            : RepairCardStrings.titleWithId(repair.id)),
        actions: [
          if (repair != null)
            Padding(
              padding: const EdgeInsets.only(right: AppConstants.spacingMD),
              child: Center(child: RepairStatusPill(status: repair.status)),
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(cs, repair)),
      bottomNavigationBar: _buildBottomBar(repair),
    );
  }

  /// Неотправленная правка существующего ремонта. У черновика её не бывает:
  /// он сам целиком и есть неотправленное.
  PendingRepairUpdate? get _pendingUpdate =>
      GlobalState.dataProvider.pendingUpdateFor(widget.repairUuid);

  /// Ремонт, занявший оборудование и не давший черновику создаться.
  ///
  /// `null` — либо конфликта не было, либо ремонт чужой: чужие обходчику не
  /// отдают, и в кэше его нет.
  Repair? _blockingRepair(PendingRepair draft) {
    final uuid = draft.conflictRepairUuid;
    if (uuid == null || uuid.isEmpty) return null;
    for (final repair in GlobalState.dataProvider.repairs) {
      if (repair.uuid == uuid) return repair;
    }
    return null;
  }

  /// Вид отказа. У правки он определён очередью в момент отказа, у черновика
  /// выводится из того, чей ремонт занял оборудование: сервер сообщает только
  /// сам факт занятости.
  RepairConflictKind _conflictKind(
      PendingRepair? draft, PendingRepairUpdate? update) {
    if (update != null) return update.kind;
    final blocking = _blockingRepair(draft!);
    if (blocking == null) return RepairConflictKind.equipmentBusyOther;
    final me = GlobalState.authUser?.uuid;
    final owner = blocking.responsibleUserUuid;
    final mine = me != null && owner != null && owner.isNotEmpty && owner == me;
    return mine
        ? RepairConflictKind.equipmentBusyMine
        : RepairConflictKind.equipmentBusyOther;
  }

  /// Переносит данные черновика в уже существующий ремонт.
  ///
  /// Возможно только когда оборудование занял ремонт самого обходчика: чужой
  /// расход подтверждать он не вправе. Уходим сразу в карточку получателя —
  /// дальше работать там; черновика после переноса не существует.
  Future<void> _transferDraft(PendingRepair draft, Repair target) async {
    setState(() => _isUnsentBusy = true);
    await GlobalState.dataProvider.transferDraftToRepair(draft, target);
    if (!mounted) return;
    final router = GoRouter.of(context);
    router.pop();
    router.push('/repairs/${target.uuid}', extra: target);
  }

  /// Отправляет неотправленное прямо сейчас, не дожидаясь прохода очереди.
  Future<void> _retryUnsent(
      PendingRepair? draft, PendingRepairUpdate? update) async {
    setState(() => _isUnsentBusy = true);
    final provider = GlobalState.dataProvider;
    if (draft != null) {
      await provider.retryPendingRepair(draft.localId);
      if (!mounted) return;
      final left = _draft;
      if (left == null) {
        // Черновик уехал и стал настоящим ремонтом — на этой карточке его
        // больше нет. В списке он уже с сервера.
        GoRouter.of(context).backOr('/repairs');
        return;
      }
      setState(() => _isUnsentBusy = false);
      // Отказ повторился — говорим об этом, иначе нажатие выглядит как
      // молчаливо ничего не сделавшее.
      if (left.isRejected) _showSnack(message: left.lastError!, ok: false);
      return;
    }
    await provider.retryPendingRepairUpdate(widget.repairUuid);
    if (!mounted) return;
    setState(() => _isUnsentBusy = false);
    await _load();
  }

  /// Третья кнопка блока — та, что зависит от причины отказа.
  ///
  /// `null` — делать нечего: сервер отказал окончательно, и остаётся только
  /// скопировать данные и удалить. Иначе либо переносим в свой ремонт, либо
  /// пробуем отправить ещё раз.
  Widget? _unsentPrimaryAction(
      PendingRepair? draft, PendingRepairUpdate? update, bool rejected) {
    final busy = _isUnsentBusy || _isSaving;
    if (draft != null && rejected) {
      final kind = _conflictKind(draft, null);
      final blocking = _blockingRepair(draft);
      if (kind.canTransfer && blocking != null) {
        return ElevatedButton.icon(
          onPressed: busy ? null : () => _transferDraft(draft, blocking),
          icon: const Icon(Icons.move_down_rounded, size: 20),
          label: Text(ConflictStrings.transferTo(blocking.id)),
        );
      }
    }
    // Окончательный отказ повторять бессмысленно: сервер ответит тем же.
    // Пока связи нет, отказа ещё не было — «повторить» значит «отправить
    // сейчас», не дожидаясь очередного прохода очереди.
    if (rejected && _conflictKind(draft, update).isFinal) return null;
    return ElevatedButton.icon(
      onPressed: busy ? null : () => _retryUnsent(draft, update),
      icon: const Icon(Icons.refresh_rounded, size: 20),
      label: const Text(ConflictStrings.retry),
    );
  }

  /// Кладёт неотправленные данные в буфер обмена.
  ///
  /// Берём из формы, а не из сохранённой записи: обходчик мог только что
  /// дописать комментарий или добавить позицию расхода и ещё не нажать
  /// «Сохранить» — скопировать надо то, что он видит на экране.
  Future<void> _copyUnsent() async {
    // `_repair` подходит и черновику: у него это `PendingRepair.toRepair()`,
    // где уже собраны оборудование, норма, ответственный и даты. Отдельной
    // ветки на черновик не нужно.
    final repair = _repair;
    if (repair == null) return;
    await Clipboard.setData(ClipboardData(
      text: repairClipboardText(
        repair: repair,
        comment: _commentController.text,
        consumptions: _consumptions,
      ),
    ));
    if (!mounted) return;
    _showSnack(message: ConflictStrings.copied, ok: true);
  }

  /// Блок неотправленного — последним в форме, под расходом.
  ///
  /// Раньше на его месте была красная полоса поверх карточки с кнопкой
  /// «Разобраться», уводившей на отдельный экран. Экран показывал те же
  /// комментарий и расход второй раз, а его заголовок настоящую причину не
  /// называл. Теперь здесь только действия: отправить ещё раз или перенести —
  /// и скопировать данные, чтобы передать их администратору.
  ///
  /// Текста причины в блоке нет намеренно: у отказа сервера формулировки
  /// служебные («Не удалось выполнить действие»), и обходчику они ничего не
  /// дают. Что ремонт не уехал, видно по самому блоку и по карточке в списке.
  List<Widget> _buildUnsentSection(ColorScheme cs) {
    final draft = _draft;
    final update = draft == null ? _pendingUpdate : null;
    if (draft == null && update == null) return const [];
    final rejected = draft?.isRejected ?? update!.isRejected;
    final busy = _isSaving || _isUnsentBusy;
    final primary = _unsentPrimaryAction(draft, update, rejected);
    return [
      Divider(color: cs.outlineVariant, height: AppConstants.spacingLG * 2),
      _SectionLabel(RepairCardStrings.labelUnsent),
      const SizedBox(height: AppConstants.spacingSM),
      // В столбик, а не в строку: подписи со значком в половину ширины не
      // помещаются. Первой — та, что зависит от причины отказа.
      if (primary != null) ...[
        SizedBox(
          width: double.infinity,
          height: AppConstants.buttonHeight,
          child: primary,
        ),
        const SizedBox(height: AppConstants.spacingSM),
      ],
      SizedBox(
        width: double.infinity,
        height: AppConstants.buttonHeight,
        child: OutlinedButton.icon(
          onPressed: busy ? null : _copyUnsent,
          // Значок чёрным, а не в цвет подписи: копирование — служебное
          // действие, и выделять его наравне с отправкой незачем.
          icon: Icon(Icons.copy_rounded, size: 20, color: cs.onSurface),
          label: const Text(ConflictStrings.copyToClipboard),
        ),
      ),
    ];
  }

  Widget _buildBody(ColorScheme cs, Repair? repair) {
    if (repair == null && _isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: cs.primary,
          strokeWidth: 8,
          constraints: const BoxConstraints(minHeight: 128, minWidth: 128),
        ),
      );
    }
    if (repair == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: RepairCardStrings.loadFailedTitle,
            hint: RepairCardStrings.loadFailedHint,
          ),
        ],
      );
    }

    // Полоса снимков собирается один раз: она нужна и счётчику в заголовке,
    // и самой полосе.
    final photos = _photoViews;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMD,
        AppConstants.spacingMD,
        AppConstants.spacingMD,
        AppConstants.spacingXL,
      ),
      children: [
        // Причина, по которой ремонт не уехал, теперь стоит внизу формы —
        // см. [_buildUnsentSection].
        if (_failed) ...[
          // Без значка и по центру — как остальные полосы про отсутствие связи.
          _Banner(
            text: RepairCardStrings.staleDataBanner,
          ),
          const SizedBox(height: AppConstants.spacingMD),
        ],
        // Ремонт вне статуса «Открыт» правкам не подлежит — говорим об этом
        // сразу, а не оставляем гадать, почему всё серое.
        if (!_editable && !repair.isUnassigned) ...[
          // Без значка: текст занимает всю ширину, и отступы со всех сторон
          // получаются одинаковыми — плашка выглядит ровно.
          //
          // Цвет по статусу: «на рассмотрении» оранжевым — работа сдана, ждём
          // администратора; «закрыт» нейтрально-серым — это уже не
          // предупреждение, а констатация.
          _Banner(
            text: repair.isClosed
                ? RepairCardStrings.lockedClosed
                : RepairCardStrings.lockedUnderReview,
            warning: !repair.isClosed,
          ),
          const SizedBox(height: AppConstants.spacingMD),
        ],
        _EquipmentCard(repair: repair),
        const SizedBox(height: AppConstants.spacingLG),
        _SectionLabel(RepairCardStrings.labelDetails),
        const SizedBox(height: AppConstants.spacingSM),
        _DetailsGrid(repair: repair),
        const SizedBox(height: AppConstants.spacingLG),
        _SectionLabel(RepairCardStrings.labelComment),
        const SizedBox(height: AppConstants.spacingSM),
        TextField(
          controller: _commentController,
          enabled: _editable,
          minLines: 3,
          maxLines: 6,
          maxLength: _commentLimit,
          onChanged: (_) => setState(_markEdited),
          decoration: const InputDecoration(
            hintText: RepairCardStrings.commentHint,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSM),
        _SectionLabel(
          RepairCardStrings.labelPhotos,
          // Считаем и неотправленные: предел в десять снимков сервер проверяет
          // по факту, и обходчик должен видеть, сколько наберётся после
          // отправки, а не сколько уже доехало.
          trailing: _CountChip(
            count: photos.length,
            total: _PhotoStrip.maxPhotos,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSM),
        _PhotoStrip(
          photos: photos,
          editable: _editable,
          busy: _isPhotoBusy,
          onAdd: _addPhoto,
          onRemove: (view) {
            final local = view.localPath;
            if (local != null) {
              _removeLocalPhoto(local);
            } else {
              _removePhoto(view.remote!);
            }
          },
        ),
        const SizedBox(height: AppConstants.spacingSM),
        // Разделитель раньше рисовала сама секция расхода. Теперь секция общая
        // с экраном осмотра, где она стоит между другими блоками формы и
        // отбивка сверху не нужна, — поэтому здесь она своя.
        Divider(color: cs.outlineVariant, height: AppConstants.spacingLG * 2),
        SparePartConsumptionSection(
          lines: _consumptionLines,
          editable: _editable,
          // Ремонт закрыт — значит ЗИП уже списан со склада, и сравнение
          // расхода с остатком дало бы ложную тревогу про позицию, которая
          // как раз этим ремонтом и была списана.
          showStockWarnings: !repair.isClosed,
          hasNorm: repair.normItems.isNotEmpty,
          // Кнопка гаснет, когда добавлять уже нечего (п. 4.3.9 отчёта):
          // нажимать её ради снекбара «всё добавлено» бессмысленно.
          canFillFromNorm: _missingNormItems.isNotEmpty,
          onAdd: _addPosition,
          onFillFromNorm: _fillFromNorm,
          onChangeQuantity: _changeQuantity,
          onSetQuantity: _setQuantity,
          onRemove: _removePosition,
        ),
        ..._buildUnsentSection(cs),
      ],
    );
  }

  Widget? _buildBottomBar(Repair? repair) {
    if (repair == null) return null;
    if (repair.isUnassigned && repair.isOpen) {
      return _BottomBar(
        children: [
          Expanded(
            // Без значка — остаётся один текст. Спиннер на время запроса
            // подставляется вместо него, иначе кнопка выглядела бы
            // неотзывчивой: другой обратной связи у неё нет.
            child: ElevatedButton(
              onPressed: _isClaiming ? null : _claim,
              child: _isClaiming
                  ? const _ButtonSpinner()
                  : const Text(RepairCardStrings.claim),
            ),
          ),
        ],
      );
    }
    if (!_editable) return null;
    return _BottomBar(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _hasChanges && !_isSaving ? _save : null,
            child: const Text(RepairCardStrings.save),
          ),
        ),
        const SizedBox(width: AppConstants.spacingMD),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _submit,
            icon: _isSaving
                ? const _ButtonSpinner()
                : const Icon(Icons.send_rounded),
            label: const Text(RepairCardStrings.submit),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Паспорт оборудования
// ─────────────────────────────────────────────────────────────────────────
class _EquipmentCard extends StatelessWidget {
  final Repair repair;

  const _EquipmentCard({required this.repair});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
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
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
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
                  Text(
                    repair.equipmentName.isEmpty
                        ? RepairStrings.equipmentUnknown
                        : repair.equipmentName,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (repair.equipmentTypeModel != null &&
                      repair.equipmentTypeModel!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      repair.equipmentTypeModel!,
                      style:
                          tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Детали ремонта — две колонки, только чтение
// ─────────────────────────────────────────────────────────────────────────
class _DetailsGrid extends StatelessWidget {
  final Repair repair;

  const _DetailsGrid({required this.repair});

  static String _formatDate(DateTime value) =>
      DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    // Исполнитель и должность — два разных реквизита, как в админке. Раньше
    // они склеивались в одну строку («тест (не назначен)»), и у свободного
    // ремонта выходило, будто ответственный есть, просто со скобкой.
    final responsible =
        repair.responsibleUserFullname?.trim().isNotEmpty == true
            ? repair.responsibleUserFullname!
            : RepairCardStrings.responsibleNone;
    final role = repair.responsibleRoleName?.trim().isNotEmpty == true
        ? repair.responsibleRoleName!
        : RepairCardStrings.responsibleRoleNone;

    // Порядок: ответственный, должность, норма расхода, дата начала, дата
    // окончания, длительность. Поля, которых у ремонта ещё нет (окончание у
    // открытого, длительность до завершения), просто не показываются — пустая
    // подпись сбивала бы. Раскладываем по два в ряд, добивая непарное пустой
    // ячейкой.
    final fields = <Widget>[
      _Field(
        label: RepairCardStrings.fieldResponsible,
        value: responsible,
      ),
      _Field(
        label: RepairCardStrings.fieldResponsibleRole,
        value: role,
      ),
      _Field(
        label: RepairCardStrings.fieldNorm,
        value: repair.consumptionNormName?.trim().isNotEmpty == true
            ? repair.consumptionNormName!
            : RepairCardStrings.normNotSet,
      ),
      _Field(
        label: RepairCardStrings.fieldStartedAt,
        value: _formatDate(repair.startedAt),
      ),
      if (repair.underReviewAt != null)
        _Field(
          label: RepairCardStrings.fieldFinishedAt,
          value: _formatDate(repair.underReviewAt!),
        ),
      if (repair.duration != null && repair.duration!.isNotEmpty)
        _Field(
          label: RepairCardStrings.fieldDuration,
          value: repair.duration!,
        ),
    ];

    return Column(
      children: [
        for (var i = 0; i < fields.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingMD),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[i]),
              const SizedBox(width: AppConstants.spacingMD),
              Expanded(
                child: i + 1 < fields.length
                    ? fields[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: tt.bodyLarge),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Фотографии ремонта
// ─────────────────────────────────────────────────────────────────────────
/// Полоса фотографий ремонта.
///
/// Форма повторяет секцию фото на экране осмотра (`_PhotoStrip` в
/// `result_controls.dart`): пока снимков нет — одна широкая кнопка
/// «Добавить фото» вместо ряда пустых ячеек, дальше — слоты равной высоты
/// 80 px. Так два экрана приложения выглядят одинаково.
/// Снимок в полосе: либо принятый сервером, либо файл на устройстве, ждущий
/// отправки. Полосе нужен один тип — рисуются они одинаково, разница только в
/// источнике картинки и в пометке «ещё не уехал».
class RepairPhotoView {
  final RepairPhoto? remote;
  final String? localPath;

  const RepairPhotoView.remote(RepairPhoto photo)
      : remote = photo,
        localPath = null;

  const RepairPhotoView.local(String path)
      : remote = null,
        localPath = path;

  bool get isLocal => localPath != null;

  /// Ключ для списков: у серверного — uuid, у локального — путь к файлу.
  String get key => remote?.uuid ?? localPath!;

  Widget image({BoxFit? fit, required Widget errorIcon}) {
    final path = localPath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder: (_, __, ___) => errorIcon,
      );
    }
    return Image.network(
      remote!.url,
      fit: fit,
      errorBuilder: (_, __, ___) => errorIcon,
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  static const int maxPhotos = 10;

  /// Высота полосы — как у осмотра.
  static const double _slotHeight = 80;

  /// Сколько слотов помещается в ряд, чтобы снимки не превращались в марки.
  static const int _slotsPerRow = 3;

  final List<RepairPhotoView> photos;
  final bool editable;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(RepairPhotoView photo) onRemove;

  const _PhotoStrip({
    required this.photos,
    required this.editable,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  void _openLightbox(BuildContext context, RepairPhotoView photo) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppConstants.spacingMD),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: photo.image(
                errorIcon: const Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: Colors.white70,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: RepairCardStrings.close,
              onPressed: () => Navigator.of(ctx).pop(),
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

    if (photos.isEmpty && !editable) {
      return Text(
        RepairCardStrings.photosEmpty,
        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    // Пока снимков нет — одна широкая кнопка вместо ряда пустых ячеек:
    // экономнее по месту и понятнее, что делать.
    if (photos.isEmpty) {
      return Material(
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        child: InkWell(
          onTap: busy ? null : onAdd,
          child: SizedBox(
            height: _slotHeight,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.primary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded,
                            color: cs.primary, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          RepairCardStrings.photoAdd,
                          style: tt.titleMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    // Снимков может быть до десяти — раскладываем рядами по три, сохраняя
    // высоту слота из осмотра.
    final canAddMore = editable && photos.length < maxPhotos;
    final slots = <Widget>[
      for (final photo in photos)
        _PhotoSlot(
          photo: photo,
          editable: editable,
          busy: busy,
          onPreview: () => _openLightbox(context, photo),
          onRemove: () => onRemove(photo),
        ),
      if (canAddMore) _AddPhotoSlot(busy: busy, onTap: busy ? null : onAdd),
    ];

    return Column(
      children: [
        for (var start = 0; start < slots.length; start += _slotsPerRow) ...[
          if (start > 0) const SizedBox(height: AppConstants.spacingSM),
          SizedBox(
            height: _slotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start;
                    i < start + _slotsPerRow && i < slots.length;
                    i++) ...[
                  if (i > start) const SizedBox(width: AppConstants.spacingSM),
                  Expanded(child: slots[i]),
                ],
                // Добиваем неполный ряд пустотой, чтобы последние снимки не
                // растягивались на всю ширину.
                for (var i = slots.length; i < start + _slotsPerRow; i++) ...[
                  const SizedBox(width: AppConstants.spacingSM),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Слот с фотографией: тап — просмотр, крестик — удаление.
class _PhotoSlot extends StatelessWidget {
  final RepairPhotoView photo;
  final bool editable;
  final bool busy;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  const _PhotoSlot({
    required this.photo,
    required this.editable,
    required this.busy,
    required this.onPreview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Material(
            color: cs.surfaceContainerHigh,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              side: BorderSide(color: cs.outlineVariant, width: 0.5),
            ),
            child: InkWell(
              onTap: onPreview,
              child: photo.image(
                fit: BoxFit.cover,
                errorIcon: Icon(
                  Icons.broken_image_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        // Уголок у неотправленного снимка: обходчик должен видеть, что кадр
        // ещё на устройстве, а не на сервере.
        if (photo.isLocal)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        if (editable)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onRemove,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child:
                      Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Пустой слот «добавить ещё» — той же формы, что и слот со снимком.
class _AddPhotoSlot extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _AddPhotoSlot({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        side: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: cs.primary,
                  ),
                )
              : Icon(Icons.add_a_photo_outlined,
                  color: cs.onSurfaceVariant, size: 22),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Диалог «Завершить ремонт»
// ─────────────────────────────────────────────────────────────────────────
/// Диалог подтверждения отправки на рассмотрение — по макету «Рисунок 9».
///
/// Три вида на одном каркасе: со сводкой расхода, без заполненного расхода и
/// без связи. Отличаются значком в шапке, содержимым под подзаголовком и
/// подписью на кнопке действия.
class _SubmitConfirmDialog extends StatelessWidget {
  final int repairId;
  final int positions;
  final int overNorm;

  /// Связи нет: ремонт уйдёт в очередь, а не на сервер. Обещать это можно
  /// только теперь, когда очередь есть (п. 4.3.13 отчёта).
  final bool offline;

  const _SubmitConfirmDialog({
    required this.repairId,
    required this.positions,
    required this.overNorm,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Без связи сводка всё равно верна — она считается по форме, а не по
    // серверу, поэтому «нет связи» и «расход не заполнен» не спорят друг с
    // другом: значок выбирает офлайн, а плашку снизу — пустой расход.
    final noConsumption = positions == 0;

    return Dialog(
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
            // Значок сверху по центру: зелёная «галочка в круге» либо
            // оранжевая «i», когда расход не заполнен.
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: offline || noConsumption
                    ? cs.warningContainer
                    : cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              ),
              child: Icon(
                offline
                    ? Icons.cloud_off_rounded
                    : noConsumption
                        ? Icons.info_outline_rounded
                        : Icons.check_circle_outline_rounded,
                size: 36,
                color: offline || noConsumption ? cs.warning : cs.primary,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMD),
            Text(
              RepairCardStrings.finishTitle(repairId),
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingSM),
            // Название нового статуса — цветом этого статуса, как в макете.
            Text.rich(
              TextSpan(
                style: tt.bodyLarge,
                children: [
                  const TextSpan(text: RepairCardStrings.finishBodyPrefix),
                  TextSpan(
                    text: RepairCardStrings.finishStatusUnderReview,
                    style: TextStyle(
                      color: cs.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            if (!noConsumption) ...[
              const SizedBox(height: AppConstants.spacingMD),
              Text(
                RepairCardStrings.finishBodySuffix,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppConstants.spacingMD),
            if (offline) ...[
              // Без значка и по центру: в диалоге уже отцентрованы заголовок,
              // пояснение и плитки сводки, и полоса со значком слева ломала
              // бы этот ряд.
              _Banner(
                text: RepairCardStrings.finishOffline,
                warning: true,
              ),
              const SizedBox(height: AppConstants.spacingSM),
            ],
            if (noConsumption)
              _Banner(
                text: RepairCardStrings.finishNoConsumption,
                warning: true,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      value: '$positions',
                      caption: RepairCardStrings.finishCaptionPositions,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSM),
                  Expanded(
                    child: _SummaryTile(
                      value: '$overNorm',
                      caption: RepairCardStrings.finishCaptionOverNorm,
                      warning: overNorm > 0,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppConstants.spacingLG),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кнопки друг под другом, а не в ряд. В ряду каждой доставалась
                // половина ширины, и «Завершить и сохранить» со значком туда не
                // помещалось: подпись переносилась на вторую строку, а высота
                // кнопки фиксированная — вторую строку срезало. На всю ширину
                // помещается любая подпись, в том числе при увеличенном
                // системном шрифте. Так же выглядят подтверждения на других
                // экранах: главное действие широкой кнопкой, отказ под ним.
                SizedBox(
                  width: double.infinity,
                  height: AppConstants.buttonHeightLarge,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icon(
                      offline ? Icons.save_outlined : Icons.send_rounded,
                      size: 20,
                    ),
                    label: Text(
                      offline
                          ? RepairCardStrings.finishAndSave
                          : RepairCardStrings.submit,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingSM),
                SizedBox(
                  width: double.infinity,
                  height: AppConstants.buttonHeightLarge,
                  child: ElevatedButton(
                    // Вторичная кнопка в макете — заливка серым, а не
                    // обводка: обе кнопки одинаковой «плотности».
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.surfaceContainer,
                      foregroundColor: cs.onSurface,
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(RepairStrings.cancel, maxLines: 1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Плитка сводки: крупное число сверху, подпись снизу.
class _SummaryTile extends StatelessWidget {
  final String value;
  final String caption;
  final bool warning;

  const _SummaryTile({
    required this.value,
    required this.caption,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = warning ? cs.warning : cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingSM,
        vertical: AppConstants.spacingMD,
      ),
      decoration: BoxDecoration(
        color: warning ? cs.warningContainer : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: tt.bodySmall?.copyWith(
              color: warning ? cs.warning : cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Мелочи
// ─────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;

  /// Правый край строки-заголовка: счётчик «0 из 10» у секции фото.
  final Widget? trailing;

  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = Text(
      text,
      style: tt.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
    if (trailing == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        trailing!,
      ],
    );
  }
}

/// Счётчик «N из M» справа от заголовка секции. Форма и поведение — как в
/// секции фото на экране осмотра (`_CountChip` в `result_controls.dart`):
/// пока ничего не выбрано, серый; появилось хоть одно — зелёный.
class _CountChip extends StatelessWidget {
  final int count;
  final int total;

  const _CountChip({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Text(
      RepairCardStrings.countOf(count, total),
      style: tt.labelSmall?.copyWith(
        color: count > 0 ? cs.primary : cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// Плашка-предупреждение. Значок необязателен: без него текст занимает всю
/// ширину и блок выглядит ровнее — отступы со всех сторон одинаковые.
/// Полоса-пояснение: одна фраза на цветной подложке.
///
/// Всегда без значка и всегда по центру. Значок ничего не добавлял к тексту —
/// он повторял ту же мысль картинкой, — а прижатый влево текст оставлял справа
/// пустое поле, и полоса выглядела перекошенной. Единственное, чем полосы
/// отличаются друг от друга, — цвет: [warning] для того, что требует внимания.
class _Banner extends StatelessWidget {
  final String text;
  final bool warning;

  const _Banner({required this.text, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = warning ? cs.warning : cs.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: tt.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// Липкая нижняя панель — по эталону `_SubmitBar` с экрана результата скана.
class _BottomBar extends StatelessWidget {
  final List<Widget> children;

  const _BottomBar({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
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
        child: SizedBox(
          height: 56,
          child: Row(children: children),
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
