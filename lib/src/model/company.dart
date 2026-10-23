import 'package:hive_ce/hive.dart';

class Company {
  final int id;
  final String name;
  final String? logoUrl;
  final String? currentTariff;
  final DateTime? tariffValidUntil;
  final bool allowRequestsWithoutQr;
  final bool allowMultipleTasksPerQrScan;

  Company({
    required this.id,
    required this.name,
    this.logoUrl,
    this.currentTariff,
    this.tariffValidUntil,
    required this.allowRequestsWithoutQr,
    this.allowMultipleTasksPerQrScan = false,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as int,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      currentTariff: json['current_tariff'] as String?,
      tariffValidUntil: json['tariff_valid_until'] != null
          ? DateTime.parse(json['tariff_valid_until'] as String)
          : null,
      allowRequestsWithoutQr: json['allow_requests_without_qr'] as bool,
      allowMultipleTasksPerQrScan:
          json['allow_multiple_tasks_per_qr_scan'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'current_tariff': currentTariff,
      'tariff_valid_until': tariffValidUntil?.toIso8601String(),
      'allow_requests_without_qr': allowRequestsWithoutQr,
      'allow_multiple_tasks_per_qr_scan': allowMultipleTasksPerQrScan,
    };
  }
}

/// Компания из `/user/me` — блок `company`: название, логотип и два флага,
/// по которым приложение что-то решает.
///
/// Сервер отдаёт его любой клиентской роли. `/v1/company/me` раньше
/// требовал «Компания: Просмотр», и у роли обходчика без него флаги не
/// приходили вовсе: пропадал вход «Осмотр оборудования» без QR, хотя сам
/// сервер осмотр без QR разрешал. Теперь флаги едут с профилем доступа, тем
/// же запросом раз в минуту, и отдельный `/company/me` не нужен.
class CompanyFlags {
  final String name;
  final String? logoUrl;
  final bool allowRequestsWithoutQr;
  final bool allowMultipleTasksPerQrScan;

  const CompanyFlags({
    required this.name,
    this.logoUrl,
    required this.allowRequestsWithoutQr,
    required this.allowMultipleTasksPerQrScan,
  });

  /// Блок `company` из ответа `/user/me`. `null` — блока нет (сервер прошлой
  /// версии, пользователь без компании) или он не разобрался: тогда флаги
  /// остаются за `/v1/company/me`, а не выключаются по незнанию.
  static CompanyFlags? fromMe(Map<String, dynamic> json) {
    final company = json['company'];
    if (company is! Map) return null;
    final withoutQr = company['allow_requests_without_qr'];
    final multipleTasks = company['allow_multiple_tasks_per_qr_scan'];
    if (withoutQr is! bool || multipleTasks is! bool) return null;
    final name = company['name'];
    final logoUrl = company['logo_url'];
    return CompanyFlags(
      name: name is String ? name : '',
      logoUrl: logoUrl is String ? logoUrl : null,
      allowRequestsWithoutQr: withoutQr,
      allowMultipleTasksPerQrScan: multipleTasks,
    );
  }

  /// Кэш компании с этими флагами. Тариф в блоке не приходит — его берём из
  /// прежнего кэша ([cached]). Кэша нет — компанию собираем по [companyId]
  /// (`access_scope.company_id`); нет и его — собрать не из чего, `null`.
  Company? applyTo(Company? cached, {required int? companyId}) {
    final id = cached?.id ?? companyId;
    if (id == null) return null;
    return Company(
      id: id,
      name: name.isNotEmpty ? name : (cached?.name ?? ''),
      logoUrl: logoUrl,
      currentTariff: cached?.currentTariff,
      tariffValidUntil: cached?.tariffValidUntil,
      allowRequestsWithoutQr: allowRequestsWithoutQr,
      allowMultipleTasksPerQrScan: allowMultipleTasksPerQrScan,
    );
  }
}

class CompanyAdapter extends TypeAdapter<Company> {
  @override
  final int typeId = 15;

  @override
  Company read(BinaryReader reader) {
    return Company(
      id: reader.read(),
      name: reader.read(),
      logoUrl: reader.read(),
      currentTariff: reader.read(),
      tariffValidUntil: reader.read(),
      allowRequestsWithoutQr: reader.read(),
      // Поле добавлено позже — у ранее закэшированных записей его нет.
      allowMultipleTasksPerQrScan:
          reader.availableBytes > 0 ? reader.read() as bool : false,
    );
  }

  @override
  void write(BinaryWriter writer, Company obj) {
    writer.write(obj.id);
    writer.write(obj.name);
    writer.write(obj.logoUrl);
    writer.write(obj.currentTariff);
    writer.write(obj.tariffValidUntil);
    writer.write(obj.allowRequestsWithoutQr);
    writer.write(obj.allowMultipleTasksPerQrScan);
  }
}
