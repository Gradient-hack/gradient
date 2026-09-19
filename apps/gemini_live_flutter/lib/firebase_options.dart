import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration supplied at run time with `--dart-define`.
///
/// Keeping these values out of source control makes the demo easy to point at
/// a disposable Firebase project. Run `flutterfire configure` for a generated
/// production configuration when the app gets a permanent Firebase project.
class DemoFirebaseOptions {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static bool get isConfigured {
    final sharedValuesPresent =
        apiKey.isNotEmpty &&
        projectId.isNotEmpty &&
        messagingSenderId.isNotEmpty;

    final appIdPresent = switch (defaultTargetPlatform) {
      TargetPlatform.android => androidAppId.isNotEmpty,
      TargetPlatform.iOS => iosAppId.isNotEmpty,
      _ => false,
    };

    return sharedValuesPresent && appIdPresent;
  }

  static FirebaseOptions get currentPlatform {
    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android => androidAppId,
      TargetPlatform.iOS => iosAppId,
      _ => '',
    };

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }
}
