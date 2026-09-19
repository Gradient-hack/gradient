import Flutter
import MapKit

/// Method channel that turns an ordered list of stops into a real walking
/// route using MKDirections, one leg per consecutive pair of stops.
///
/// Dart side: `WalkingDirections` in `lib/features/tour/data/walking_directions.dart`.
///
/// Method `route`, argument `[lat0, lng0, lat1, lng1, …]` (flat list of doubles),
/// returns the route as a flat `[lat, lng, lat, lng, …]` list. Legs that fail
/// (no network, throttled, off-map) fall back to a straight segment so the
/// polyline is always continuous.
final class WalkingDirections {
  static let channelName = "gradient/directions"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "route" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let flat = call.arguments as? [Double], flat.count >= 4, flat.count % 2 == 0 else {
        result(FlutterError(code: "bad_args", message: "Expected a flat [lat, lng, …] list", details: nil))
        return
      }
      var stops: [CLLocationCoordinate2D] = []
      for i in stride(from: 0, to: flat.count, by: 2) {
        stops.append(CLLocationCoordinate2D(latitude: flat[i], longitude: flat[i + 1]))
      }
      route(through: stops) { coords in
        var out: [Double] = []
        out.reserveCapacity(coords.count * 2)
        for c in coords {
          out.append(c.latitude)
          out.append(c.longitude)
        }
        result(out)
      }
    }
  }

  private static func route(
    through stops: [CLLocationCoordinate2D],
    completion: @escaping ([CLLocationCoordinate2D]) -> Void
  ) {
    let legCount = stops.count - 1
    var legs = [[CLLocationCoordinate2D]](repeating: [], count: legCount)
    let group = DispatchGroup()

    for i in 0..<legCount {
      group.enter()
      let from = stops[i]
      let to = stops[i + 1]
      let request = MKDirections.Request()
      request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
      request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
      request.transportType = .walking
      request.requestsAlternateRoutes = false

      MKDirections(request: request).calculate { response, error in
        defer { group.leave() }
        if let route = response?.routes.first {
          legs[i] = coordinates(of: route.polyline)
        } else {
          if let error = error {
            NSLog("[WalkingDirections] leg \(i) failed: \(error.localizedDescription)")
          }
          legs[i] = [from, to]
        }
      }
    }

    group.notify(queue: .main) {
      var merged: [CLLocationCoordinate2D] = []
      for (i, leg) in legs.enumerated() {
        // Drop the first point of every leg after the first: it duplicates the
        // previous leg's end.
        merged.append(contentsOf: i == 0 ? leg : Array(leg.dropFirst()))
      }
      completion(merged)
    }
  }

  private static func coordinates(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
    var coords = [CLLocationCoordinate2D](
      repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
    return coords
  }
}
