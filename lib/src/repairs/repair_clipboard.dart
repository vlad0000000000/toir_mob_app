import 'package:intl/intl.dart';

import '../../strings.dart';
import '../model/repair.dart';
import '../widgets/spare_part_row.dart';

/// Все данные ремонта одним текстом — для буфера обмена.
///
/// Нужен там, где обходчик отправить ремонт не может, а данные терять нельзя:
/// на карточке черновика (связи нет) и при отказе сервера. Текст пересылают
/// администратору, чтобы тот внёс всё руками, поэтому подписи развёрнутые, а
/// поля — те же, что обходчик видит на карточке.
///
/// [repair] — состояние ремонта, [comment] и [consumptions] берутся из формы
/// отдельно: обходчик мог дописать их и не нажать «Сохранить», а скопировать
/// нужно то, что на экране.
///
/// **Фотографий в тексте нет** — в буфер обмена они не помещаются, и передать
/// их можно только отдельно.
///
/// Пустые поля пропускаются: строка «Дата окончания: —» получателю ничего не
/// сообщает, а сообщение делает длиннее.
///
/// ```
/// Ремонт №128
/// Оборудование: Токарный станок
/// Статус: Открыт
/// Ответственный: Иванов И. И.
/// Норма расхода: Замена подшипника
/// Состав нормы: Подшипник 6205 × 1; Смазка × 2;
/// Дата начала: 19.08.2026 18:30
/// Комментарий: заменил подшипник
/// Фактический расход ЗИП: Болт 31-23 × 2; Ремень ГРМ × 232;
/// ```
String repairClipboardText({
  required Repair repair,
  String comment = '',
  List<RepairConsumption> consumptions = const [],
}) {
  final lines = <String>[
    // У черновика серверного номера ещё нет — id нулевой.
    repair.id > 0
        ? RepairCardStrings.titleWithId(repair.id)
        : ConflictStrings.clipboardNewRepair,
    '${ConflictStrings.clipboardEquipment} ${repair.equipmentName}',
    if ((repair.equipmentTypeModel ?? '').isNotEmpty)
      '${ConflictStrings.clipboardTypeModel} ${repair.equipmentTypeModel}',
    // Статус — только у существующего ремонта: у черновика его нет вовсе, а
    // модель отдаёт «Открыт» просто как значение по умолчанию.
    if (repair.id > 0)
      '${ConflictStrings.clipboardStatus} '
          '${RepairStatuses.displayName(repair.status)}',
    '${RepairCardStrings.fieldResponsible}: '
        '${_orDash(repair.responsibleUserFullname, RepairCardStrings.responsibleNone)}',
    if ((repair.responsibleRoleName ?? '').isNotEmpty)
      '${RepairCardStrings.fieldResponsibleRole}: ${repair.responsibleRoleName}',
    '${RepairCardStrings.fieldNorm}: '
        '${_orDash(repair.consumptionNormName, RepairCardStrings.normNotSet)}',
    if (repair.normItems.isNotEmpty)
      '${ConflictStrings.clipboardNormItems} ${_normLine(repair.normItems)}',
    '${ConflictStrings.clipboardStartedAt} '
        '${formatRepairDateTime(repair.startedAt)}',
    if (repair.completedAt != null)
      '${RepairCardStrings.fieldFinishedAt}: '
          '${formatRepairDateTime(repair.completedAt!)}',
    if ((repair.duration ?? '').isNotEmpty)
      '${RepairCardStrings.fieldDuration}: ${repair.duration}',
    if (comment.trim().isNotEmpty)
      '${ConflictStrings.clipboardComment} ${comment.trim()}',
    if (consumptions.isNotEmpty)
      '${ConflictStrings.clipboardConsumption} '
          '${_consumptionLine(consumptions)}',
  ];
  return lines.join('\n');
}

String _orDash(String? value, String fallback) =>
    (value == null || value.isEmpty) ? fallback : value;

/// Весь расход одной строкой: «Болт 31-23 × 2; Ремень ГРМ × 232;».
///
/// В строку, а не списком: сообщение читают в мессенджере, где каждая позиция
/// с новой строки растягивает его на экран. Единицу измерения не пишем — её
/// нет ни в норме, ни в составе расхода на других экранах, а название позиции
/// администратор и так находит в справочнике.
String _consumptionLine(List<RepairConsumption> items) => items
    .map((item) =>
        '${item.sparePartName} × ${formatSparePartQuantity(item.quantity)};')
    .join(' ');

/// Состав нормы — тем же видом, что и фактический расход.
String _normLine(List<RepairNormItem> items) => items
    .map((item) =>
        '${item.sparePartName} × ${formatSparePartQuantity(item.quantity)};')
    .join(' ');

/// Дата в том же виде, что и на карточках ремонта.
String formatRepairDateTime(DateTime value) =>
    DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());
