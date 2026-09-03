import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/repairs/repair_clipboard.dart';

RepairConsumption item(String name, double quantity) => RepairConsumption(
      sparePartUuid: 'uuid-$name',
      sparePartName: name,
      quantity: quantity,
    );

RepairNormItem normItem(String name, double quantity) => RepairNormItem(
      sparePartUuid: 'uuid-$name',
      sparePartName: name,
      quantity: quantity,
    );

/// Дата берётся локальным конструктором: форматтер выводит локальное время.
final started = DateTime(2026, 8, 19, 18, 30);

Repair repair({
  int id = 0,
  String status = RepairStatuses.open,
  String equipmentName = 'Токарный станок',
  String? equipmentTypeModel,
  String? normName,
  List<RepairNormItem> normItems = const [],
  String? responsible,
  String? responsibleRole,
  DateTime? completedAt,
  String? duration,
}) =>
    Repair(
      id: id,
      uuid: '',
      status: status,
      equipmentUuid: 'eq',
      equipmentName: equipmentName,
      equipmentTypeModel: equipmentTypeModel,
      consumptionNormName: normName,
      createdAt: started,
      startedAt: started,
      completedAt: completedAt,
      duration: duration,
      responsibleUserFullname: responsible,
      responsibleRoleName: responsibleRole,
      normItems: normItems,
    );

void main() {
  group('repairClipboardText', () {
    test('черновик: без номера, статуса и пустых полей', () {
      final text = repairClipboardText(
        repair: repair(),
        consumptions: [item('Болт 31-23', 2), item('Ремень ГРМ', 232)],
      );

      expect(text.split('\n'), [
        'Новый ремонт',
        'Оборудование: Токарный станок',
        'Ответственный: Не назначен',
        'Норма расхода: Не задана',
        'Дата начала: 19.08.2026 18:30',
        'Фактический расход ЗИП: Болт 31-23 × 2; Ремень ГРМ × 232;',
      ]);
    });

    test('существующий ремонт: номер, статус и все заполненные поля', () {
      final text = repairClipboardText(
        repair: repair(
          id: 128,
          status: RepairStatuses.underReview,
          equipmentTypeModel: '16К20',
          normName: 'Замена подшипника',
          normItems: [normItem('Подшипник 6205', 1)],
          responsible: 'Иванов И. И.',
          responsibleRole: 'Слесарь',
          completedAt: DateTime(2026, 8, 20, 9, 15),
          duration: '14 ч 45 мин',
        ),
        comment: 'заменил подшипник',
        consumptions: [item('Болт', 1)],
      );

      expect(text.split('\n'), [
        'Ремонт №128',
        'Оборудование: Токарный станок',
        'Тип/модель: 16К20',
        'Статус: На рассмотрении',
        'Ответственный: Иванов И. И.',
        'Ответственная должность: Слесарь',
        'Норма расхода: Замена подшипника',
        'Состав нормы: Подшипник 6205 × 1;',
        'Дата начала: 19.08.2026 18:30',
        'Дата окончания: 20.08.2026 09:15',
        'Длительность: 14 ч 45 мин',
        'Комментарий: заменил подшипник',
        'Фактический расход ЗИП: Болт × 1;',
      ]);
    });

    test('дробное количество не округляется и пишется через запятую', () {
      final text = repairClipboardText(
        repair: repair(),
        consumptions: [item('Масло И-20', 1.5)],
      );

      expect(text, contains('Масло И-20 × 1,5;'));
    });

    test('фотографий в тексте нет ни при каких данных', () {
      final text = repairClipboardText(repair: repair(id: 7));

      expect(text.toLowerCase(), isNot(contains('фото')));
    });

    test('пробельный комментарий строки не добавляет', () {
      final text = repairClipboardText(repair: repair(), comment: '   ');

      expect(text, isNot(contains('Комментарий')));
    });
  });
}
