import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tour_generator.dart';
import '../domain/tour.dart';

/// Swap this override to plug in a real backend.
final tourGeneratorProvider = Provider<TourGenerator>(
  (ref) => const MockTourGenerator(),
);

/// The three inputs on the create screen.
class TourRequestNotifier extends Notifier<TourRequest> {
  @override
  TourRequest build() => const TourRequest(
        interests: {Interest.oddities},
        durationMinutes: 30,
        tone: Tone.playful,
      );

  void toggleInterest(Interest i) {
    final next = {...state.interests};
    if (!next.remove(i)) next.add(i);
    state = state.copyWith(interests: next);
  }

  void setDuration(int minutes) =>
      state = state.copyWith(durationMinutes: minutes);

  void setTone(Tone t) => state = state.copyWith(tone: t);

  void setLocation(double lat, double lng) =>
      state = state.copyWith(lat: lat, lng: lng);
}

final tourRequestProvider =
    NotifierProvider<TourRequestNotifier, TourRequest>(TourRequestNotifier.new);

/// The most recently generated tour (null until the user generates one).
class CurrentTourNotifier extends Notifier<Tour?> {
  @override
  Tour? build() => null;

  Future<Tour> generate() async {
    final request = ref.read(tourRequestProvider);
    final tour = await ref.read(tourGeneratorProvider).generate(request);
    state = tour;
    return tour;
  }

  void clear() => state = null;
}

final currentTourProvider =
    NotifierProvider<CurrentTourNotifier, Tour?>(CurrentTourNotifier.new);
