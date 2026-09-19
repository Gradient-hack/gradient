import 'package:flutter/foundation.dart';

import '../../tour/domain/tour.dart';

/// Where we are in the listen → look → answer → capture → walk loop.
enum WalkPhase {
  /// Walking to `stopIndex`. Hosts may be speaking the intro / a cue.
  navigating,

  /// Arrived; hosts are telling the story of the stop.
  listening,

  /// Hosts asked a question; waiting for the answer.
  quiz,

  /// Quiz answered; asking for a photo.
  photo,

  /// After the last stop; outro playing / summary ready.
  finished,
}

@immutable
class WalkState {
  const WalkState({
    required this.tour,
    required this.startedAt,
    this.stopIndex = 0,
    this.phase = WalkPhase.navigating,
    this.currentLine = -1,
    this.playing = false,
    this.answers = const {},
    this.photos = const {},
    this.distanceToStop,
    this.bearingToStop,
    this.arrived = false,
    this.talking = false,
  });

  final Tour tour;
  final DateTime startedAt;
  final int stopIndex;
  final WalkPhase phase;

  /// Index into the script currently being spoken (-1 = none).
  final int currentLine;
  final bool playing;

  /// stopIndex → chosen option index.
  final Map<int, int> answers;

  /// stopIndex → local file path.
  final Map<int, String> photos;

  final double? distanceToStop;
  final double? bearingToStop;

  /// Whether the device is within arrival radius of the current stop.
  final bool arrived;

  /// A live voice call with the hosts is open; narration is paused.
  final bool talking;

  TourStop get stop => tour.stops[stopIndex];
  bool get isLastStop => stopIndex == tour.stops.length - 1;

  /// The lines being narrated for the current phase.
  List<ScriptLine> get activeScript => switch (phase) {
    WalkPhase.navigating => stopIndex == 0 ? tour.intro : const [],
    WalkPhase.listening => stop.script,
    WalkPhase.finished => tour.outro,
    _ => const [],
  };

  int get correctCount => answers.entries
      .where((e) => tour.stops[e.key].quiz.correctIndex == e.value)
      .length;

  WalkState copyWith({
    int? stopIndex,
    WalkPhase? phase,
    int? currentLine,
    bool? playing,
    Map<int, int>? answers,
    Map<int, String>? photos,
    double? distanceToStop,
    double? bearingToStop,
    bool? arrived,
    bool? talking,
    bool clearDistance = false,
  }) => WalkState(
    tour: tour,
    startedAt: startedAt,
    stopIndex: stopIndex ?? this.stopIndex,
    phase: phase ?? this.phase,
    currentLine: currentLine ?? this.currentLine,
    playing: playing ?? this.playing,
    answers: answers ?? this.answers,
    photos: photos ?? this.photos,
    distanceToStop: clearDistance
        ? null
        : distanceToStop ?? this.distanceToStop,
    bearingToStop: clearDistance ? null : bearingToStop ?? this.bearingToStop,
    arrived: arrived ?? this.arrived,
    talking: talking ?? this.talking,
  );
}
