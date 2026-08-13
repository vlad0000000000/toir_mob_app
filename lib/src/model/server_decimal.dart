/// Разбор количественных полей, приходящих с бэкенда.
///
/// На сервере это `Numeric(14, 4)` в SQLAlchemy и `Decimal` в Pydantic. В JSON
/// такое поле приходит то числом, то строкой — зависит от режима сериализации,
/// и полагаться на один вариант нельзя. Поэтому принимаем оба, а на мусор
/// отвечаем `null`, а не исключением: из-за одной кривой позиции не должен
/// падать разбор всего справочника.
double? parseServerDecimal(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
