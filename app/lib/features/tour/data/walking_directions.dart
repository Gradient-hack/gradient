import 'dart:async';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' show LatLng;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Fetches a real walking route through an ordered list of stops from
/// Apple's MapKit (`MKDirections`) via a small platform channel.
///
/// Native side: `ios/Runner/WalkingDirections.swift`.
///
/// Results are cached in memory per stop sequence so the preview, walk and
/// keepsake maps of the same tour only hit MapKit once.
class WalkingDirections {
  WalkingDirections._();

  static const _channel = MethodChannel('gradient/directions');
  static final Map<String, Future<List<LatLng>?>> _cache = {};

  /// Route through [stops] in order. Returns null if the route couldn't be
  /// fetched (no network, not on iOS, …) so callers can fall back to
  /// straight lines between stops.
  static Future<List<LatLng>?> route(List<LatLng> stops) {
    if (stops.length < 2) return Future.value(null);
    final key = stops.map((p) => '${p.latitude},${p.longitude}').join(';');
    return _cache.putIfAbsent(key, () async {
      final result = await _fetch(stops);
      // Don't pin failures in the cache: let the next map retry.
      if (result == null) unawaited(_cache.remove(key));
      return result;
    });
  }

  static Future<List<LatLng>?> _fetch(List<LatLng> stops) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final flat = <double>[
        for (final p in stops) ...[p.latitude, p.longitude],
      ];
      final raw = await _channel.invokeListMethod<double>('route', flat);
      if (raw == null || raw.length < 4) return null;
      return [
        for (var i = 0; i + 1 < raw.length; i += 2) LatLng(raw[i], raw[i + 1]),
      ];
    } on PlatformException catch (e) {
      debugPrint('WalkingDirections failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
