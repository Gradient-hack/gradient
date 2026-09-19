import Flutter

/// Tiny method channel exposing compile-time facts about where the app runs.
///
/// Dart side: `DeviceEnv` in `lib/features/voice_test/data/device_env.dart`.
///
/// `isSimulator` → Bool. Used to skip the `audio_io` pipeline on the iOS
/// simulator, where enabling Apple's voice-processing unit raises an
/// uncatchable ObjC exception and aborts the app.
final class DeviceEnv {
  static let channelName = "gradient/device_env"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSimulator":
        #if targetEnvironment(simulator)
          result(true)
        #else
          result(false)
        #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
