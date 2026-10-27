import '../model/inventory_record.dart';
import '../utils/search_text.dart';

/// Фильтр списка оборудования. Пустые множества — «без ограничений».
///
/// Отбор идёт строго по порядку: область → поиск → фильтры. Область задаёт
/// весь набор: при «Моё подразделение» и поиск, и варианты чипов, и все
/// счётчики — только по оборудованию своих подразделений.
class EquipmentFilter {
  /// «Все подразделения». По умолчанию — своё.
  final bool showAll;

  /// Названия помещений (`InventoryRecord.location`).
  final Set<String> locations;

  /// Коды состояний (`InventoryRecord.state`).
  final Set<String> states;

  /// Только оборудование с активными задачами.
  final bool onlyWithTasks;

  const EquipmentFilter({
    this.showAll = false,
    this.locations = const {},
    this.states = const {},
    this.onlyWithTasks = false,
  });

  /// Число активных разделов — для кнопки фильтров. Область считается
  /// активной на «Все подразделения»: по умолчанию показывается своё.
  int get activeCount =>
      (showAll ? 1 : 0) +
      (locations.isEmpty ? 0 : 1) +
      (states.isEmpty ? 0 : 1) +
      (onlyWithTasks ? 1 : 0);

  bool get isDefault => activeCount == 0;

  /// Условия, которые сбрасывает «Сбросить фильтры» на пустом списке, —
  /// всё, кроме области: её переключают отдельной кнопкой.
  bool get hasConditions =>
      locations.isNotEmpty || states.isNotEmpty || onlyWithTasks;

  EquipmentFilter copyWith({
    bool? showAll,
    Set<String>? locations,
    Set<String>? states,
    bool? onlyWithTasks,
  }) {
    return EquipmentFilter(
      showAll: showAll ?? this.showAll,
      locations: locations ?? this.locations,
      states: states ?? this.states,
      onlyWithTasks: onlyWithTasks ?? this.onlyWithTasks,
    );
  }

  /// Без условий отбора, область та же.
  EquipmentFilter withoutConditions() => EquipmentFilter(showAll: showAll);
}

/// Помещение оборудования как значение фильтра: название без лишних
/// пробелов. `null` — помещения нет.
String? equipmentLocationOf(InventoryRecord equipment) {
  final location = equipment.location?.trim() ?? '';
  return location.isEmpty ? null : location;
}

/// Набор области: всё или только своё.
List<InventoryRecord> equipmentInScope(
  Iterable<InventoryRecord> source, {
  required bool showAll,
  required bool Function(InventoryRecord) isOwn,
}) {
  if (showAll) return source.toList();
  return [
    for (final item in source)
      if (isOwn(item)) item,
  ];
}

/// Совпадение с запросом по названию, модели и серийному номеру — без учёта
/// регистра и «ё/е», по подстроке. [query] — уже из [normalizeSearchText].
bool equipmentMatchesQuery(InventoryRecord equipment, String query) {
  if (query.isEmpty) return true;
  for (final field in [
    equipment.name,
    equipment.typeModel,
    equipment.serialNumber,
  ]) {
    if (field != null && normalizeSearchText(field).contains(query)) {
      return true;
    }
  }
  return false;
}

/// Отбор списка: область → поиск → фильтры. Одна функция и для списка, и
/// для счётчика «Показать N» в листе — обещанное число совпадает со списком.
///
/// [hasActiveTasks] нужен только при [EquipmentFilter.onlyWithTasks].
List<InventoryRecord> applyEquipmentFilter(
  Iterable<InventoryRecord> source, {
  required EquipmentFilter filter,
  required String query,
  required bool Function(InventoryRecord) isOwn,
  bool Function(InventoryRecord)? hasActiveTasks,
}) {
  final normalized = normalizeSearchText(query);
  final result = <InventoryRecord>[];
  for (final item in equipmentInScope(
    source,
    showAll: filter.showAll,
    isOwn: isOwn,
  )) {
    if (!equipmentMatchesQuery(item, normalized)) continue;
    if (filter.locations.isNotEmpty &&
        !filter.locations.contains(equipmentLocationOf(item))) {
      continue;
    }
    if (filter.states.isNotEmpty && !filter.states.contains(item.state)) {
      continue;
    }
    if (filter.onlyWithTasks &&
        hasActiveTasks != null &&
        !hasActiveTasks(item)) {
      continue;
    }
    result.add(item);
  }
  return result;
}

/// Варианты раздела «Местоположение» — помещения набора области, по
/// алфавиту. Ключ и подпись — название.
Map<String, String> equipmentLocationOptions(Iterable<InventoryRecord> scoped) {
  final names = <String>{
    for (final item in scoped)
      if (equipmentLocationOf(item) case final location?) location,
  }.toList()
    ..sort((a, b) => normalizeSearchText(a).compareTo(normalizeSearchText(b)));
  return {for (final name in names) name: name};
}

/// Варианты раздела «Состояние» — состояния, встреченные в наборе области,
/// в порядке справочника состояний ([dictionary]: код → название). Код,
/// которого в справочнике нет, показываем как есть — в конце.
Map<String, String> equipmentStateOptions(
  Iterable<InventoryRecord> scoped, {
  required Map<String, String> dictionary,
}) {
  final present = <String>{
    for (final item in scoped)
      if ((item.state ?? '').isNotEmpty) item.state!,
  };
  return {
    for (final entry in dictionary.entries)
      if (present.contains(entry.key)) entry.key: entry.value,
    for (final code in present)
      if (!dictionary.containsKey(code)) code: code,
  };
}
