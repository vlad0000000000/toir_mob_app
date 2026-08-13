import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../global_state.dart';

/// Каталог локальной базы Hive.
///
/// Раньше имя каталога считалось как md5 от
/// `appName|packageName|version|buildNumber`, то есть **каждый выпуск новой
/// версии открывал пустую базу**. Неотправленные осмотры, наработки и
/// внеплановые задачи оставались в каталоге предыдущей версии и для
/// обходчика просто исчезали.
///
/// Теперь путь зависит только от `appName|packageName` и переживает
/// обновление приложения. [resolve] дополнительно один раз переносит боксы
/// из каталога прошлой версии — иначе само обновление на сборку с этой
/// правкой стало бы той последней потерей данных, ради которой всё и
/// затевалось.
class HiveStorageLocation {
  HiveStorageLocation._();

  /// Имена каталогов, которые создавала прежняя схема, — md5 в hex.
  static final RegExp _digestDirName = RegExp(r'^[0-9a-f]{32}$');

  /// Разделитель пути — принимаем оба, чтобы не зависеть от платформы.
  static final RegExp _pathSeparator = RegExp(r'[\\/]');

  /// Файлы боксов Hive. `.lock` не переносим — он создаётся заново.
  static const String _boxExtension = '.hive';

  /// Метка выполненного переноса. Лежит внутри каталога базы; Hive боксы
  /// открывает по имени и каталог не перечисляет, так что не мешает.
  static const String _migrationMarker = '.migrated';

  /// Абсолютный путь к каталогу базы. При первом запуске сборки со
  /// стабильным путём переносит сюда боксы прошлой версии.
  ///
  /// Вызывать только на мобильных платформах: на web у Hive собственное
  /// хранилище и путь не нужен.
  static Future<String> resolve(PackageInfo packageInfo) async {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    final stableName = GlobalState.digest(
      [packageInfo.appName, packageInfo.packageName].join('|'),
    );
    final stableDir = Directory('${appDocumentDir.path}/$stableName');
    final marker = File('${stableDir.path}/$_migrationMarker');

    try {
      if (!await stableDir.exists()) {
        await stableDir.create(recursive: true);
      }
      // Метку ставим только после полного успешного переноса. Если приложение
      // убьют на середине копирования, метки не будет и следующий запуск
      // повторит перенос целиком — File.copy перезаписывает, повтор безопасен.
      // Проверять «есть ли боксы» вместо метки нельзя: после частичного
      // копирования боксы уже есть, а данные неполные.
      if (!await marker.exists()) {
        final legacyDir = await _findLegacyDir(appDocumentDir, stableName);
        if (legacyDir != null) {
          final copied = await _copyBoxes(legacyDir, stableDir);
          debugPrint(
              '[Storage] перенесено боксов из ${legacyDir.path}: $copied');
        }
        await marker.create();
      }
    } catch (e) {
      // Сбой переноса не должен мешать запуску: приложение стартует на
      // стабильном каталоге, данные прошлой версии остаются на диске.
      debugPrint('[Storage] перенос базы не удался: $e');
    }
    return stableDir.path;
  }

  /// Каталог прошлой версии: имя — md5, внутри есть боксы. Если таких
  /// несколько (обходчик обновлялся не раз), берём самый свежий по времени
  /// изменения — это и есть последняя рабочая база.
  static Future<Directory?> _findLegacyDir(
    Directory appDocumentDir,
    String stableName,
  ) async {
    Directory? newest;
    DateTime? newestAt;
    await for (final entity in appDocumentDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _basename(entity.path);
      if (name == stableName || !_digestDirName.hasMatch(name)) continue;
      final modifiedAt = await _lastBoxModification(entity);
      if (modifiedAt == null) continue;
      if (newestAt == null || modifiedAt.isAfter(newestAt)) {
        newest = entity;
        newestAt = modifiedAt;
      }
    }
    return newest;
  }

  static Future<DateTime?> _lastBoxModification(Directory dir) async {
    DateTime? latest;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith(_boxExtension)) continue;
        final modified = (await entity.stat()).modified;
        if (latest == null || modified.isAfter(latest)) {
          latest = modified;
        }
      }
    } catch (_) {
      return null;
    }
    return latest;
  }

  /// Копируем, а не переносим: если что-то пойдёт не так, база прошлой
  /// версии останется на диске и её ещё можно будет достать. Очистку
  /// старых каталогов делаем отдельным выпуском, когда перенос себя покажет.
  static Future<int> _copyBoxes(Directory from, Directory to) async {
    var copied = 0;
    await for (final entity in from.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith(_boxExtension)) continue;
      await entity.copy('${to.path}/${_basename(entity.path)}');
      copied++;
    }
    return copied;
  }

  static String _basename(String path) {
    return path.split(_pathSeparator).where((part) => part.isNotEmpty).last;
  }
}
