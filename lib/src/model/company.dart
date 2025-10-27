import 'package:hive_ce/hive.dart';

@HiveType(typeId: 12)
class Company {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String? logoUrl;
  @HiveField(3)
  final String? currentTariff;
  @HiveField(4)
  final DateTime? tariffValidUntil;
  @HiveField(5)
  final bool allowRequestsWithoutQr;

  Company({
    required this.id,
    required this.name,
    this.logoUrl,
    this.currentTariff,
    this.tariffValidUntil,
    required this.allowRequestsWithoutQr,
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
    };
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
  }
}
