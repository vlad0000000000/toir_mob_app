import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateManager {
  static String get updateUrl => dotenv.env["UPDATE_URL"]!;

  static String get apkDownloadUrl => dotenv.env["APK_DOWNLOAD_URL"]!;

  static Future<UpdateInfo?> getUpdateInfo() async {
    try {
      final response = await http
          .get(Uri.parse(updateUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return UpdateInfo.fromJson(json.decode(response.body));
      }
    } catch (e) {
      print('Error checking update: $e');
    }
    return null;
  }

  static Future<void> checkForUpdate(BuildContext context) async {
    final updateInfo = await getUpdateInfo();
    if (updateInfo != null) {
      if (await _isNewVersionAvailable(updateInfo.version)) {
        _showUpdateDialog(context, updateInfo);
      }
    }
  }

  static Future<bool> _isNewVersionAvailable(String newVersion) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentParts = packageInfo.version.split('.');
    final newParts = newVersion.split('.');
    final maxLen = currentParts.length > newParts.length
        ? currentParts.length
        : newParts.length;

    for (int i = 0; i < maxLen; i++) {
      final int newPart =
          i < newParts.length ? int.tryParse(newParts[i]) ?? 0 : 0;
      final int currentPart =
          i < currentParts.length ? int.tryParse(currentParts[i]) ?? 0 : 0;
      if (newPart > currentPart) return true;
      if (newPart < currentPart) return false;
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Доступно обновление'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Версия: ${updateInfo.version}'),
              SizedBox(height: 8),
              Text('Что нового:'),
              Text(updateInfo.changelog ?? ''),
            ],
          ),
          actions: [
            if (updateInfo.optional || kIsWeb)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Позже'),
              ),
            ElevatedButton(
              onPressed: () => downloadAndInstall(context, updateInfo),
              child: Text('Обновить'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> downloadAndInstall(
      BuildContext context, UpdateInfo updateInfo) async {
    // Проверка и запрос разрешения на управление внешним хранилищем (если требуется)
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Требуется разрешение на доступ к хранилищу для установки обновления')),
        );
        return;
      }

      // Разрешение на установку пакетов из неизвестных источников
      final installPerm = await Permission.requestInstallPackages.status;
      if (installPerm.isDenied ||
          installPerm.isRestricted ||
          installPerm.isPermanentlyDenied) {
        final req = await Permission.requestInstallPackages.request();
        if (!req.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Разрешение на установку приложений не предоставлено')),
          );
          return;
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        double progress = 0.0;
        bool installing = false;
        bool started = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (ctx, setState) {
            if (!started) {
              started = true;
              Future.microtask(() async {
                try {
                  final filePath = await _downloadAPKWithProgress(
                    onProgress: (fraction) =>
                        setState(() => progress = fraction),
                  );
                  setState(() => installing = true);
                  print(filePath);
                  await _installAPK(filePath);
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                } catch (e) {
                  setState(() => errorMessage = 'Ошибка обновления: $e');
                }
              });
            }

            return AlertDialog(
              title: Text(errorMessage != null
                  ? 'Ошибка'
                  : (installing ? 'Установка…' : 'Загрузка обновления…')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null) ...[
                    Text(errorMessage!),
                  ] else if (!installing) ...[
                    LinearProgressIndicator(
                        value: progress > 0 && progress < 1 ? progress : null),
                    SizedBox(height: 8),
                    Text(
                        progress > 0
                            ? '${(progress * 100).toStringAsFixed(0)}%'
                            : 'Подключение…',
                        textAlign: TextAlign.center),
                  ] else ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Подготовка к установке…'),
                  ],
                ],
              ),
              actions: [
                if (errorMessage != null)
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Закрыть'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<String> _downloadAPKWithProgress(
      {required void Function(double fraction) onProgress}) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(apkDownloadUrl));
      final streamed =
          await client.send(request).timeout(const Duration(minutes: 2));

      final contentLength = streamed.contentLength ?? 0;
      Directory tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/app-update.apk';
      final file = File(filePath);
      final sink = file.openWrite();

      int received = 0;
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          onProgress(received / contentLength);
        } else {
          onProgress(0); // неизвестный размер
        }
      }
      await sink.flush();
      await sink.close();

      if (streamed.statusCode != 200) {
        throw HttpException('Код ответа: ${streamed.statusCode}');
      }

      return filePath;
    } finally {
      client.close();
    }
  }

  static Future<void> _installAPK(String filePath) async {
    if (Platform.isAndroid) {
      await OpenFile.open(filePath);
      // result.type / result.message можно использовать для логирования при необходимости
    }
  }
}

class UpdateInfo {
  final String version;
  final String? changelog;
  final bool optional;

  UpdateInfo({required this.version, this.changelog, this.optional = false});

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'],
      changelog: json['changelog'],
      optional: json['optional'] ?? false,
    );
  }
}
