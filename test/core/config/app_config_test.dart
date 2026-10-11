import 'package:flutter_test/flutter_test.dart';
import 'package:kizuna_veda/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('validate throws StateError when required environment variables are missing', () {
      expect(() => AppConfig.validate(), throwsA(isA<StateError>()));
    });
  });
}
