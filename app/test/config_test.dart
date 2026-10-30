import 'package:bubbleapp/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app is not considered configured without dart-define values', () {
    // Tests run without --dart-define, so no fake backend is ever assumed.
    expect(AppConfig.isConfigured, isFalse);
  });

  test('official channel is addressed by username, not a hardcoded id', () {
    expect(AppConfig.officialChannelUsername, 'bubbleapp');
  });
}
