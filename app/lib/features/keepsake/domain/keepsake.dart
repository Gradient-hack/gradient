import 'package:flutter/foundation.dart';

import '../../tour/domain/tour.dart';
import '../../walk/domain/walk_state.dart';

@immutable
class KeepsakeStop {
  const KeepsakeStop({
    required this.name,
    required this.lat,
    required this.lng,
    this.photoPath,
    this.correct,
  });

  final String name;
  final double lat;
  final double lng;
  final String? photoPath;

  /// null = unanswered.
  final bool? correct;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'photoPath': photoPath,
        'correct': correct,
      };

  factory KeepsakeStop.fromJson(Map<String, dynamic> j) => KeepsakeStop(
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        photoPath: j['photoPath'] as String?,
        correct: j['correct'] as bool?,
      );
}

/// What you take home from a walk: route, snaps, score, sources.
@immutable
class Keepsake {
  const Keepsake({
    required this.id,
    required this.title,
    required this.neighbourhood,
    required this.startedAt,
    required this.finishedAt,
    required this.stops,
    required this.sources,
  });

  final String id;
  final String title;
  final String neighbourhood;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<KeepsakeStop> stops;
  final List<Source> sources;

  int get correctCount => stops.where((s) => s.correct ?? false).length;
  int get answeredCount => stops.where((s) => s.correct != null).length;
  List<String> get photoPaths =>
      stops.map((s) => s.photoPath).whereType<String>().toList();
  Duration get duration => finishedAt.difference(startedAt);

  factory Keepsake.fromWalk(WalkState w) {
    final stops = <KeepsakeStop>[];
    for (var i = 0; i < w.tour.stops.length; i++) {
      final s = w.tour.stops[i];
      final a = w.answers[i];
      stops.add(
        KeepsakeStop(
          name: s.name,
          lat: s.lat,
          lng: s.lng,
          photoPath: w.photos[i],
          correct: a == null ? null : a == s.quiz.correctIndex,
        ),
      );
    }
    return Keepsake(
      id: w.tour.id,
      title: w.tour.title,
      neighbourhood: w.tour.neighbourhood,
      startedAt: w.startedAt,
      finishedAt: DateTime.now(),
      stops: stops,
      sources: w.tour.allSources,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'neighbourhood': neighbourhood,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'stops': stops.map((s) => s.toJson()).toList(),
        'sources': sources.map((s) => s.toJson()).toList(),
      };

  factory Keepsake.fromJson(Map<String, dynamic> j) => Keepsake(
        id: j['id'] as String,
        title: j['title'] as String,
        neighbourhood: j['neighbourhood'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        finishedAt: DateTime.parse(j['finishedAt'] as String),
        stops: (j['stops'] as List)
            .map((e) => KeepsakeStop.fromJson(e as Map<String, dynamic>))
            .toList(),
        sources: (j['sources'] as List)
            .map((e) => Source.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
