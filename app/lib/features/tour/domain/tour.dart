import 'package:flutter/foundation.dart';

/// What the user is curious about. Drives which stops/stories get picked.
enum Interest {
  history('History', '🏛️'),
  food('Food & drink', '🍜'),
  music('Music', '🎸'),
  oddities('Oddities', '🧐'),
  architecture('Architecture', '🏗️'),
  nightlife('Nightlife', '🌙');

  const Interest(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// How the hosts should sound.
enum Tone {
  playful('Playful', 'Banter, jokes, a bit cheeky'),
  curious('Curious', 'Warm, wide-eyed, lots of questions'),
  deepDive('Deep dive', 'Slower, denser, more detail');

  const Tone(this.label, this.description);
  final String label;
  final String description;
}

/// The three inputs that generate a walk.
@immutable
class TourRequest {
  const TourRequest({
    required this.interests,
    required this.durationMinutes,
    required this.tone,
    this.lat,
    this.lng,
  });

  final Set<Interest> interests;
  final int durationMinutes;
  final Tone tone;
  final double? lat;
  final double? lng;

  TourRequest copyWith({
    Set<Interest>? interests,
    int? durationMinutes,
    Tone? tone,
    double? lat,
    double? lng,
  }) =>
      TourRequest(
        interests: interests ?? this.interests,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        tone: tone ?? this.tone,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );
}

/// One of the two podcast hosts.
enum Host {
  a('Mara', 'M'),
  b('Theo', 'T');

  const Host(this.name, this.initial);
  final String name;
  final String initial;
}

/// One spoken line of the podcast script.
@immutable
class ScriptLine {
  const ScriptLine(this.host, this.text);
  final Host host;
  final String text;

  Map<String, dynamic> toJson() => {'host': host.name, 'text': text};
  factory ScriptLine.fromJson(Map<String, dynamic> j) => ScriptLine(
        Host.values.firstWhere((h) => h.name == j['host']),
        j['text'] as String,
      );
}

/// A real question with a real answer, asked at the stop.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

@immutable
class Source {
  const Source({required this.title, required this.url});
  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};
  factory Source.fromJson(Map<String, dynamic> j) =>
      Source(title: j['title'] as String, url: j['url'] as String);
}

@immutable
class TourStop {
  const TourStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.directionsHint,
    required this.script,
    required this.quiz,
    required this.sources,
    required this.photoPrompt,
    this.interests = const {},
  });

  final String id;
  final String name;
  final double lat;
  final double lng;

  /// Human directions read out while walking here ("Head down Frith St…").
  final String directionsHint;

  /// The conversation the hosts have once you've arrived.
  final List<ScriptLine> script;
  final QuizQuestion quiz;
  final List<Source> sources;

  /// What to photograph here.
  final String photoPrompt;
  final Set<Interest> interests;
}

@immutable
class Tour {
  const Tour({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.neighbourhood,
    required this.durationMinutes,
    required this.tone,
    required this.intro,
    required this.outro,
    required this.stops,
  });

  final String id;
  final String title;
  final String subtitle;
  final String neighbourhood;
  final int durationMinutes;
  final Tone tone;

  /// Spoken once at the start, while walking to stop 1.
  final List<ScriptLine> intro;

  /// Spoken after the last stop.
  final List<ScriptLine> outro;
  final List<TourStop> stops;

  List<Source> get allSources => [
        for (final s in stops) ...s.sources,
      ];
}
