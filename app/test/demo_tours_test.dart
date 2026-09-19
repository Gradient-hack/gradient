import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/features/tour/data/demo_tours.dart';
import 'package:gradient/features/tour/domain/tour.dart';
import 'package:gradient/features/walk/providers/location_provider.dart';

void main() {
  group('DemoTours.build', () {
    test('trims to duration and keeps walk order', () {
      final tour = DemoTours.build(
        const TourRequest(
          interests: {Interest.history},
          durationMinutes: 15,
          tone: Tone.playful,
        ),
      );
      expect(tour.stops.length, 3);
      expect(tour.intro, isNotEmpty);
      expect(tour.outro, isNotEmpty);
      // Every stop has a quiz with a valid answer and at least one source.
      for (final s in tour.stops) {
        expect(s.quiz.correctIndex, inInclusiveRange(0, s.quiz.options.length - 1));
        expect(s.sources, isNotEmpty);
        expect(s.script, isNotEmpty);
      }
    });

    test('only music stops for a music-only request', () {
      final tour = DemoTours.build(
        const TourRequest(
          interests: {Interest.music},
          durationMinutes: 60,
          tone: Tone.curious,
        ),
      );
      expect(tour.stops.every((s) => s.interests.contains(Interest.music)), isTrue);
      expect(tour.title, contains('noise'));
    });

    test('falls back to the full loop when nothing matches well', () {
      final tour = DemoTours.build(
        const TourRequest(
          interests: {},
          durationMinutes: 60,
          tone: Tone.deepDive,
        ),
      );
      expect(tour.stops.length, greaterThanOrEqualTo(3));
    });
  });

  group('geo helpers', () {
    test('compass labels', () {
      expect(compassLabel(0), 'north');
      expect(compassLabel(90), 'east');
      expect(compassLabel(225), 'south-west');
      expect(compassLabel(359), 'north');
    });

    test('bearing from Soho Square to Carnaby Street is roughly south-west', () {
      final b = bearingDegrees(51.5155, -0.1320, 51.5130, -0.1392);
      expect(compassLabel(b), 'south-west');
    });

    test('distance formatting', () {
      expect(formatDistance(240.4), '240 m');
      expect(formatDistance(1250), '1.3 km');
    });
  });
}
