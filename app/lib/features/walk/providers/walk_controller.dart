import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../tour/domain/tour.dart';
import '../../voice/providers/voice_call_controller.dart';
import '../data/narrator.dart';
import '../domain/walk_state.dart';
import 'location_provider.dart';

/// Metres within which we count the user as "arrived".
const kArrivalRadiusMeters = 35.0;

final narratorProvider = Provider<Narrator>((ref) {
  final n = Narrator();
  ref.onDispose(n.dispose);
  return n;
});

/// Drives one walk from start to finish. Created via [start]; null when no
/// walk is active.
class WalkController extends Notifier<WalkState?> {
  @override
  WalkState? build() {
    ref.listen(positionStreamProvider, (_, next) {
      final pos = next.value;
      if (pos != null) _onPosition(pos);
    });
    // If the live call ends on its own (relay closed, fatal error, user hung
    // up from elsewhere), resume the narration.
    ref.listen(voiceCallProvider, (prev, next) {
      final s = state;
      if (s == null || !s.talking) return;
      final ended =
          next.status == VoiceCallStatus.idle ||
          next.status == VoiceCallStatus.error;
      if (ended && prev?.status != next.status) unawaited(_afterTalk());
    });
    // Capture the narrator now: ref can't be used inside life-cycle callbacks.
    final narrator = ref.read(narratorProvider);
    ref.onDispose(() => unawaited(narrator.stop()));
    return null;
  }

  Narrator get _narrator => ref.read(narratorProvider);
  VoiceCallController get _voice => ref.read(voiceCallProvider.notifier);

  // Narration to pick up again after a call.
  bool _resumeAfterTalk = false;
  int _resumeFrom = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start(Tour tour) {
    // Set state synchronously so the walk screen never sees a null walk.
    // speakLines bumps the narrator generation, so any earlier speech is
    // abandoned without an explicit await here.
    unawaited(_narrator.stop());
    state = WalkState(tour: tour, startedAt: DateTime.now());
    _syncPosition();
    unawaited(_playActiveScript());
  }

  /// Apply the latest known position right away. The stream only pushes on
  /// movement, so a stationary device (or the simulator) would otherwise
  /// leave distance/bearing empty until the user takes a few steps.
  void _syncPosition() {
    final pos = ref.read(positionStreamProvider).value;
    // No auto-arrive here: if you're already standing on the stop, the intro
    // (or the direction cue) still gets to play first; arrival follows once
    // it's done, or on the "I'm here" tap.
    if (pos != null) _onPosition(pos, autoArrive: false);
  }

  void end() {
    if (state?.talking == true) unawaited(_voice.stop());
    unawaited(_narrator.stop());
    state = null;
  }

  // ── Live call with the hosts ──────────────────────────────────────────────

  /// Pause the narration and open a live voice call. Whatever was playing
  /// resumes from the same line when the call ends.
  Future<void> askHosts() async {
    final s = state;
    if (s == null || s.talking || s.phase == WalkPhase.finished) return;
    _resumeAfterTalk = s.playing && s.activeScript.isNotEmpty;
    _resumeFrom = s.currentLine < 0 ? 0 : s.currentLine;
    await _narrator.stop();
    state = s.copyWith(talking: true, playing: false);
    final url = await _voice.loadRelayUrl();
    if (state?.talking != true) return; // Cancelled while loading.
    await _voice.start(url);
  }

  /// Hang up and carry on with the walk.
  Future<void> endTalk() async {
    if (state?.talking != true) return;
    await _voice.stop();
    await _afterTalk();
  }

  Future<void> _afterTalk() async {
    final s = state;
    if (s == null || !s.talking) return;
    state = s.copyWith(talking: false);
    // The call owned the audio session; hand it back to text-to-speech.
    await _narrator.reclaimAudioSession();
    final cur = state;
    if (cur == null || cur.talking) return;
    if (_resumeAfterTalk && cur.activeScript.isNotEmpty) {
      unawaited(_playActiveScript(from: _resumeFrom));
    }
    _resumeAfterTalk = false;
  }

  /// Any explicit walk action while on a call hangs up first, without
  /// resuming the old narration (the new phase brings its own).
  Future<void> _hangUpIfTalking() async {
    final s = state;
    if (s == null || !s.talking) return;
    _resumeAfterTalk = false;
    await _voice.stop();
    state = state?.copyWith(talking: false);
    await _narrator.reclaimAudioSession();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  void _onPosition(Position pos, {bool autoArrive = true}) {
    final s = state;
    if (s == null || s.phase == WalkPhase.finished) return;
    final d = distanceMeters(
      pos.latitude,
      pos.longitude,
      s.stop.lat,
      s.stop.lng,
    );
    final b = bearingDegrees(
      pos.latitude,
      pos.longitude,
      s.stop.lat,
      s.stop.lng,
    );
    final arrived = d <= kArrivalRadiusMeters;
    state = s.copyWith(distanceToStop: d, bearingToStop: b, arrived: arrived);
    // Auto-arrive only once the intro has finished so the hosts don't talk
    // over themselves.
    if (autoArrive &&
        arrived &&
        s.phase == WalkPhase.navigating &&
        !s.playing &&
        !s.talking) {
      unawaited(arrive());
    }
  }

  // ── Phase transitions ─────────────────────────────────────────────────────

  /// User reached the stop (auto or via the "I'm here" button).
  Future<void> arrive() async {
    var s = state;
    if (s == null || s.phase != WalkPhase.navigating) return;
    await _hangUpIfTalking();
    s = state;
    if (s == null || s.phase != WalkPhase.navigating) return;
    await _narrator.stop();
    state = s.copyWith(
      phase: WalkPhase.listening,
      currentLine: -1,
      arrived: true,
    );
    unawaited(_playActiveScript());
  }

  /// Hosts have finished the story → ask the question.
  void _askQuestion() {
    final s = state;
    if (s == null || s.phase != WalkPhase.listening) return;
    state = s.copyWith(phase: WalkPhase.quiz, playing: false, currentLine: -1);
    unawaited(
      _narrator.say(
        Host.b,
        'Quick one before we move on. ${s.stop.quiz.question}',
      ),
    );
  }

  Future<void> answer(int optionIndex) async {
    final s = state;
    if (s == null || s.phase != WalkPhase.quiz) return;
    final correct = s.stop.quiz.correctIndex == optionIndex;
    state = s.copyWith(
      answers: {...s.answers, s.stopIndex: optionIndex},
      phase: WalkPhase.photo,
    );
    await _narrator.stop();
    final verdict = correct ? 'Yes! ' : 'Not quite. ';
    unawaited(
      _narrator.say(
        Host.a,
        '$verdict${s.stop.quiz.explanation} Grab a photo of ${s.stop.photoPrompt}',
      ),
    );
  }

  void attachPhoto(String path) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(photos: {...s.photos, s.stopIndex: path});
  }

  /// Leave the current stop: next stop, or finish.
  Future<void> continueWalk() async {
    await _hangUpIfTalking();
    final s = state;
    if (s == null) return;
    await _narrator.stop();
    if (s.isLastStop) {
      state = s.copyWith(
        phase: WalkPhase.finished,
        currentLine: -1,
        clearDistance: true,
      );
      unawaited(_playActiveScript());
      return;
    }
    final next = s.stopIndex + 1;
    state = s.copyWith(
      stopIndex: next,
      phase: WalkPhase.navigating,
      currentLine: -1,
      arrived: false,
      clearDistance: true,
    );
    _syncPosition();
    final nextStop = s.tour.stops[next];
    unawaited(
      _narrator.say(
        Host.b,
        'Next up, ${nextStop.name}. ${nextStop.directionsHint}',
      ),
    );
  }

  /// Skip the remaining narration of the current phase.
  Future<void> skip() async {
    await _hangUpIfTalking();
    final s = state;
    if (s == null) return;
    await _narrator.stop();
    if (s.phase == WalkPhase.listening) {
      _askQuestion();
    } else {
      state = s.copyWith(playing: false, currentLine: -1);
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> togglePlay() async {
    final s = state;
    if (s == null || s.talking) return;
    if (s.playing) {
      await _narrator.stop();
      state = s.copyWith(playing: false);
    } else {
      final from = s.currentLine < 0 ? 0 : s.currentLine;
      unawaited(_playActiveScript(from: from));
    }
  }

  Future<void> _playActiveScript({int from = 0}) async {
    final s = state;
    if (s == null) return;
    final lines = s.activeScript;
    if (lines.isEmpty) return;
    final phase = s.phase;
    final stopIndex = s.stopIndex;
    state = s.copyWith(playing: true);

    final completed = await _narrator.speakLines(
      lines,
      from: from,
      onLine: (i) {
        final cur = state;
        if (cur != null && cur.phase == phase && cur.stopIndex == stopIndex) {
          state = cur.copyWith(currentLine: i);
        }
      },
    );

    final cur = state;
    if (cur == null || cur.phase != phase || cur.stopIndex != stopIndex) return;
    if (!completed) return; // stopped/paused elsewhere; they set state.
    state = cur.copyWith(playing: false);
    if (phase == WalkPhase.listening) {
      _askQuestion();
    } else if (phase == WalkPhase.navigating && cur.arrived) {
      unawaited(arrive());
    }
  }
}

final walkControllerProvider = NotifierProvider<WalkController, WalkState?>(
  WalkController.new,
);
