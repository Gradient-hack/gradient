# Gradient voice demo

A local browser voice demo using Pydantic AI and Gemini Live. The browser sends
microphone audio to FastAPI over a WebSocket, Pydantic AI runs Python tools on
the server, and Gemini's audio response streams back over the same connection.
The Google API key remains on the backend.

This repository also contains a separate Flutter proof of concept at
[`apps/gemini_live_flutter`](apps/gemini_live_flutter). Its Firebase setup and
device instructions are in the [Flutter demo README](apps/gemini_live_flutter/README.md).

## Run the HTML demo

Requires [uv](https://docs.astral.sh/uv/) and Python 3.13 or newer.

1. Copy `.env.example` to `.env` if `.env` does not already exist.
2. Set `GOOGLE_API_KEY` in `.env`.
3. Start the server:

   ```bash
   uv run uvicorn main:app --host 127.0.0.1 --port 8000
   ```

4. Open **http://127.0.0.1:8000**, click **Start call**, and allow microphone
   access.
5. Ask “What time is it in Tokyo?” or “What's your refund policy?” to exercise
   the server-side tools.
6. Click **Stop call** to close the WebSocket and release the microphone.

The page starts without a key and shows setup instructions. Configuration is
read for every new call, so saving `.env` is enough; no server restart is
needed. Shell environment variables take precedence over `.env`.

## Configuration

| Variable | Default |
| --- | --- |
| `GOOGLE_API_KEY` | Required to start a Gemini call |
| `GEMINI_REALTIME_MODEL` | `google:gemini-2.5-flash-native-audio-latest` |
| `GEMINI_REALTIME_VOICE` | `Puck` |

Audio is sent to Gemini and Gemini API usage is billed to your Google account.
The refund and return policies are fictional examples. Transcripts and tool
activity appear on the page, while detailed tool execution is logged in the
terminal.

Microphone access requires localhost or HTTPS. This demo has no authentication,
so keep it bound to `127.0.0.1`. Add application authentication and use `wss://`
before exposing the relay beyond a trusted development network.

## WebSocket protocol

The browser connects to `ws://127.0.0.1:8000/gemini/voice`. It sends raw signed
PCM16 little-endian mono microphone frames at 16 kHz and receives PCM16 mono
model audio at 24 kHz. JSON frames carry readiness, transcripts, tool activity,
barge-in output clearing, turn completion, reconnection, and errors.

The setup endpoint is `http://127.0.0.1:8000/gemini/health`. The complete frame
contract is also recorded in
[`FLUTTER_PROXY_INTEGRATION_PROMPT.md`](FLUTTER_PROXY_INTEGRATION_PROMPT.md).

## Files

- `main.py`: shared agent instructions, tools, route setup, and legacy OpenAI
  WebRTC endpoints.
- `gemini_proxy.py`: Pydantic AI Gemini Live WebSocket relay.
- `index.html`: browser microphone capture, PCM playback, status, and
  transcripts.
- `tests/test_gemini_proxy.py`: relay configuration and protocol tests.
- `uv.lock`: pinned Python dependencies, including Pydantic AI 2.46.0.
