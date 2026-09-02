import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/model/repair.dart';

/// Подробности ремонта, которых нет в списке.
///
/// `GET /v1/repairs/` отдаёт `RepairListSchema` — без комментария, расхода,
/// фото и состава нормы. `GET /v1/repairs/{uuid}` отдаёт всё. Пока разница не
/// была выражена в модели, фоновая синхронизация раскладывала записи из списка
/// в кэш и затирала ими карточку, прочитанную целиком: открыл ремонт онлайн,
/// через минуту прошла синхронизация — и расход из кэша исчез. Дальше без
/// связи карточка «На рассмотрении» показывала пустой блок расхода с подписью
/// «Расход не указан — списания со склада не будет», хотя на сервере расход
/// есть, а править блок в этом статусе нельзя.
Map<String, dynamic> listJson({String status = 'under_review'}) => {
      'id': 1,
      'uuid': 'repair-1',
      'status': status,
      'equipment': {'uuid': 'eq-1', 'name': 'Насос'},
      'consumption_norm': {'uuid': 'norm-1', 'name': 'ТО-1'},
      'created_at': '2026-08-18T10:00:00Z',
      'started_at': '2026-08-18T10:00:00Z',
    };

Map<String, dynamic> fullJson({
  String status = 'under_review',
  String normUuid = 'norm-1',
  List<dynamic>? consumptions,
}) =>
    {
      ...listJson(status: status),
      'consumption_norm': {
        'uuid': normUuid,
        'name': 'ТО-1',
        'items': [
          {
            'spare_part': {'uuid': 'sp-1', 'name': 'Сальник'},
            'quantity': '2',
          }
        ],
      },
      'comment': 'заменил сальник',
      'photos': [
        {'uuid': 'ph-1', 'url': 'http://x/1.jpg'}
      ],
      'actual_consumptions': consumptions ??
          [
            {
              'spare_part': {
                'uuid': 'sp-1',
                'name': 'Сальник',
                'unit': {'name': 'шт'},
              },
              'quantity': '3',
            }
          ],
    };

void main() {
  group('Repair.detailsLoaded', () {
    test('запись из списка подробностей не несёт', () {
      final repair = Repair.fromJson(listJson());

      expect(repair.detailsLoaded, isFalse);
      expect(repair.actualConsumptions, isEmpty);
      expect(repair.comment, isNull);
      expect(repair.normItems, isEmpty);
    });

    test('запись из полной схемы несёт', () {
      final repair = Repair.fromJson(fullJson());

      expect(repair.detailsLoaded, isTrue);
      expect(repair.actualConsumptions.single.quantity, 3);
      expect(repair.comment, 'заменил сальник');
      expect(repair.photos, hasLength(1));
      expect(repair.normItems.single.quantity, 2);
    });

    test('пустой расход в полной схеме — это «нет», а не «неизвестно»', () {
      // Различаем по наличию ключа, а не по значению: значения у «пусто» и
      // «поле не пришло» одинаковые, а смысл противоположный.
      final repair = Repair.fromJson(fullJson(consumptions: const []));

      expect(repair.detailsLoaded, isTrue);
      expect(repair.actualConsumptions, isEmpty);
    });
  });

  group('Repair.withDetailsFrom', () {
    test('запись из списка забирает подробности из кэша', () {
      final cached = Repair.fromJson(fullJson());
      final fromList = Repair.fromJson(listJson());

      final merged = fromList.withDetailsFrom(cached);

      expect(merged.detailsLoaded, isTrue);
      expect(merged.actualConsumptions.single.quantity, 3);
      expect(merged.comment, 'заменил сальник');
      expect(merged.photos, hasLength(1));
      expect(merged.normItems, hasLength(1));
    });

    test('свежие поля списка остаются от списка', () {
      // Ради этого синхронизация и ходит: статус мог смениться. Подробности
      // берём из кэша, всё остальное — из свежего ответа.
      final cached = Repair.fromJson(fullJson(status: 'open'));
      final fromList = Repair.fromJson(listJson(status: 'under_review'));

      final merged = fromList.withDetailsFrom(cached);

      expect(merged.status, 'under_review');
      expect(merged.comment, 'заменил сальник');
    });

    test('в кэше тоже запись из списка — брать нечего', () {
      final cached = Repair.fromJson(listJson());
      final fromList = Repair.fromJson(listJson());

      final merged = fromList.withDetailsFrom(cached);

      expect(merged.detailsLoaded, isFalse);
      expect(merged.actualConsumptions, isEmpty);
    });

    test('пустого кэша достаточно, чтобы ничего не делать', () {
      final fromList = Repair.fromJson(listJson());

      expect(fromList.withDetailsFrom(null).detailsLoaded, isFalse);
    });

    test('сменилась норма — её состав из кэша не переносим', () {
      // Иначе к новой норме прицепился бы состав старой, и «Заполнить из
      // нормы» подставило бы позиции, которых в ней нет.
      final cached = Repair.fromJson(fullJson(normUuid: 'norm-old'));
      final fromList = Repair.fromJson(listJson());

      final merged = fromList.withDetailsFrom(cached);

      expect(merged.consumptionNormUuid, 'norm-1');
      expect(merged.normItems, isEmpty);
      // Расход при этом остаётся: он к смене нормы отношения не имеет.
      expect(merged.actualConsumptions, hasLength(1));
    });
  });
}
