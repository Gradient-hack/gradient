import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the app is running. Native side: `ios/Runner/DeviceEnv.swift`.
class DeviceEnv {
  DeviceEnv._();

  static const _channel = MethodChannel('gradient/device_env');
  static Future<bool>? _isSimulator;

  /// True on the iOS simulator. False on devices, non-iOS platforms, and when
  /// the channel is missing (e.g. widget tests).
  static Future<bool> isSimulator() {
    return _isSimulator ??= () async {
      if (defaultTargetPlatform != TargetPlatform.iOS) return false;
      try {
        return await _channel.invokeMethod<bool>('isSimulator') ?? false;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        return false;
      }
    }();
  }
}
