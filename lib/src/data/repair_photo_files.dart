import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Файлы снимков ремонта, снятых без связи.
///
/// В Hive кладём только путь, а сам снимок лежит отдельным файлом: base64
/// одной фотографии — это сотни килобайт, и десяток таких в боксе раздул бы
/// его до неприличия, а Hive переписывает бокс целиком.
///
/// Каталог общий и плоский. Раскладывать по подкаталогам «на черновик» смысла
/// нет: файл всегда упоминается ровно одной записью очереди, а поиск
/// осиротевших проще, когда файлы в одном месте.
class RepairPhotoFiles {
  RepairPhotoFiles._();

  static const String _dirName = 'repair_photos';

  /// Расширение фиксированное: `image_picker` отдаёт JPEG, и сервер принимает
  /// снимки как `image/jpeg` (см. `uploadRepairPhotos`).
  static const String _extension = '.jpg';

  static Directory? _cachedDir;

  static Future<Directory> _dir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// Сохраняет снимок и возвращает абсолютный путь к файлу.
  ///
  /// Имя — время в миллисекундах плюс счётчик: два снимка подряд в одну
  /// миллисекунду маловероятны, но счётчик снимает вопрос совсем.
  static int _counter = 0;

  static Future<String> save(Uint8List bytes) async {
    final dir = await _dir();
    final name = '${DateTime.now().millisecondsSinceEpoch}_${_counter++}'
        '$_extension';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// `Idempotency-Key` для отправки снимка на сервер.
  ///
  /// Считается от **содержимого** кадра, а не от пути к файлу или от времени.
  /// Это важно: снимок сначала пробуют отправить прямо из карточки, и если
  /// ответ потерялся (таймаут — ошибка «повторяемая»), тот же кадр ложится в
  /// очередь уже под новым именем файла. Ключ от содержимого у обеих попыток
  /// один, поэтому сервер вернёт уже сохранённый снимок вместо второго.
  ///
  /// Ремонт входит в ключ, чтобы один и тот же кадр можно было приложить к
  /// разным ремонтам.
  static String idempotencyKey(String repairUuid, List<int> bytes) =>
      'photo-$repairUuid-${md5.convert(bytes)}';

  /// Разделитель пути — принимаем оба, чтобы не зависеть от платформы.
  static final RegExp _pathSeparator = RegExp(r'[\\/]');

  static String _basename(String path) =>
      path.split(_pathSeparator).where((part) => part.isNotEmpty).last;

  /// Приводит сохранённый путь к тому, что есть на диске **сейчас**.
  ///
  /// В очереди лежит абсолютный путь — так проще всего показать снимок в
  /// карточке (`Image.file`). Но каталог приложения не вечен: на iOS при
  /// переустановке меняется идентификатор контейнера, и старый абсолютный
  /// путь перестаёт существовать, хотя сам файл на месте. Поэтому если по
  /// пути ничего нет, пробуем то же имя в текущем каталоге снимков.
  static Future<File?> _resolve(String path) async {
    final direct = File(path);
    if (await direct.exists()) return direct;
    final dir = await _dir();
    final fallback = File('${dir.path}/${_basename(path)}');
    return await fallback.exists() ? fallback : null;
  }

  static Future<Uint8List?> read(String path) async {
    try {
      final file = await _resolve(path);
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (e) {
      // Файл могли удалить извне (чистка хранилища системой). Не роняем
      // очередь — пусть снимок просто пропадёт, ремонт уедет без него.
      debugPrint('[Photos] не удалось прочитать $path: $e');
      return null;
    }
  }

  static Future<void> delete(String path) async {
    try {
      final file = await _resolve(path);
      if (file != null) await file.delete();
    } catch (e) {
      debugPrint('[Photos] не удалось удалить $path: $e');
    }
  }

  static Future<void> deleteAll(Iterable<String> paths) async {
    for (final path in paths) {
      await delete(path);
    }
  }

  /// Удаляет файлы, на которые больше никто не ссылается.
  ///
  /// Такие остаются после сбоя на середине отправки, после удаления черновика
  /// сторонним кодом и — главное — после переустановки базы: каталог с
  /// файлами переживает и очистку Hive, и обновление приложения. Без уборки
  /// они копились бы вечно (п. 4.1.5 отчёта).
  ///
  /// [referenced] — все пути, упомянутые в очередях **на момент вызова**.
  /// Вызывать только на старте, до того как обходчик успеет снять новый
  /// кадр: иначе гонка удалит только что сохранённый файл.
  static Future<int> deleteOrphans(Set<String> referenced) async {
    var removed = 0;
    try {
      // Сверяем по именам файлов, а не по полным путям: после переустановки
      // каталог мог переехать, и уцелевший снимок с «старым» путём в очереди
      // иначе выглядел бы осиротевшим и был бы удалён.
      final keep = referenced.map(_basename).toSet();
      final dir = await _dir();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (keep.contains(_basename(entity.path))) continue;
        await entity.delete();
        removed++;
      }
    } catch (e) {
      debugPrint('[Photos] уборка осиротевших не удалась: $e');
    }
    return removed;
  }
}
