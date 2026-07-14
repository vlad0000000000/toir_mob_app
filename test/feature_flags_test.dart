import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scan_industry/src/feature_flags.dart';

void main() {
  group('FeatureFlags.pprEnabled', () {
    test('выключен, если PPR_ENABLED отсутствует (прод)', () {
      dotenv.testLoad(fileInput: 'API_ENDPOINT=https://example.test');
      expect(FeatureFlags.pprEnabled, isFalse);
    });

    test('включён только при PPR_ENABLED=true (дев)', () {
      dotenv.testLoad(fileInput: 'PPR_ENABLED=true');
      expect(FeatureFlags.pprEnabled, isTrue);
    });

    test('регистр и пробелы не важны', () {
      dotenv.testLoad(fileInput: 'PPR_ENABLED=True');
      expect(FeatureFlags.pprEnabled, isTrue);
    });

    test('выключен при любом другом значении', () {
      for (final value in ['false', '0', '1', 'yes', '']) {
        dotenv.testLoad(fileInput: 'PPR_ENABLED=$value');
        expect(FeatureFlags.pprEnabled, isFalse, reason: 'значение "$value"');
      }
    });
  });
}
