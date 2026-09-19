import 'dart:async';
import 'dart:io';

import 'package:audio_io/audio_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/device_env.dart';
import '../data/relay_protocol.dart';

enum VoiceCallStatus { idle, connecting, live, stopping, error }

@immutable
class VoiceCallState {
  const VoiceCallState({
    this.status = VoiceCallStatus.idle,
    this.url,
    this.turns = const [],
    this.model,
    this.lastToolEvent,
    this.error,
    this.notice,
    this.muted = false,
    this.holdMicWhileSpeaking = false,
    this.assistantSpeaking = false,
    this.log = const [],
  });

  final VoiceCallStatus status;

  /// Normalised URL of the current/last call, so the screen can show what
  /// was actually dialled.
  final String? url;
  final List<TranscriptTurn> turns;
  final String? model;
  final String? lastToolEvent;
  final String? error;

  /// Non-error caveat about this session (e.g. simulator has no audio).
  final String? notice;
  final bool muted;

  /// Half-duplex: don't send microphone audio while the host's reply is
  /// still playing. Disables barge-in, but stops the relay's VAD from
  /// flushing playback when the speaker leaks into the mic.
  final bool holdMicWhileSpeaking;

  /// True while buffered response audio is still playing (estimated from
  /// the bytes received), cleared early by `clear_output`. Drives the
  /// avatar glow and the half-duplex mic hold.
  final bool assistantSpeaking;

  /// Recent connection events, newest last. Handy on-device debugging.
  final List<String> log;

  bool get isLive => status == VoiceCallStatus.live;
  bool get isBusy =>
      status == VoiceCallStatus.connecting ||
      status == VoiceCallStatus.stopping;

  VoiceCallState copyWith({
    VoiceCallStatus? status,
    String? url,
    List<TranscriptTurn>? turns,
    String? model,
    String? lastToolEvent,
    String? error,
    bool clearError = false,
    String? notice,
    bool? muted,
    bool? holdMicWhileSpeaking,
    bool? assistantSpeaking,
    List<String>? log,
  }) {
    return VoiceCallState(
      status: status ?? this.status,
      url: url ?? this.url,
      turns: turns ?? this.turns,
      model: model ?? this.model,
      lastToolEvent: lastToolEvent ?? this.lastToolEvent,
      error: clearError ? null : (error ?? this.error),
      notice: notice ?? this.notice,
      muted: muted ?? this.muted,
      holdMicWhileSpeaking: holdMicWhileSpeaking ?? this.holdMicWhileSpeaking,
      assistantSpeaking: assistantSpeaking ?? this.assistantSpeaking,
      log: log ?? this.log,
    );
  }
}

/// One live voice call against the Gemini relay: WebSocket for signalling
/// and audio frames, `audio_io` for the microphone and speaker.
///
/// Independent of the walk's narrator (flutter_tts): both want to own the
/// iOS audio session, so the walk controller pauses narration around a call.
class VoiceCallController extends Notifier<VoiceCallState> {
  static const _prefsUrlKey = 'voice_test.relay_url';
  static const _prefsDefaultKey = 'voice_test.relay_url_default';
  static const _connectTimeout = Duration(seconds: 15);
  static const _readyTimeout = Duration(seconds: 20);
  static const _pingInterval = Duration(seconds: 15);
  static const _maxLog = 40;

  /// Bytes per second of relay output audio (PCM16 mono 24 kHz).
  static const _outputBytesPerSecond = kRelayOutputSampleRate * 2;

  /// audio_io's output ring drops whatever doesn't fit. Gemini sends a reply
  /// in bursts well ahead of real time, so the ring must hold a whole reply,
  /// not a jitter budget. 20 s ≈ 7.7 MB of Doubles at the 48 kHz contract rate.
  static const _outputBufferSeconds = 20.0;

  /// audio_io enables Apple's voice-processing unit unconditionally, which
  /// raises an uncatchable ObjC exception on the iOS simulator (input format
  /// reports 0 Hz) and aborts the whole app. Resolved via [DeviceEnv] at the
  /// start of each call; on the simulator we run signalling-only.
  bool _isSimulator = false;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _pingTimer;
  Timer? _readyTimer;
  Timer? _speakingTimer;

  /// When the audio queued so far will have finished playing.
  DateTime? _playbackEnd;
  bool _audioStarted = false;
  bool _disposed = false;

  /// Bumped on every stop so stale callbacks bail out.
  int _generation = 0;
  final TranscriptLog _transcript = TranscriptLog();

  @override
  VoiceCallState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      unawaited(_teardown(notifyServer: true));
    });
    return const VoiceCallState();
  }

  // ── URL persistence ──────────────────────────────────────────────────────

  /// Last URL used, else the build-time default. The tunnel host changes on
  /// every backend restart, so remembering it saves a rebuild. A new
  /// build-time default (i.e. a rebuild with a fresh `--dart-define`) beats
  /// the remembered URL, which was saved against the previous default.
  Future<String> loadRelayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsUrlKey);
    final savedDefault = prefs.getString(_prefsDefaultKey);
    if (saved == null || savedDefault != kDefaultRelayUrl) {
      return kDefaultRelayUrl;
    }
    return saved;
  }

  Future<void> _rememberRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUrlKey, url);
    await prefs.setString(_prefsDefaultKey, kDefaultRelayUrl);
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> start(String url) async {
    if (state.isBusy || state.isLive) return;
    final gen = ++_generation;
    _transcript.clear();
    url = normalizeRelayUrl(url);
    state = VoiceCallState(status: VoiceCallStatus.connecting, url: url);
    _log('Connecting to $url');

    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'ws' && uri.scheme != 'wss') {
        throw const FormatException('URL must start with ws:// or wss://');
      }
      unawaited(_rememberRelayUrl(url));

      _isSimulator = await DeviceEnv.isSimulator();
      if (gen != _generation) return;
      if (_isSimulator) {
        _set(
          state.copyWith(
            notice:
                'iOS simulator: connection only, no audio '
                '(audio_io voice processing aborts on the simulator). Use a real iPhone.',
          ),
        );
        _log('Simulator detected: audio disabled.');
      } else {
        final granted = (await Permission.microphone.request()).isGranted;
        if (gen != _generation) return;
        if (!granted) {
          throw StateError('Microphone access is required for a live call.');
        }
      }

      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(_connectTimeout);
      if (gen != _generation) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _log('Socket open, waiting for ready…');

      _socketSub = socket.listen(
        (data) => _onFrame(data, gen),
        onError: (Object e, StackTrace _) => _fail('Connection error: $e', gen),
        onDone: () {
          if (gen != _generation) return;
          if (state.status == VoiceCallStatus.connecting) {
            _fail('The relay closed the connection before it was ready.', gen);
          } else if (state.status == VoiceCallStatus.live) {
            _log('Connection closed by relay.');
            unawaited(stop());
          }
        },
      );
      _readyTimer = Timer(_readyTimeout, () {
        if (gen == _generation && state.status == VoiceCallStatus.connecting) {
          _fail('Timed out waiting for the relay to become ready.', gen);
        }
      });
    } catch (e) {
      if (gen != _generation) return;
      await _fail(_describe(e), gen);
    }
  }

  Future<void> stop() async {
    if (state.status == VoiceCallStatus.idle ||
        state.status == VoiceCallStatus.stopping) {
      return;
    }
    _generation++;
    _set(
      state.copyWith(
        status: VoiceCallStatus.stopping,
        assistantSpeaking: false,
      ),
    );
    await _teardown(notifyServer: true);
    _set(state.copyWith(status: VoiceCallStatus.idle, muted: false));
    _log('Call ended.');
  }

  void toggleMute() {
    if (!state.isLive) return;
    _set(state.copyWith(muted: !state.muted));
  }

  void toggleHoldMic() {
    _set(state.copyWith(holdMicWhileSpeaking: !state.holdMicWhileSpeaking));
    _log(
      'Hold mic while host speaks: ${state.holdMicWhileSpeaking ? 'on' : 'off'}',
    );
  }

  /// Whether microphone frames should go up the wire right now.
  bool get _micOpen =>
      !state.muted && !(state.holdMicWhileSpeaking && state.assistantSpeaking);

  // ── Frames ───────────────────────────────────────────────────────────────

  void _onFrame(dynamic data, int gen) {
    if (gen != _generation) return;
    if (data is String) {
      RelayEvent event;
      try {
        event = parseRelayEvent(data);
      } on FormatException catch (e) {
        _log('Ignored bad frame: ${e.message}');
        return;
      }
      unawaited(_onEvent(event, gen));
      return;
    }
    if (data is List<int>) {
      if (!_audioStarted) return; // Never before `ready`.
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      if (bytes.length.isOdd) {
        _log('Dropped odd-length PCM frame (${bytes.length} bytes).');
        return;
      }
      if (!_isSimulator) AudioIo.instance.outputBytes.add(bytes);
      _queuedPlayback(bytes.length);
    }
  }

  /// Extends the estimated playback end by this chunk's duration and keeps
  /// [VoiceCallState.assistantSpeaking] true until then. `turn_complete`
  /// arrives when generation ends, which is well before playback ends.
  void _queuedPlayback(int bytes) {
    final now = DateTime.now();
    final base = (_playbackEnd == null || _playbackEnd!.isBefore(now))
        ? now
        : _playbackEnd!;
    _playbackEnd = base.add(
      Duration(microseconds: bytes * 1000000 ~/ _outputBytesPerSecond),
    );
    if (!state.assistantSpeaking) _set(state.copyWith(assistantSpeaking: true));
    _speakingTimer?.cancel();
    // Small tail so the mic doesn't reopen on the last syllable's echo.
    _speakingTimer = Timer(
      _playbackEnd!.difference(now) + const Duration(milliseconds: 250),
      () {
        if (state.assistantSpeaking) {
          _set(state.copyWith(assistantSpeaking: false));
        }
      },
    );
  }

  void _playbackCleared() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _playbackEnd = null;
    if (state.assistantSpeaking) _set(state.copyWith(assistantSpeaking: false));
  }

  Future<void> _onEvent(RelayEvent event, int gen) async {
    switch (event) {
      case RelayReady():
        final why = event.incompatibility;
        if (why != null) {
          await _fail('Relay audio format not supported ($why).', gen);
          return;
        }
        _readyTimer?.cancel();
        await _startAudio(gen);
        if (gen != _generation) return;
        _set(
          state.copyWith(
            status: VoiceCallStatus.live,
            model: event.model,
            clearError: true,
          ),
        );
        _log('Live: ${event.model}');
      case RelayTranscript():
        _transcript.apply(event);
        _set(state.copyWith(turns: _transcript.turns));
      case RelayToolCall():
        _set(state.copyWith(lastToolEvent: 'Calling ${event.name}…'));
        _log('Tool call: ${event.name}');
      case RelayToolResult():
        _set(state.copyWith(lastToolEvent: 'Completed ${event.name}.'));
        _log('Tool result: ${event.name}');
      case RelayClearOutput():
        if (_audioStarted) await AudioIo.instance.clearOutput();
        _playbackCleared();
        _log(
          'Output cleared${event.reason != null ? ' (${event.reason})' : ''}.',
        );
      case RelayTurnComplete():
        // Playback keeps going from the buffer; assistantSpeaking follows it.
        _log('Turn complete.');
      case RelayReconnected():
        _log(
          'Relay reconnected${event.stateRestored ? ' with state restored' : ''}.',
        );
      case RelayPong():
        break;
      case RelayError():
        _log(
          'Error${event.code != null ? ' [${event.code}]' : ''}: ${event.message}',
        );
        if (event.fatal) {
          await _fail(event.message, gen);
        } else {
          _set(state.copyWith(error: event.message));
        }
      case RelayUnknown():
        _log('Unknown relay event: ${event.type}');
    }
  }

  // ── Audio ────────────────────────────────────────────────────────────────

  Future<void> _startAudio(int gen) async {
    if (_isSimulator) {
      // Keep the keepalive so the relay session stays up for the smoke test.
      _pingTimer = Timer.periodic(_pingInterval, (_) {
        final s = _socket;
        if (gen == _generation && s != null && s.readyState == WebSocket.open) {
          s.add(encodePing());
        }
      });
      return;
    }
    await AudioIo.instance.startWith(
      const AudioIoConfig(
        format: AudioIoFormat.pcm16,
        inputSampleRate: AudioIoSampleRate.rate16000,
        outputSampleRate: AudioIoSampleRate.rate24000,
        latency: AudioIoLatency.Realtime,
        outputBufferDuration: _outputBufferSeconds,
      ),
    );
    _audioStarted = true;
    if (gen != _generation) return;

    _micSub = AudioIo.instance.inputBytes.listen((bytes) {
      final s = _socket;
      if (gen != _generation || s == null || !_micOpen) return;
      if (s.readyState != WebSocket.open) return;
      s.add(bytes);
    }, onError: (Object e, StackTrace _) => _fail('Microphone error: $e', gen));
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      final s = _socket;
      if (gen == _generation && s != null && s.readyState == WebSocket.open) {
        s.add(encodePing());
      }
    });
  }

  // ── Teardown ─────────────────────────────────────────────────────────────

  Future<void> _fail(String message, int gen) async {
    if (gen != _generation) return;
    _generation++;
    await _teardown(notifyServer: false);
    _set(
      state.copyWith(
        status: VoiceCallStatus.error,
        error: message,
        assistantSpeaking: false,
      ),
    );
    _log('Failed: $message');
  }

  /// Idempotent: safe to call from stop, failure and dispose in any order.
  Future<void> _teardown({required bool notifyServer}) async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _readyTimer?.cancel();
    _readyTimer = null;
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _playbackEnd = null;

    await _micSub?.cancel();
    _micSub = null;

    final socket = _socket;
    _socket = null;
    await _socketSub?.cancel();
    _socketSub = null;
    if (socket != null) {
      try {
        if (notifyServer && socket.readyState == WebSocket.open) {
          socket.add(encodeClose());
        }
        await socket.close(WebSocketStatus.normalClosure, 'Client stopped');
      } catch (_) {}
    }

    if (_audioStarted) {
      _audioStarted = false;
      try {
        await AudioIo.instance.clearOutput();
        await AudioIo.instance.stop();
      } catch (e) {
        debugPrint('audio_io stop failed: $e');
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _set(VoiceCallState s) {
    if (!_disposed) state = s;
  }

  void _log(String line) {
    debugPrint('[VoiceCall] $line');
    if (_disposed) return;
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    final next = [...state.log, '$stamp  $line'];
    if (next.length > _maxLog) next.removeRange(0, next.length - _maxLog);
    state = state.copyWith(log: next);
  }

  String _describe(Object e) {
    if (e is TimeoutException) return 'Could not reach the relay (timed out).';
    if (e is SocketException) return 'Could not reach the relay: ${e.message}';
    if (e is WebSocketException) {
      return 'WebSocket handshake failed: ${e.message}';
    }
    if (e is AudioIoException) return 'Audio error: ${e.message}';
    return e.toString().replaceFirst(
      RegExp(r'^(Bad state|Exception|FormatException): '),
      '',
    );
  }
}

/// App-wide (kept alive): the walk and the dev screen share one call.
/// Screens that start a call must stop it when they go away.
final voiceCallProvider = NotifierProvider<VoiceCallController, VoiceCallState>(
  VoiceCallController.new,
);
