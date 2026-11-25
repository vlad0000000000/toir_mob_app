import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// Сборка приложения, которой сервер помечает установку
/// (`PUT /v1/mobile/installations/{uuid}`, бэкенд `81f644c`).
///
/// По паре «пакет + номер сборки» сервер находит сборку в каталоге
/// суперадминки: от неё зависят статус поддержки и ссылка на RuStore. Ссылку
/// сервер даёт только продовому пакету из RuStore и только сборке старше
/// последней опубликованной.
class MobileBuild {
  /// `android` или `ios` — как в схеме сервера.
  final String platform;
  final String packageName;
  final int buildNumber;
  final String versionName;

  const MobileBuild({
    required this.platform,
    required this.packageName,
    required this.buildNumber,
    required this.versionName,
  });

  /// Сборка из данных пакета. `null` — данные не годятся для сервера: он
  /// требует номер сборки больше нуля и непустые пакет и версию, иначе 422.
  static MobileBuild? fromPackage({
    required bool isIos,
    required String packageName,
    required String version,
    required String buildNumber,
  }) {
    final number = int.tryParse(buildNumber.trim());
    final package = packageName.trim();
    final name = version.trim();
    if (number == null || number <= 0 || package.isEmpty || name.isEmpty) {
      return null;
    }
    return MobileBuild(
      platform: isIos ? 'ios' : 'android',
      packageName: package,
      buildNumber: number,
      versionName: name,
    );
  }

  /// Сборка, на которой запущено приложение. Читается с платформы один раз.
  static Future<MobileBuild?> current() => _current ??= _read();

  static Future<MobileBuild?>? _current;

  /// Уже прочитанная сборка ([current]) — для синхронных мест: заголовка
  /// `X-Mobile-Build-Number` и сверки сохранённого статуса поддержки.
  /// `null` — ещё не читали (`main.dart` читает до первого запроса) или
  /// данные пакета не годятся для сервера.
  static MobileBuild? get known => _known;

  static MobileBuild? _known;

  static Future<MobileBuild?> _read() async {
    final info = await PackageInfo.fromPlatform();
    return _known = fromPackage(
      isIos: Platform.isIOS,
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  /// Отпечаток сборки: сменился — регистрацию нужно повторить сразу, не
  /// дожидаясь интервала (обновили приложение).
  String get signature => '$platform|$packageName|$buildNumber|$versionName';

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'package_name': packageName,
        'build_number': buildNumber,
        'version_name': versionName,
      };
}
