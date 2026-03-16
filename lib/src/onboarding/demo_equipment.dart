import '../model/inventory_record.dart';

class DemoEquipment {
  static const String demoUuid = 'demo-onboarding-conveyor';

  static InventoryRecord get conveyorBelt => InventoryRecord(
        id: -1,
        uuid: demoUuid,
        name: 'Конвейерная лента наклонная',
        typeModel: 'КЛН-12м',
        serialNumber: 'KLN-2022-7788',
        location: 'Складской комплекс',
        manufacturer: 'ООО "КонвейерСтрой"',
        description:
            'Наклонная конвейерная лента длиной 12 метров для транспортировки '
            'коробок и упаковок на высоту до 3 метров. Ширина ленты 600 мм, '
            'скорость движения регулируемая до 0.5 м/с. Оборудована защитными '
            'ограждениями и системой аварийной остановки.',
        imageData: 'https://storage.yandexcloud.net/toir-images-prod/companies/21/equipment/16911539-212f-44d7-abb9-2c665a3ef0bb/photo_1_6288d813-a8db-441c-a48f-ab41b56b5141.jpg',
        state: 'in_operation',
        usageParameters: [
          UsageParameter(
            id: -1,
            uuid: 'demo-usage-kilowatts',
            unitType: 'kilowatts',
            currentValue: 18750.0,
            prohibitDecrease: false,
            createMaintenanceTasks: true,
            lastMaintenanceValue: 15000.0,
            maintenanceInterval: 5000.0,
            nextMaintenanceValue: 20000.0,
            maintenanceRole: const MaintenanceRole(
              uuid: '2120947f-e6b2-461b-a6a3-068232232ae3',
              name: 'Механик',
            ),
          ),
          UsageParameter(
            id: -2,
            uuid: 'demo-usage-motohours',
            unitType: 'motor_hours',
            currentValue: 2450.0,
            prohibitDecrease: true,
            createMaintenanceTasks: true,
            lastMaintenanceValue: 2000.0,
            maintenanceInterval: 1000.0,
            nextMaintenanceValue: 3000.0,
            maintenanceRole: const MaintenanceRole(
              uuid: '5bed09d7-23fa-47a3-a0db-b0549d79cc35',
              name: 'Обходчик',
            ),
          ),
          UsageParameter(
            id: -3,
            uuid: 'demo-usage-kilometers',
            unitType: 'kilometers',
            currentValue: 125.0,
            prohibitDecrease: false,
            createMaintenanceTasks: false,
            lastMaintenanceValue: 100.0,
            maintenanceInterval: 50.0,
            nextMaintenanceValue: 150.0,
            maintenanceRole: const MaintenanceRole(
              uuid: '5bed09d7-23fa-47a3-a0db-b0549d79cc35',
              name: 'Обходчик',
            ),
          ),
        ],
      );
}
