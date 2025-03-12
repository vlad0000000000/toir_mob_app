import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/http/api.dart';
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/user.dart';

class DataProvider {
  final API api;
  final Box<User> userBox;
  final Box<Machine> machineBox;
  final Box<Check> machineCheckBox;

  DataProvider({
    required this.api,
    required this.userBox,
    required this.machineBox,
    required this.machineCheckBox,
  }) {
    _users = userBox.values.toList();
    _machines = machineBox.values.toList();
  }

  List<User> _users = [];
  List<Machine> _machines = [];
  bool _isLoading = false;

  List<User> get users => _users;

  List<Machine> get machines => _machines;

  bool get isLoading => _isLoading;

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
    }
  }

  void startSyncing() {
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 60));
        if (await GlobalState.hasConnectionToServer) {
          await syncChecks();
        }
      }
    });
    Future.sync(() async {
      while (true) {
        await Future.delayed(Duration(seconds: 300));
        if (await GlobalState.hasConnectionToServer) {
          await syncUsersAndMachines();
        }
      }
    });
  }

  Future<void> syncChecks() async {
    final checks = machineCheckBox.values.toList();
    for (final check in checks) {
      try {
        await api.sendMachineCheck(check);
        machineCheckBox.delete(check.key());
      } catch (e) {
        print('Error syncing data: $e');
      }
    }
  }
}
