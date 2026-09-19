import '../domain/tour.dart';
import 'demo_tours.dart';

/// Turns a [TourRequest] into a [Tour].
///
/// The prototype ships with [MockTourGenerator], which assembles a tour from
/// hand-written Soho content. Swap in a backend-backed implementation (LLM
/// script + TTS) by providing a different instance to `tourGeneratorProvider`.
abstract class TourGenerator {
  Future<Tour> generate(TourRequest request);
}

class MockTourGenerator implements TourGenerator {
  const MockTourGenerator({this.delay = const Duration(seconds: 4)});

  /// Simulated "writing the show" time so the loading screen gets a moment.
  final Duration delay;

  @override
  Future<Tour> generate(TourRequest request) async {
    await Future<void>.delayed(delay);
    return DemoTours.build(request);
  }
}
