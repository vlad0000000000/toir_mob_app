/// Приводит строку к виду для поиска: нижний регистр и `ё` → `е`.
///
/// Обходчик набирает «шестеренныи» без «ё», а в справочнике «Насос
/// шестерённый»: без замены такой запрос ничего бы не находил. Тем же
/// приводится и запрос, и поля, по которым ищем.
String normalizeSearchText(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');

/// Склонение по числу: `pluralRu(n, 'единицу', 'единицы', 'единиц')` —
/// «1 единицу», «2 единицы», «5 единиц».
String pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
  return many;
}
