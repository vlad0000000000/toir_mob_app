import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/http/api.dart';
import 'package:qr_machine_scanner/src/model/scan.dart';
import 'package:qr_machine_scanner/src/model/inventory_record.dart';
import 'package:qr_machine_scanner/src/model/session.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Task> taskBox;
  final Box<InventoryRecord> inventoryBox;
  final Box<Scan> scanBox;
  final Box<Session> sessionBox;

  DataProvider(
      {required this.api,
      required this.userBox,
      required this.inventoryBox,
      required this.scanBox,
      required this.sessionBox,
      required this.taskBox}) {
    _users = userBox.values.toList();
    _inventoryRecords = inventoryBox.values.toList();
    _currentSession = sessionBox.get('current_session');
  }

  List<User> _users = [];
  List<InventoryRecord> _inventoryRecords = [];
  bool _isLoading = false;

  List<User> get users => _users;

  List<InventoryRecord> get inventoryRecords => _inventoryRecords;

  Session? get currentSession => _currentSession;
  Session? _currentSession;

  bool get isLoading => _isLoading;

  addUser(User user) async {
    await userBox.put(user.username, user);
    _users = userBox.values.toList();
  }

  addScan(Scan scan) async {
    await scanBox.put(scan.key(), scan);
  }

  setCurrentSession(session) async {
    await sessionBox.put('current_session', session);
    _currentSession = session;
  }

  Future<List<InventoryRecord>> loadAllInventory() async {
    int limit = 100;
    int offset = 0;
    List<InventoryRecord> all = [];
    while (true) {
      List<InventoryRecord> notAll =
          // await api.getInventoryRecords(limit: limit, offset: offset);
          await api.getEquipment(limit: limit, offset: offset);
      for (var inventoryRecord in notAll) {
        all.add(inventoryRecord);
      }
      if (notAll.isEmpty) {
        break;
      }
      offset += limit;
    }
    return all;
  }

  Future<void> syncCurrentSession() async {
    _isLoading = true;

    try {
      setCurrentSession(await api.getCurrentSession());
    } catch (e) {
      print('Failed sync session: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncInventory() async {
    _isLoading = true;

    try {
      _inventoryRecords = await loadAllInventory();
      await inventoryBox.clear();
      await inventoryBox.addAll(_inventoryRecords);
    } catch (e) {
      print('Failed sync inventory: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncScans() async {
    final scans = scanBox.values.toList();
    for (final scan in scans) {
      try {
        await api.sendScan(scan);
        await scanBox.delete(scan.key());
      } catch (e) {
        print('Error syncing scan: $e');
      }
    }
  }

  void startSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        if (await GlobalState.hasConnectionToServer) {
          await syncInventory();
          await syncScans();
        }
      }
    });
  }

  // Метод синхронизации задач
  Future<void> syncTasksForMachine(machineId) async {
    _isLoading = true;
    try {
      List<Task> tasks = [];
      for (var task in taskBox.values) {
        if (task.machineId != machineId) {
          tasks.add(task);
        }
      }
      for (var task in await api.getEquipmentTasks(machineId)) {
        tasks.add(task);
      }
      await taskBox.clear();
      await taskBox.addAll(tasks);
    } catch (e) {
      print('Error syncing tasks: $e');
    } finally {
      _isLoading = false;
    }
  }

  // Метод синхронизации задач
  Future<void> syncTasks() async {
    _isLoading = true;
    try {
      List<Task> tasks = [];
      for (var machine in inventoryRecords) {
        for (var task in await api.getEquipmentTasks(machine.uuid)) {
          tasks.add(task);
        }
      }

      // List<Task> tasks = await api.getAllCurrentTasks();
      await taskBox.clear();
      await taskBox.addAll(tasks);
      // for (var machine in this.machines) {
      //   await syncTasksForMachine(machine.id);
      // }
    } catch (e) {
      print('Error syncing tasks: $e');
    } finally {
      _isLoading = false;
    }
  }

  List<Task> loadTasks(int machineId) {
    var tasks = getTasksForMachine(machineId);
    return tasks.where((task) {
      return task.role == GlobalState.authUser!.role;
    }).toList();
  }

  // Получение задач для машины
  List<Task> getTasksForMachine(int machineId) {
    return taskBox.values.where((task) => task.machineId == machineId).toList();
  }

// // TODO: как можно меньше await
// Future<void> syncChecks() async {
//   final checks = machineCheckBox.values.toList();
//   for (final check in checks) {
//     if (check.isSyncing) {
//       continue;
//     }
//     try {
//       check.isSyncing = true;
//       await machineCheckBox.put(check.key(), check);
//       await api.sendMachineCheck(check);
//       await machineCheckBox.delete(check.key());
//     } catch (e) {
//       check.isSyncing = false;
//       await machineCheckBox.put(check.key(), check);
//       print('Error syncing data: $e');
//     }
//   }
// }
}
