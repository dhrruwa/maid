import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Saves each binding.takeScreenshot(name) as SCREENSHOT_DIR/name.png
// (default: build/screenshots). Run with:
//   SCREENSHOT_DIR=/some/dir flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_test.dart -d DEVICE --dart-define-from-file=../dart_defines.json \
//     --dart-define=TEST_NAME=... --dart-define=TEST_PIN=...
Future<void> main() async {
  final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('$dir/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
