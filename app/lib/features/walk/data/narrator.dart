import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../tour/domain/tour.dart';

/// Speaks a script line-by-line using on-device iOS voices, one voice per
/// host. Prototype stand-in for pre-rendered podcast audio.
class Narrator {
  Narrator() {
    _ready = _init();
  }

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready;

  Map<String, String>? _voiceA;
  Map<String, String>? _voiceB;

  /// Incremented on every stop() so a stale speak loop knows to bail out.
  int _generation = 0;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> _init() async {
    try {
      await _tts.setSharedInstance(true);
      await _configureSession();
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5);
      await _pickVoices();
    } catch (e) {
      debugPrint('Narrator init failed: $e');
    }
  }

  Future<void> _configureSession() =>
      _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.allowAirPlay,
      ], IosTextToSpeechAudioMode.spokenAudio);

  /// Re-applies the playback audio session after something else (the live
  /// voice call's play-and-record session) has owned it.
  Future<void> reclaimAudioSession() async {
    await _ready;
    try {
      await _configureSession();
    } catch (e) {
      debugPrint('Narrator reclaim failed: $e');
    }
  }

  /// Two distinct English voices. Prefers a GB + US pairing; falls back to
  /// pitch variation if only one voice exists.
  Future<void> _pickVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return;
    final voices = raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
        .where((m) => (m['locale'] ?? '').startsWith('en'))
        .toList();
    if (voices.isEmpty) return;

    Map<String, String>? byName(String name) =>
        voices.where((v) => v['name'] == name).firstOrNull;
    Map<String, String>? byLocale(String loc, {Map<String, String>? not}) =>
        voices.where((v) => v['locale'] == loc && v != not).firstOrNull;

    // Apple's stock names: Samantha (en-US), Daniel (en-GB), Karen (en-AU).
    _voiceA = byName('Samantha') ?? byLocale('en-US') ?? voices.first;
    _voiceB =
        byName('Daniel') ??
        byLocale('en-GB', not: _voiceA) ??
        byLocale('en-AU', not: _voiceA) ??
        voices.where((v) => v != _voiceA).firstOrNull;
  }

  Future<void> _applyHost(Host host) async {
    final voice = host == Host.a ? _voiceA : _voiceB;
    if (voice != null) {
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    }
    // Slight pitch split so the hosts read differently even with one voice.
    await _tts.setPitch(host == Host.a ? 1.05 : 0.92);
  }

  /// Speaks [lines] starting at [from]. Calls [onLine] before each line.
  /// Returns true if it reached the end without being stopped.
  Future<bool> speakLines(
    List<ScriptLine> lines, {
    int from = 0,
    void Function(int index)? onLine,
  }) async {
    await _ready;
    final gen = ++_generation;
    _speaking = true;
    try {
      for (var i = from; i < lines.length; i++) {
        if (gen != _generation) return false;
        onLine?.call(i);
        await _applyHost(lines[i].host);
        if (gen != _generation) return false;
        await _tts.speak(lines[i].text);
        if (gen != _generation) return false;
        // Small beat between speakers.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      return gen == _generation;
    } finally {
      if (gen == _generation) _speaking = false;
    }
  }

  /// Speak a single line, e.g. a direction cue. Fire-and-forget safe.
  Future<void> say(Host host, String text) async {
    await _ready;
    final gen = ++_generation;
    _speaking = true;
    try {
      await _applyHost(host);
      if (gen != _generation) return;
      await _tts.speak(text);
    } finally {
      if (gen == _generation) _speaking = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    unawaited(stop());
  }
}
