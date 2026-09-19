import 'dart:math' as math;

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/walking_directions.dart';

/// A point on the route with a display label.
class MapStopPin {
  const MapStopPin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.title,
    this.highlighted = false,
    this.done = false,
  });

  final String id;
  final double lat;
  final double lng;
  final String title;
  final bool highlighted;
  final bool done;
}

/// Apple Map showing the route polyline and numbered stops. Optionally
/// follows [focus] (e.g. the user's position) instead of fitting the route.
class TourMap extends StatefulWidget {
  const TourMap({
    required this.pins,
    super.key,
    this.focus,
    this.showUserLocation = false,
    this.interactive = true,
    this.padding = 60,
  });

  final List<MapStopPin> pins;

  /// When set, the camera follows this point at street zoom.
  final LatLng? focus;
  final bool showUserLocation;
  final bool interactive;
  final double padding;

  @override
  State<TourMap> createState() => _TourMapState();
}

class _TourMapState extends State<TourMap> {
  AppleMapController? _controller;

  /// Real walking route from MapKit; null if directions are unavailable
  /// (straight lines between stops are drawn instead).
  List<LatLng>? _route;
  String _routeKey = '';

  /// The map is only created once the route is known: apple_maps_flutter
  /// doesn't repaint a polyline that is swapped after creation, so we wait
  /// (briefly) instead of drawing a placeholder line first.
  bool _routeReady = false;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void didUpdateWidget(covariant TourMap old) {
    super.didUpdateWidget(old);
    final f = widget.focus;
    if (f != null && (old.focus?.latitude != f.latitude || old.focus?.longitude != f.longitude)) {
      _controller?.animateCamera(CameraUpdate.newLatLng(f));
    }
    _loadRoute();
  }

  List<LatLng> get _stopPoints => widget.pins.map((p) => LatLng(p.lat, p.lng)).toList();

  Future<void> _loadRoute() async {
    final points = _stopPoints;
    final key = points.map((p) => '${p.latitude},${p.longitude}').join(';');
    if (key == _routeKey) return;
    _routeKey = key;
    final route = await WalkingDirections.route(points)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (!mounted || key != _routeKey) return;
    setState(() {
      _route = route;
      _routeReady = true;
    });
  }

  List<LatLng> _routeBounds() => _route ?? _stopPoints;

  CameraPosition _initialCamera() {
    if (widget.focus != null) {
      return CameraPosition(target: widget.focus!, zoom: 16.5);
    }
    if (widget.pins.isEmpty) {
      return const CameraPosition(target: LatLng(51.5136, -0.1340), zoom: 15);
    }
    final lat = widget.pins.map((p) => p.lat).reduce((a, b) => a + b) / widget.pins.length;
    final lng = widget.pins.map((p) => p.lng).reduce((a, b) => a + b) / widget.pins.length;
    return CameraPosition(target: LatLng(lat, lng), zoom: 15.2);
  }

  Future<void> _fit() async {
    final c = _controller;
    if (c == null || widget.pins.length < 2 || widget.focus != null) return;
    var minLat = double.infinity, minLng = double.infinity;
    var maxLat = -double.infinity, maxLng = -double.infinity;
    for (final p in _routeBounds()) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        widget.padding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeReady) return const ColoredBox(color: AppColors.background);
    final points = _route ?? _stopPoints;
    return AppleMap(
      initialCameraPosition: _initialCamera(),
      onMapCreated: (c) {
        _controller = c;
        _fit();
      },
      myLocationEnabled: widget.showUserLocation,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      zoomGesturesEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false,
      pitchGesturesEnabled: false,
      polylines: {
        if (points.length >= 2)
          Polyline(
            polylineId: PolylineId('route'),
            points: points,
            color: AppColors.primary,
            width: 5,
            jointType: JointType.round,
          ),
      },
      annotations: {
        for (final (i, p) in widget.pins.indexed)
          Annotation(
            annotationId: AnnotationId(p.id),
            position: LatLng(p.lat, p.lng),
            infoWindow: InfoWindow(title: '${i + 1}. ${p.title}'),
            icon: BitmapDescriptor.markerAnnotationWithHue(
              p.highlighted
                  ? BitmapDescriptor.hueOrange
                  : p.done
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueViolet,
            ),
          ),
      },
    );
  }
}
