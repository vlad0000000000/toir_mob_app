import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:qr_machine_scanner/src/storage/key_value_storage.dart';

/// файловое хранилище, по сути читалка/писалка из/в файл
class FileStorage extends KeyValueStorage {

  @override
  Future<bool?> sync() {
    // TODO: implement sync
    return super.sync();
  }

  /// имя файла
  final String fileName;

  FileStorage(this.fileName);

  /// получаем путь к файлу
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }

  /// получаем хендлер файла
  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/${this.fileName}');
  }

  /// читаем файл
  Future<String> read() async {
    final file = await _localFile;

    bool fileExists = await file.exists();
    if (!fileExists) {
      await write('');
    }

    return file.readAsString();
  }

  /// читаем файл и обрабатываем функциней [processContent]
  Future<bool> readProcess(void Function(String content) processContent) async {
    try {
      final file = await _localFile;

      bool fileExists = await file.exists();
      if (!fileExists) {
        await write('');
      }

      // Read the file
      String contents = await file.readAsString();

      processContent(contents);

      return true;
    } catch (e) {
      return false;
      // If encountering an error, return 0
    }
  }

  /// пишем в файл
  Future<File> write(String data) async {
    final file = await _localFile;

    // Write the file
    return file.writeAsString(data);
  }
}
