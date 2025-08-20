import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/http/api.dart';
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Machine> machineBox;
  final Box<Task> taskBox;
  final Box<Check> machineCheckBox;

  DataProvider(
      {required this.api,
      required this.userBox,
      required this.machineBox,
      required this.machineCheckBox,
      required this.taskBox}) {
    _users = userBox.values.toList();
    _machines = machineBox.values.toList();
  }

  List<User> _users = [];
  List<Machine> _machines = [];
  bool _isLoading = false;

  List<User> get users => _users;

  List<Machine> get machines => _machines;

  bool get isLoading => _isLoading;

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
      for (var task in await api.getCurrentTasks(machineId)) {
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
      List<Task> tasks = await api.getAllCurrentTasks();
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

  Future<void> syncUsers() async {
    _isLoading = true;

    try {
      _users = userBox.values.toList();
      _users = await api.getUsers();
      userBox.clear();
      userBox.addAll(_users);
    } catch (e) {
      print('Error loading initial data: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> syncMachines() async {
    _isLoading = true;

    try {
      _machines = machineBox.values.toList();
      _machines = await api.getMachines();
      machineBox.clear();
      machineBox.addAll(_machines);
    } catch (e) {
      print('Error loading initial data: $e');
    } finally {
      _isLoading = false;
    }
  }

  // Загрузить данные при запуске
  Future<void> syncUsersAndMachines() async {
    _isLoading = true;

    try {
      _users = await api.getUsers();
      _machines = await api.getMachines();

      // Сохранить данные в локальное хранилище
      userBox.clear();
      machineBox.clear();
      userBox.addAll(_users);
      machineBox.addAll(_machines);
    } catch (e) {
      print('Error loading initial data: $e');
    } finally {
      _isLoading = false;
    }
  }

  // Отправить данные о проверке машины
  Future<void> sendMachineCheck(Check check) async {
    debugPrint(check.toString());
    try {
      await api.sendMachineCheck(check);
    } catch (e) {
      machineCheckBox.put(check.key(), check);
    }
  }

  Future<void> checkConnectivityAndSync() async {
    if (await GlobalState.hasConnectionToServer) {
      await syncUsersAndMachines();
      await syncChecks();
      // await syncTasks();
    }
  }

  void startSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        await checkConnectivityAndSync();
      }
    });
  }

  // TODO: как можно меньше await
  Future<void> syncChecks() async {
    final checks = machineCheckBox.values.toList();
    for (final check in checks) {
      if (check.isSyncing) {
        continue;
      }
      try {
        check.isSyncing = true;
        await machineCheckBox.put(check.key(), check);
        await api.sendMachineCheck(check);
        await machineCheckBox.delete(check.key());
      } catch (e) {
        check.isSyncing = false;
        await machineCheckBox.put(check.key(), check);
        print('Error syncing data: $e');
      }
    }
  }
}
