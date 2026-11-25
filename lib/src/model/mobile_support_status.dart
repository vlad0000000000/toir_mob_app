import 'package:flutter/foundation.dart';

/// Что показать на главной по статусу поддержки версии.
enum SupportNotice {
  /// Ничего: версия поддерживается или сервер её не знает.
  none,

  /// Поддержка завершится [MobileSupportStatus.supportEndsAt].
  endingSoon,

  /// Поддержка завершена.
  obsolete,

  /// Суперадмин вручную ограничил работу этой версии (`work_blocked`,
  /// бэкенд `811c4dc`): новых плановых задач и взятия ремонта нет, очередь
  /// принимается. Важнее дат поддержки.
  workBlocked,
}

/// Статус поддержки версии приложения (бэкенд `81f644c`): ответ
/// `GET /v1/mobile/support-status` и регистрации установки.
///
/// Даты поддержки — только предупреждение: даже у завершённой доступ
/// остаётся. Работу ограничивает лишь ручной [workBlocked] (бэкенд
/// `811c4dc`), и то частично: сервер не отдаёт новые плановые задачи и не
/// даёт взять ремонт (426), а очередь осмотров, фото и ремонтов принимает.
class MobileSupportStatus {
  /// `supported`, `ending_soon`, `obsolete` или `unknown`.
  final String status;
  final String? versionName;
  final DateTime? supportEndsAt;
  final String? updateUrl;

  /// Работа версии ограничена вручную (`work_blocked`).
  final bool workBlocked;

  const MobileSupportStatus({
    required this.status,
    this.versionName,
    this.supportEndsAt,
    this.updateUrl,
    this.workBlocked = false,
  });

  /// `null` — ответ без статуса: показывать нечего.
  static MobileSupportStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = json['status'];
    if (status is! String || status.isEmpty) return null;
    final version = json['version_name'];
    final url = json['update_url'];
    return MobileSupportStatus(
      status: status,
      versionName: version is String && version.isNotEmpty ? version : null,
      supportEndsAt: DateTime.tryParse('${json['support_ends_at'] ?? ''}'),
      updateUrl: url is String && url.isNotEmpty ? url : null,
      // Сервер прошлой версии поля не знает — не ограничено.
      workBlocked: json['work_blocked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'version_name': versionName,
        'support_ends_at': supportEndsAt?.toUtc().toIso8601String(),
        'update_url': updateUrl,
        'work_blocked': workBlocked,
      };

  /// Что показать в момент [now].
  ///
  /// Дату сверяем и сами: статус мог прийти «скоро завершится» до даты
  /// окончания, а телефон с тех пор без связи — тогда после даты показываем
  /// «завершена», не дожидаясь сервера.
  SupportNotice noticeAt(DateTime now) {
    if (workBlocked) return SupportNotice.workBlocked;
    if (status == 'obsolete') return SupportNotice.obsolete;
    final ends = supportEndsAt;
    if (status == 'ending_soon') {
      return ends != null && !now.isBefore(ends)
          ? SupportNotice.obsolete
          : SupportNotice.endingSoon;
    }
    return SupportNotice.none;
  }

  /// Ссылка на RuStore, если её можно открыть. Только `https`: адрес приходит
  /// с сервера, и открывать по нему другие схемы (`intent:`, `file:`)
  /// приложение не должно.
  Uri? get safeUpdateUri {
    final raw = updateUrl;
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}

/// Отладочный показ плашки поддержки на главной — посмотреть её без
/// настоящего статуса с сервера. Включается при запуске:
/// `flutter run --dart-define=PREVIEW_SUPPORT_STATUS=work_blocked` (или
/// `obsolete`, `ending_soon`). В релизной сборке выключено всегда
/// (`kDebugMode`).
const String previewSupportStatusMode =
    kDebugMode ? String.fromEnvironment('PREVIEW_SUPPORT_STATUS') : '';

/// Отладочный статус для [previewSupportStatusMode] (`null` — показ
/// выключен или значение неизвестно): версия 1.0, ссылка на RuStore. Плашка
/// и окно синхронизации берут его вместо настоящего, на сервер ничего не
/// уходит.
MobileSupportStatus? previewSupportStatus(
  DateTime now, {
  String mode = previewSupportStatusMode,
}) {
  const url = 'https://www.rustore.ru/catalog/app/pakgroup.qr.scanner.prod';
  switch (mode) {
    case 'work_blocked':
      return const MobileSupportStatus(
        status: 'obsolete',
        versionName: '1.0',
        updateUrl: url,
        workBlocked: true,
      );
    case 'obsolete':
      return const MobileSupportStatus(
        status: 'obsolete',
        versionName: '1.0',
        updateUrl: url,
      );
    case 'ending_soon':
      return MobileSupportStatus(
        status: 'ending_soon',
        versionName: '1.0',
        supportEndsAt: now.add(const Duration(days: 5)),
        updateUrl: url,
      );
  }
  return null;
}
