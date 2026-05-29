part of 'data_provider.dart';

/// Офлайн-очереди отправки: осмотры (scans), наработки (usage),
/// периодические задачи. Перекладывание pending ↔ box + ретраи.
extension DataProviderOutbox on DataProvider {
  Future<void> syncUsageScans() async {
    final scans = scanUsageBox.values.toList();
    for (final scan in scans) {
      try {
        await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox
            .put(scan.key(), scan);
        if (await api.updateUsageParameter(scan)) {
          await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        } else {
          await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
          await GlobalState.dataProvider.scanUsageBox.put(scan.key(), scan);
        }
      } catch (e) {
        await GlobalState.dataProvider.scanUsageBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsagePendingBox.delete(scan.key());
        await GlobalState.dataProvider.scanUsageBox.put(scan.key(), scan);
        print('Error syncing data: $e');
      }
    }
  }

  Future<void> syncScans() async {
    // Защита от параллельного запуска: 5-секундный цикл (startScanSyncing) и
    // ручная синхронизация ("Синхронизировать данные") могут вызвать syncScans
    // одновременно — оба прочитают scanBox и отправят один осмотр дважды.
    if (_isSyncingScans) return;
    _isSyncingScans = true;
    try {
      await _syncScansImpl();
    } finally {
      _isSyncingScans = false;
    }
  }

  Future<void> _syncScansImpl() async {
    // Проверяем pending сканы - возвращаем в scanBox те, что прождали 60 секунд
    final pendingScans = scanPendingBox.values.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final scan in pendingScans) {
      final timestampKey = 'scan_pending_${scan.key()}';
      final timestampStr = stringBox.get(timestampKey);
      if (timestampStr != null) {
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final elapsedSeconds = (now - timestamp) ~/ 1000;
          if (elapsedSeconds >= 120) {
            // Прошло 60 секунд - возвращаем скан в scanBox для повторной попытки
            await scanPendingBox.delete(scan.key());
            await stringBox.delete(timestampKey);
            await scanBox.put(scan.key(), scan);
          }
        }
      }
    }

    // Обрабатываем сканы из scanBox
    final scans = scanBox.values.toList();
    for (final scan in scans) {
      final taskUuid = scan.taskUuid;
      final isMaintenancePeriodicTask = taskUuid != null &&
          taskUuid.isNotEmpty &&
          scan.periodicTaskUuid != null &&
          scan.periodicTaskUuid!.isNotEmpty &&
          stringBox.get('maintenance_task_$taskUuid') == '1';

      // Если есть наработка по этому оборудованию, задачи ТО ждем ее отправки
      if (isMaintenancePeriodicTask &&
          scan.equipmentUuid != null &&
          scan.equipmentUuid!.isNotEmpty) {
        final hasPendingUsage = scanUsageBox.values.any(
              (usage) => usage.equipmentUuid == scan.equipmentUuid,
            ) ||
            scanUsagePendingBox.values.any(
              (usage) => usage.equipmentUuid == scan.equipmentUuid,
            );
        if (hasPendingUsage) {
          continue;
        }
      }
      try {
        // Перемещаем скан в pending перед отправкой
        await scanBox.delete(scan.key());
        await scanPendingBox.put(scan.key(), scan);

        // Сохраняем timestamp текущей попытки
        final timestampKey = 'scan_pending_${scan.key()}';
        await stringBox.put(timestampKey, now.toString());

        // Пытаемся отправить
        if (await api.sendScan(scan)) {
          // Успешно - удаляем из всех хранилищ
          await scanPendingBox.delete(scan.key());
          await stringBox.delete(timestampKey);
          if (scan.taskUuid != null) {
            await stringBox.delete('maintenance_task_${scan.taskUuid}');
          }
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 60 секунд
          // Ничего не делаем, скан уже в scanPendingBox с timestamp
        }
      } catch (e) {
        // При ошибке также оставляем в pending с timestamp
        // Убеждаемся, что скан в scanPendingBox и timestamp сохранен
        await scanPendingBox.put(scan.key(), scan);
        final timestampKey = 'scan_pending_${scan.key()}';
        await stringBox.put(timestampKey, now.toString());
        print('Error syncing data: $e');
      }
    }
  }

  Future<void> syncPeriodicTasks() async {
    // Проверяем pending задачи - возвращаем в periodicTaskBox те, что прождали 60 секунд
    final pendingTasks = periodicTaskPendingBox.values.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final task in pendingTasks) {
      final timestampKey = 'periodic_task_pending_${task.key()}';
      final timestampStr = stringBox.get(timestampKey);
      if (timestampStr != null) {
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final elapsedSeconds = (now - timestamp) ~/ 1000;
          if (elapsedSeconds >= 120) {
            // Прошло 120 секунд - возвращаем задачу в periodicTaskBox для повторной попытки
            await periodicTaskPendingBox.delete(task.key());
            await stringBox.delete(timestampKey);
            await periodicTaskBox.put(task.key(), task);
          }
        }
      }
    }

    // Обрабатываем задачи из periodicTaskBox
    final tasks = periodicTaskBox.values.toList();
    for (final task in tasks) {
      try {
        // Перемещаем задачу в pending перед отправкой
        await periodicTaskBox.delete(task.key());
        await periodicTaskPendingBox.put(task.key(), task);

        // Сохраняем timestamp текущей попытки
        final timestampKey = 'periodic_task_pending_${task.key()}';
        await stringBox.put(timestampKey, now.toString());

        // Пытаемся отправить
        if (await api.createPeriodicTask(task)) {
          // Успешно - удаляем из всех хранилищ
          await periodicTaskPendingBox.delete(task.key());
          await stringBox.delete(timestampKey);
        } else {
          // Неуспешно - оставляем в pending с timestamp, вернется через 120 секунд
          // Ничего не делаем, задача уже в periodicTaskPendingBox с timestamp
        }
      } catch (e) {
        // При ошибке также оставляем в pending с timestamp
        // Убеждаемся, что задача в periodicTaskPendingBox и timestamp сохранен
        await periodicTaskPendingBox.put(task.key(), task);
        final timestampKey = 'periodic_task_pending_${task.key()}';
        await stringBox.put(timestampKey, now.toString());
        print('Error syncing periodic task: $e');
      }
    }
  }
}
