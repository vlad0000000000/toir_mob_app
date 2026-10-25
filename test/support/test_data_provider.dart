import 'package:hive_ce/hive.dart';
import 'package:qr_scan_industry/src/data/data_provider.dart';
import 'package:qr_scan_industry/src/http/api.dart';
import 'package:qr_scan_industry/src/model/company.dart';
import 'package:qr_scan_industry/src/model/consumption_norm.dart';
import 'package:qr_scan_industry/src/model/equipment_state.dart';
import 'package:qr_scan_industry/src/model/inventory_record.dart';
import 'package:qr_scan_industry/src/model/pending_repair.dart';
import 'package:qr_scan_industry/src/model/pending_repair_update.dart';
import 'package:qr_scan_industry/src/model/periodic_task_request.dart';
import 'package:qr_scan_industry/src/model/periodicity_rule.dart';
import 'package:qr_scan_industry/src/model/repair.dart';
import 'package:qr_scan_industry/src/model/scan.dart';
import 'package:qr_scan_industry/src/model/session.dart';
import 'package:qr_scan_industry/src/model/spare_part.dart';
import 'package:qr_scan_industry/src/model/task.dart';
import 'package:qr_scan_industry/src/model/typical_problem.dart';
import 'package:qr_scan_industry/src/model/usage_unit.dart';
import 'package:qr_scan_industry/src/model/usage_update.dart';
import 'package:qr_scan_industry/src/model/user.dart';

/// Настоящий `DataProvider` на боксах во временном каталоге (`Hive.init` —
/// за тестом). Адаптеры регистрирует тест: нужны только тем боксам, в
/// которые он сам пишет, — остальные пусты и ничего не читают.
Future<DataProvider> testDataProvider() async {
  Future<Box<T>> open<T>(String name) => Hive.openBox<T>(name);
  return DataProvider(
    api: API(),
    userBox: await open<User>('users'),
    inventoryBox: await open<InventoryRecord>('inventory'),
    scanBox: await open<Scan>('scans'),
    scanUsageBox: await open<UsageUpdate>('usage_scans'),
    scanPendingBox: await open<Scan>('pending_scans'),
    scanUsagePendingBox: await open<UsageUpdate>('pending_usage_scans'),
    sessionBox: await open<Session>('sessions'),
    usageUnitBox: await open<UsageUnit>('usage_units'),
    typicalProblemBox: await open<TypicalProblem>('typical_problems'),
    stringBox: await open<String>('strings'),
    periodicityRuleBox: await open<PeriodicityRule>('periodicity_rules'),
    taskBox: await open<Task>('tasks'),
    companyBox: await open<Company>('company'),
    equipmentStateBox: await open<EquipmentState>('equipment_states'),
    sparePartBox: await open<SparePart>('spare_parts'),
    repairBox: await open<Repair>('repairs'),
    pendingRepairBox: await open<PendingRepair>('pending_repairs'),
    pendingRepairUpdateBox:
        await open<PendingRepairUpdate>('pending_repair_updates'),
    consumptionNormBox: await open<ConsumptionNorm>('consumption_norms'),
    periodicTaskBox: await open<PeriodicTaskRequest>('periodic_tasks'),
    periodicTaskPendingBox:
        await open<PeriodicTaskRequest>('pending_periodic_tasks'),
  );
}
