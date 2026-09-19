import 'dart:convert';

/// Wire contract of the team's Gemini relay (`gemini_proxy.py`,
/// `GET websocket /gemini/voice`, protocol version 1).
///
/// Binary frames carry raw PCM16 little-endian mono audio: 16 kHz up
/// (microphone), 24 kHz down (model). Text frames carry JSON events, which
/// this file parses. The backend owns the contract; if something here turns
/// out to be ambiguous, keep compatibility and report it rather than changing
/// the protocol.
const kRelayProtocolVersion = 1;
const kRelayInputSampleRate = 16000;
const kRelayOutputSampleRate = 24000;

/// Default relay URL; override per build with
/// `--dart-define=PYDANTIC_WS_URL=wss://<host>/gemini/voice`.
const kDefaultRelayUrl = String.fromEnvironment(
  'PYDANTIC_WS_URL',
  defaultValue: 'ws://127.0.0.1:8000/gemini/voice',
);

/// Turns whatever gets pasted into the relay field into a usable socket URL:
///
/// - `https://host/` or `host` → `wss://host/gemini/voice`
/// - `http://` / `ws://` to a non-local host → `wss://` (Cloudflare tunnels
///   are TLS-only; a plain `ws://` is redirected and the upgrade fails)
/// - missing or `/` path → `/gemini/voice`
///
/// Local hosts (localhost, 127.x, 10.x, 192.168.x) keep plain `ws://`.
String normalizeRelayUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return kDefaultRelayUrl;
  // Schemeless: start plain; non-local hosts are upgraded to wss below.
  if (!s.contains('://')) s = 'ws://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return s;

  final host = uri.host;
  final local =
      host == 'localhost' ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.');

  var scheme = switch (uri.scheme) {
    'https' => 'wss',
    'http' => 'ws',
    final other => other,
  };
  if (!local && scheme == 'ws') scheme = 'wss';

  final path = (uri.path.isEmpty || uri.path == '/')
      ? '/gemini/voice'
      : uri.path;
  // replace(fragment: null) keeps an empty '#'; removeFragment drops it.
  return uri.replace(scheme: scheme, path: path).removeFragment().toString();
}

// ── Server → client ────────────────────────────────────────────────────────

sealed class RelayEvent {
  const RelayEvent();
}

class RelayReady extends RelayEvent {
  const RelayReady({
    required this.protocol,
    required this.model,
    required this.inputSampleRate,
    required this.outputSampleRate,
    required this.encoding,
    required this.channels,
  });

  final int protocol;
  final String model;
  final int inputSampleRate;
  final int outputSampleRate;
  final String encoding;
  final int channels;

  /// Null when the relay speaks the audio format we implement; otherwise a
  /// human-readable reason to refuse the call.
  String? get incompatibility {
    if (protocol != kRelayProtocolVersion) return 'protocol v$protocol';
    if (encoding != 'pcm16le') return 'encoding $encoding';
    if (channels != 1) return '$channels channels';
    if (inputSampleRate != kRelayInputSampleRate) {
      return 'input ${inputSampleRate}Hz';
    }
    if (outputSampleRate != kRelayOutputSampleRate) {
      return 'output ${outputSampleRate}Hz';
    }
    return null;
  }
}

class RelayTranscript extends RelayEvent {
  const RelayTranscript({
    required this.index,
    required this.speaker,
    required this.text,
    this.delta,
  });

  final int index;

  /// `user` or `assistant`.
  final String speaker;

  /// The complete current transcript for this index (not a delta).
  final String text;
  final String? delta;
}

class RelayToolCall extends RelayEvent {
  const RelayToolCall({required this.name, this.callId});
  final String name;
  final String? callId;
}

class RelayToolResult extends RelayEvent {
  const RelayToolResult({required this.name, this.callId});
  final String name;
  final String? callId;
}

class RelayClearOutput extends RelayEvent {
  const RelayClearOutput({this.reason});
  final String? reason;
}

class RelayTurnComplete extends RelayEvent {
  const RelayTurnComplete();
}

class RelayReconnected extends RelayEvent {
  const RelayReconnected({required this.stateRestored});
  final bool stateRestored;
}

class RelayPong extends RelayEvent {
  const RelayPong();
}

class RelayError extends RelayEvent {
  const RelayError({required this.message, this.code, this.fatal = false});
  final String message;
  final String? code;
  final bool fatal;
}

/// An event type this client doesn't know. Logged, otherwise ignored.
class RelayUnknown extends RelayEvent {
  const RelayUnknown(this.type);
  final String type;
}

/// Parses one text frame. Throws [FormatException] if it isn't a JSON object
/// with a string `type`.
RelayEvent parseRelayEvent(String frame) {
  final Object? decoded;
  try {
    decoded = jsonDecode(frame);
  } on FormatException {
    throw const FormatException('Relay sent a text frame that is not JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Relay event is not a JSON object.');
  }
  // Local copy so the helper closures below see the promoted type.
  final Map<String, dynamic> map = decoded;
  final type = map['type'];
  if (type is! String) {
    throw const FormatException('Relay event has no string "type".');
  }

  int intOr(String key, int fallback) {
    final v = map[key];
    return v is int ? v : (v is num ? v.toInt() : fallback);
  }

  String strOr(String key, String fallback) {
    final v = map[key];
    return v is String ? v : fallback;
  }

  String? strOrNull(String key) {
    final v = map[key];
    return v is String ? v : null;
  }

  switch (type) {
    case 'ready':
      return RelayReady(
        protocol: intOr('protocol', -1),
        model: strOr('model', 'unknown'),
        inputSampleRate: intOr('input_sample_rate', -1),
        outputSampleRate: intOr('output_sample_rate', -1),
        encoding: strOr('encoding', ''),
        channels: intOr('channels', -1),
      );
    case 'transcript':
      final index = map['index'];
      final speaker = map['speaker'];
      if (index is! int || speaker is! String) {
        throw const FormatException(
          'transcript needs int "index" and string "speaker".',
        );
      }
      return RelayTranscript(
        index: index,
        speaker: speaker,
        text: strOr('text', ''),
        delta: strOrNull('delta'),
      );
    case 'tool_call':
      return RelayToolCall(
        name: strOr('name', 'tool'),
        callId: strOrNull('call_id'),
      );
    case 'tool_result':
      return RelayToolResult(
        name: strOr('name', 'tool'),
        callId: strOrNull('call_id'),
      );
    case 'clear_output':
      return RelayClearOutput(reason: strOrNull('reason'));
    case 'turn_complete':
      return const RelayTurnComplete();
    case 'reconnected':
      return RelayReconnected(stateRestored: map['state_restored'] == true);
    case 'pong':
      return const RelayPong();
    case 'error':
      return RelayError(
        message: strOr('message', 'The relay reported an error.'),
        code: strOrNull('code'),
        fatal: map['fatal'] == true,
      );
    default:
      return RelayUnknown(type);
  }
}

// ── Client → server ────────────────────────────────────────────────────────

String encodeClose() => jsonEncode({'type': 'close'});
String encodePing() => jsonEncode({'type': 'ping'});

/// Explicit barge-in: [playedBytes] is the cumulative number of raw 24 kHz
/// PCM output bytes actually played during this connection.
String encodeInterrupt(int playedBytes) {
  if (playedBytes < 0) throw ArgumentError.value(playedBytes, 'playedBytes');
  return jsonEncode({'type': 'interrupt', 'played_bytes': playedBytes});
}

// ── Transcript bookkeeping ─────────────────────────────────────────────────

class TranscriptTurn {
  const TranscriptTurn({required this.speaker, required this.text});
  final String speaker;
  final String text;

  bool get isUser => speaker == 'user';
}

/// Transcript entries keyed by the relay's `index`. Each `transcript` event
/// replaces the entry at its index (the text is complete, not a delta).
///
/// [turns] merges adjacent entries from the same speaker, because Gemini can
/// finalise one utterance as several transcript parts.
class TranscriptLog {
  final Map<int, TranscriptTurn> _byIndex = {};

  bool get isEmpty => _byIndex.isEmpty;

  void apply(RelayTranscript t) {
    _byIndex[t.index] = TranscriptTurn(speaker: t.speaker, text: t.text);
  }

  void clear() => _byIndex.clear();

  List<TranscriptTurn> get turns {
    final keys = _byIndex.keys.toList()..sort();
    final out = <TranscriptTurn>[];
    for (final k in keys) {
      final t = _byIndex[k]!;
      if (out.isNotEmpty && out.last.speaker == t.speaker) {
        out[out.length - 1] = TranscriptTurn(
          speaker: t.speaker,
          text: out.last.text + t.text,
        );
      } else {
        out.add(t);
      }
    }
    return out;
  }
}
