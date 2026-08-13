import 'server_decimal.dart';

/// Человекочитаемые названия типов операции (backend:
/// `SparePartStockOperationType`). Один в один с веб-админкой
/// (`STOCK_OPERATION_LABELS`) — обходчик и кладовщик должны называть одно и то
/// же движение одинаково.
const Map<String, String> stockOperationLabels = {
  'initial_balance': 'Начальный остаток',
  'manual_receipt': 'Ручной приход',
  'manual_writeoff': 'Ручное списание',
  'repair_writeoff': 'Списание в ремонт',
  'periodic_task_writeoff': 'Списание в задачу',
  'maintenance_writeoff': 'Списание в ТО',
  'adjustment': 'Корректировка',
  'onec_receipt': 'Приход из 1С',
};

/// Категория движения — по ней фильтруется лента. Категорий три, а типов
/// операций восемь: обходчику важно направление, а не то, из ремонта списали
/// или из задачи.
enum StockMovementCategory {
  replenish('Пополнения'),
  writeoff('Списания'),
  correction('Корректировки');

  const StockMovementCategory(this.label);

  final String label;
}

/// Запись истории движения ЗИП. Приходит из
/// `GET /v1/company/spare_parts/history?spare_part_uuid=...`.
///
/// В Hive не кладётся: история нужна только в карточке позиции и только при
/// связи. Офлайн отвечает за остаток (он лежит в каталоге), но не за то, откуда
/// этот остаток взялся.
class StockHistoryEntry {
  final String uuid;
  final String operationType;

  /// Знаковое изменение остатка: приход больше нуля, расход меньше.
  final double quantityChange;
  final DateTime operationAt;
  final String? comment;
  final String? responsibleName;

  StockHistoryEntry({
    required this.uuid,
    required this.operationType,
    required this.quantityChange,
    required this.operationAt,
    this.comment,
    this.responsibleName,
  });

  /// Корректировка — отдельная категория, остальное делится по знаку.
  /// Ровно так же считает веб-админка (`SparePartDetailDialog.toView`):
  /// «Ручной приход» с отрицательным количеством должен попасть в списания.
  StockMovementCategory get category {
    if (operationType == 'adjustment') return StockMovementCategory.correction;
    return quantityChange >= 0
        ? StockMovementCategory.replenish
        : StockMovementCategory.writeoff;
  }

  /// Заголовок строки — основание операции, если оно указано: «Списание в
  /// ремонт №128» говорит больше, чем «Списание в ремонт». Тип операции при
  /// этом не теряется — направление видно по значку и знаку количества.
  /// Без основания (у автоматических списаний его может не быть) заголовком
  /// остаётся название типа.
  String get title {
    final reason = comment?.trim();
    if (reason != null && reason.isNotEmpty) return reason;
    return stockOperationLabels[operationType] ?? 'Операция';
  }

  /// Приведённый к нижнему регистру заголовок — для поиска по ленте.
  /// Считается один раз: строка фильтруется на каждое нажатие клавиши.
  late final String _titleLower = title.toLowerCase();

  bool matchesQuery(String lowerQuery) => _titleLower.contains(lowerQuery);

  factory StockHistoryEntry.fromJson(Map<String, dynamic> json) {
    final user = json['responsible_user'] as Map<String, dynamic>?;
    return StockHistoryEntry(
      uuid: json['uuid'] as String,
      operationType: json['operation_type']?.toString() ?? '',
      quantityChange: parseServerDecimal(json['quantity_change']) ?? 0,
      operationAt: DateTime.tryParse(json['operation_at']?.toString() ?? '') ??
          DateTime.now(),
      comment: json['comment'] as String?,
      responsibleName: user?['fullname'] as String?,
    );
  }
}

/// Страница ленты движений. Общее число сервер отдаёт заголовком
/// `X-Total-Count` и только на первом запросе (`skip=0`) — на последующих
/// страницах здесь `null`, и вызывающий обязан сохранить прежнее значение.
class StockHistoryPage {
  final List<StockHistoryEntry> entries;
  final int? total;

  StockHistoryPage({required this.entries, this.total});
}
