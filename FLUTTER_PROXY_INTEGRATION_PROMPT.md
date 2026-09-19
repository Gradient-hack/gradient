# Prompt: add a Pydantic voice test mode to the Flutter app

Work in `apps/gemini_live_flutter` and add a small test-only voice mode that
lets us manually exercise the Pydantic AI Gemini relay at `/gemini/voice`.

Keep the existing Firebase Gemini Live experience unchanged. This is a test
harness inside the current app, not a productized second mode or a broad UI
refactor. Add one small secondary entry point labelled **Test Pydantic voice**
(a button, menu item, or lightweight test tab is fine) that opens the relay
voice screen.

The backend is being developed in parallel. Do not edit `main.py`,
`gemini_proxy.py`, `pyproject.toml`, or backend tests. Preserve other
developers' changes in the Flutter app.

## Test screen

Reuse the current app's `audio_io` capture and playback setup where practical.
The screen only needs:

- connection status;
- a start/end call control and mute control;
- the live user and assistant transcript;
- the latest tool call/result status;
- a visible error with a retry path.

Only one voice session may use the microphone or speaker at a time. Stop and
dispose the test session when leaving the screen or when the app becomes
inactive.

The proxy test must work without Firebase configuration. Read its URL from:

```dart
const String.fromEnvironment(
  'PYDANTIC_WS_URL',
  defaultValue: 'ws://127.0.0.1:8000/gemini/voice',
)
```

For an Android Emulator, use
`--dart-define=PYDANTIC_WS_URL=ws://10.0.2.2:8000/gemini/voice`. A physical
device needs the Mac's LAN address, or a deployed `wss://` endpoint.

## WebSocket protocol

The endpoint is `GET websocket /gemini/voice`, protocol version 1.

Client to server:

- Binary frames: raw signed PCM16 little-endian, mono, 16 kHz microphone audio.
- `{"type":"ping"}`: optional keepalive; the server replies with `pong`.
- `{"type":"interrupt","played_bytes":1234}`: optional explicit barge-in.
  `played_bytes` is the cumulative number of raw 24 kHz PCM output bytes that
  the device has actually played during this connection.
- `{"type":"close"}`: cleanly end the relay before closing the socket.

Server to client:

- Binary frames: raw signed PCM16 little-endian, mono, 24 kHz model audio.
- `ready`: includes `protocol`, `model`, `input_sample_rate`,
  `output_sample_rate`, `encoding`, and `channels`. Do not stream microphone
  audio before this event.
- `transcript`: includes `index`, `speaker` (`user` or `assistant`), `text`
  (the complete current transcript), and `delta`. Store entries by `index` and
  render `text`; do not concatenate `delta`.
- `tool_call`: includes `name` and `call_id`.
- `tool_result`: includes `name` and `call_id`.
- `clear_output`: immediately call `AudioIo.clearOutput()` and reset playback
  accounting for the interrupted response.
- `turn_complete`: the model and its tool work finished the turn.
- `reconnected`: includes `state_restored`.
- `pong`: keepalive response.
- `error`: includes `code`, `message`, and `fatal`. Show the message; close and
  offer retry when `fatal` is true.

Binary and text frames can arrive interleaved. Serialize client writes and make
stop/cleanup idempotent.

## Scope and validation

- Keep the proxy code isolated under `lib/proxy/` or an equivalently small
  test-only area. Keep Firebase types out of it.
- Avoid changing the existing Firebase controller unless a very small shared
  audio extraction is necessary.
- Add focused tests for protocol parsing, transcript replacement by index,
  readiness, fatal errors, and repeated stop.
- Add brief Flutter README instructions for launching this test mode.
- Run `dart format`, `flutter analyze`, and `flutter test`.
- Report physical microphone/speaker testing separately; do not claim it from
  unit or widget tests.

The backend developer owns the wire contract above. If implementation reveals
an ambiguity, preserve compatibility and report it instead of changing the
protocol.
