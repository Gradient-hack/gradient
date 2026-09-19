import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots taken via `binding.takeScreenshot` to
/// `build/screenshots/{name}.png` (override with GRADIENT_SHOTS_DIR).
Future<void> main() async {
  final dir = Directory(
    Platform.environment['GRADIENT_SHOTS_DIR'] ?? 'build/screenshots',
  );
  await dir.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
