import 'dart:async';

import 'package:audio_io/audio_io.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';

enum LiveConversationStatus {
  setupRequired,
  idle,
  requestingPermission,
  connecting,
  live,
  stopping,
  error,
}

class TranscriptEntry {
  const TranscriptEntry({required this.speaker, required this.text});

  final String speaker;
  final String text;
}

typedef LiveSessionConnector = Future<LiveSession> Function();
typedef MicrophonePermissionRequest = Future<bool> Function();

class LiveConversationController extends ChangeNotifier {
  static const _modelName = String.fromEnvironment(
    'GEMINI_LIVE_MODEL',
    defaultValue: 'gemini-2.5-flash-native-audio-preview-12-2025',
  );

  LiveConversationController({
    bool configured = true,
    LiveSessionConnector? connect,
    AudioIo? audio,
    MicrophonePermissionRequest? requestMicrophonePermission,
  }) : _configured = configured,
       _connectOverride = connect,
       _audio = audio ?? AudioIo.instance,
       _requestMicrophonePermission =
           requestMicrophonePermission ?? _requestPermission {
    _status = configured
        ? LiveConversationStatus.idle
        : LiveConversationStatus.setupRequired;
  }

  final bool _configured;
  final LiveSessionConnector? _connectOverride;
  final AudioIo _audio;
  final MicrophonePermissionRequest _requestMicrophonePermission;

  LiveConversationStatus _status = LiveConversationStatus.idle;
  final List<TranscriptEntry> _transcripts = [];
  String? _errorMessage;
  String? _lastToolEvent;
  bool _isMuted = false;
  bool _audioStarted = false;
  LiveSession? _session;
  StreamSubscription<Uint8List>? _microphoneSubscription;
  StreamSubscription<LiveServerResponse>? _responseSubscription;
  int _generation = 0;
  bool _disposed = false;

  LiveConversationStatus get status => _status;
  List<TranscriptEntry> get transcripts => List.unmodifiable(_transcripts);
  String? get errorMessage => _errorMessage;
  String? get lastToolEvent => _lastToolEvent;
  bool get isMuted => _isMuted;
  bool get isLive => _status == LiveConversationStatus.live;

  Future<void> start() async {
    if (_status == LiveConversationStatus.setupRequired ||
        _status == LiveConversationStatus.requestingPermission ||
        _status == LiveConversationStatus.connecting ||
        _status == LiveConversationStatus.live) {
      return;
    }

    if (!_configured) {
      _setStatus(LiveConversationStatus.setupRequired);
      return;
    }

    _errorMessage = null;
    _lastToolEvent = null;
    _transcripts.clear();
    _setStatus(LiveConversationStatus.requestingPermission);

    try {
      if (!await _requestMicrophonePermission()) {
        throw StateError('Microphone access is required for a live call.');
      }

      _setStatus(LiveConversationStatus.connecting);
      final session = await _connect();
      _session = session;
      final generation = ++_generation;

      await _audio.startWith(
        const AudioIoConfig(
          format: AudioIoFormat.pcm16,
          inputSampleRate: AudioIoSampleRate.rate16000,
          outputSampleRate: AudioIoSampleRate.rate24000,
          latency: AudioIoLatency.Realtime,
          outputBufferDuration: 0.3,
        ),
      );
      _audioStarted = true;

      _microphoneSubscription = _audio.inputBytes.listen(
        (bytes) => unawaited(_sendAudio(bytes, session, generation)),
        onError: (Object error, StackTrace stack) {
          unawaited(_handleStreamError(error, generation));
        },
      );
      _responseSubscription = session.receive().listen(
        (response) =>
            unawaited(_handleResponseSafely(response, session, generation)),
        onError: (Object error, StackTrace stack) {
          if (generation == _generation &&
              _status != LiveConversationStatus.stopping) {
            unawaited(_handleStreamError(error, generation));
          }
        },
        onDone: () {
          if (generation == _generation &&
              _status == LiveConversationStatus.live) {
            unawaited(stop());
          }
        },
      );
      _setStatus(LiveConversationStatus.live);
    } catch (error) {
      try {
        await _cleanup();
      } catch (_) {
        // Preserve the original permission or connection failure.
      }
      _setError(error);
    }
  }

  Future<void> stop() async {
    if (_status == LiveConversationStatus.idle ||
        _status == LiveConversationStatus.setupRequired ||
        _status == LiveConversationStatus.stopping) {
      return;
    }

    _setStatus(LiveConversationStatus.stopping);
    ++_generation;
    try {
      await _cleanup();
    } catch (error) {
      if (!_disposed) _setError(error);
      return;
    }
    if (!_disposed) {
      _setStatus(LiveConversationStatus.idle);
    }
  }

  Future<void> toggleMute() async {
    if (!isLive) return;
    _isMuted = !_isMuted;
    _notify();
  }

  Future<LiveSession> _connect() async {
    if (_connectOverride != null) return _connectOverride();

    if (!DemoFirebaseOptions.isConfigured) {
      throw StateError(
        'Firebase is not configured. Supply the FIREBASE_* dart-defines.',
      );
    }

    try {
      Firebase.app();
    } on FirebaseException {
      await Firebase.initializeApp(
        options: DemoFirebaseOptions.currentPlatform,
      );
    }

    final timeTool = FunctionDeclaration(
      'get_current_time',
      'Get the current time for a city or timezone.',
      parameters: {
        'city': Schema.enumString(
          enumValues: const ['local', 'London', 'Tokyo', 'New York'],
          description: 'One of local, London, Tokyo, or New York.',
        ),
      },
    );
    final model = FirebaseAI.googleAI().liveGenerativeModel(
      model: _modelName,
      liveGenerationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModalities.audio],
        inputAudioTranscription: AudioTranscriptionConfig(),
        outputAudioTranscription: AudioTranscriptionConfig(),
        realtimeInputConfig: RealtimeInputConfig(
          activityHandling: ActivityHandling.interrupt,
        ),
      ),
      systemInstruction: Content.system(
        'You are a concise, warm voice assistant. Use get_current_time '
        'when asked for the time. The tool returns UTC and an IANA timezone; '
        'convert it to local time with the correct daylight-saving offset. '
        'Keep spoken answers short.',
      ),
      tools: [
        Tool.functionDeclarations([timeTool]),
      ],
    );
    return model.connect();
  }

  Future<void> _handleResponse(
    LiveServerResponse response,
    LiveSession session,
  ) async {
    final message = response.message;
    if (message case final LiveServerContent content) {
      for (final part in content.modelTurn?.parts ?? const <Part>[]) {
        if (part case final InlineDataPart audioPart
            when audioPart.mimeType.startsWith('audio/pcm')) {
          _audio.outputBytes.add(audioPart.bytes);
        }
      }
      final input = content.inputTranscription?.text;
      if (input != null && input.trim().isNotEmpty) {
        _upsertTranscript('You', input);
      }
      final output = content.outputTranscription?.text;
      if (output != null && output.trim().isNotEmpty) {
        _upsertTranscript('Gemini', output);
      }
      if (content.interrupted == true) {
        await _audio.clearOutput();
      }
      return;
    }

    if (message case final LiveServerToolCall toolCall) {
      final responses = <FunctionResponse>[];
      for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
        final result = _executeTool(call.name, call.args);
        _lastToolEvent = 'get_current_time(${call.args['city'] ?? 'local'})';
        _notify();
        responses.add(FunctionResponse(call.name, result, id: call.id));
      }
      if (responses.isNotEmpty) {
        await session.sendToolResponse(responses);
      }
    }
  }

  Future<void> _sendAudio(
    Uint8List bytes,
    LiveSession session,
    int generation,
  ) async {
    if (generation != _generation || _isMuted || _session != session) return;

    try {
      await session.sendAudioRealtime(
        InlineDataPart('audio/pcm;rate=16000', bytes),
      );
    } catch (error) {
      await _handleStreamError(error, generation);
    }
  }

  Future<void> _handleResponseSafely(
    LiveServerResponse response,
    LiveSession session,
    int generation,
  ) async {
    if (generation != _generation || _session != session) return;

    try {
      await _handleResponse(response, session);
    } catch (error) {
      await _handleStreamError(error, generation);
    }
  }

  Map<String, Object?> _executeTool(String name, Map<String, Object?> args) {
    if (name != 'get_current_time') {
      return {'error': 'Unknown tool: $name'};
    }

    final city = (args['city'] ?? 'local').toString().trim();
    final now = DateTime.now().toUtc();
    final normalized = city.toLowerCase();
    final (label, zone) = switch (normalized) {
      'london' || 'uk' => ('London', 'Europe/London'),
      'tokyo' || 'japan' => ('Tokyo', 'Asia/Tokyo'),
      'new york' || 'new_york' || 'nyc' => ('New York', 'America/New_York'),
      _ => ('Local', DateTime.now().timeZoneName),
    };

    return {
      'city': label,
      'timezone': zone,
      'utcTime': now.toIso8601String(),
      if (normalized == 'local') ...{
        'localTime': DateTime.now().toIso8601String(),
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    };
  }

  Future<void> _handleStreamError(Object error, int generation) async {
    if (generation != _generation ||
        _disposed ||
        _status == LiveConversationStatus.stopping ||
        _status == LiveConversationStatus.error) {
      return;
    }

    final errorGeneration = ++_generation;
    try {
      await _cleanup();
    } catch (_) {
      // The stream error is the useful failure to surface.
    }
    if (errorGeneration == _generation && !_disposed) {
      _setError(error);
    }
  }

  void _upsertTranscript(String speaker, String text) {
    if (_transcripts.isNotEmpty && _transcripts.last.speaker == speaker) {
      _transcripts[_transcripts.length - 1] = TranscriptEntry(
        speaker: speaker,
        text: text,
      );
    } else {
      _transcripts.add(TranscriptEntry(speaker: speaker, text: text));
    }
    _notify();
  }

  Future<void> _cleanup() async {
    Object? cleanupError;
    try {
      await _microphoneSubscription?.cancel();
    } catch (error) {
      cleanupError ??= error;
    } finally {
      _microphoneSubscription = null;
    }
    try {
      await _responseSubscription?.cancel();
    } catch (error) {
      cleanupError ??= error;
    } finally {
      _responseSubscription = null;
    }
    final session = _session;
    _session = null;
    try {
      if (_audioStarted) {
        await _audio.stop();
      }
    } catch (error) {
      cleanupError ??= error;
    } finally {
      _audioStarted = false;
    }
    try {
      await session?.close();
    } catch (error) {
      cleanupError ??= error;
    }
    _isMuted = false;
    if (cleanupError != null) throw cleanupError;
  }

  void _setStatus(LiveConversationStatus value) {
    _status = value;
    _notify();
  }

  void _setError(Object error) {
    _errorMessage = error.toString().replaceFirst('Exception: ', '');
    _status = LiveConversationStatus.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_cleanup());
    super.dispose();
  }

  static Future<bool> _requestPermission() async =>
      (await Permission.microphone.request()).isGranted;
}
