// Условные запросы коротких справочников (бэкенд `81f644c`): с
// `If-None-Match` сервер отвечает 304 без тела, если справочник не менялся,
// и приложение показывает сохранённый.
//
// Ответ хранится разобранным в своём боксе (состояния оборудования, единицы
// наработки, правила периодичности), ETag — в `stringBox` под ключами ниже.
// При смене аккаунта боксы очищаются, и ETag стираются вместе с ними
// (`DataProvider.clearCachedData`): 304 подтвердил бы данные, которых на
// телефоне уже нет.

const String equipmentStatesEtagKey = 'etag_equipment_states';
const String usageUnitTypesEtagKey = 'etag_usage_unit_types';
const String periodicityRulesEtagKey = 'etag_periodicity_rules';

/// Все ключи ETag — для очистки при смене аккаунта.
const List<String> lookupEtagKeys = [
  equipmentStatesEtagKey,
  usageUnitTypesEtagKey,
  periodicityRulesEtagKey,
];

/// Что слать в `If-None-Match`: сохранённый ETag — только если сохранённые
/// данные на месте ([hasCachedData]). Пустой бокс при живом ETag (запись
/// оборвалась, бокс очистили) — запрос без условия: 304 оставил бы
/// справочник пустым.
String? ifNoneMatchFor({
  required String? storedEtag,
  required bool hasCachedData,
}) =>
    hasCachedData && storedEtag != null && storedEtag.isNotEmpty
        ? storedEtag
        : null;
