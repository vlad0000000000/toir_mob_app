import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/feature_flags.dart';

void main() {
  group('FeatureFlags.pprEnabled', () {
    test('включён, если PPR_ENABLED не задан', () {
      dotenv.testLoad(fileInput: 'API_ENDPOINT=https://example.test');
      expect(FeatureFlags.pprEnabled, isTrue);
    });

    test('выключается только явным PPR_ENABLED=false', () {
      dotenv.testLoad(fileInput: 'PPR_ENABLED=false');
      expect(FeatureFlags.pprEnabled, isFalse);
    });

    test('регистр и пробелы не важны', () {
      dotenv.testLoad(fileInput: 'PPR_ENABLED= False ');
      expect(FeatureFlags.pprEnabled, isFalse);
    });

    test('включён при любом другом значении', () {
      for (final value in ['true', 'True', '0', '1', 'yes', '']) {
        dotenv.testLoad(fileInput: 'PPR_ENABLED=$value');
        expect(FeatureFlags.pprEnabled, isTrue, reason: 'значение "$value"');
      }
    });
  });
}
