# Sidewalk walking podcast demo

A local browser prototype for a continuous, location-aware walking podcast using
Pydantic AI and Gemini Live. The browser sends microphone audio and simulated
location updates to FastAPI over a WebSocket. Pydantic AI runs the route tools
on the server, and Gemini's audio streams back over the same connection. The
Google API key remains on the backend.

## Run the HTML demo

Requires [uv](https://docs.astral.sh/uv/) and Python 3.13 or newer.

1. Copy `.env.example` to `.env` if `.env` does not already exist.
2. Set `GOOGLE_API_KEY` in `.env`.
3. Start the server:

   ```bash
   uv run uvicorn main:app --host 127.0.0.1 --port 8888
   ```

4. Open **http://127.0.0.1:8888**, click **Start live walk**, and allow microphone
   access.
5. The preview starts with a fake 25-minute Chinatown → Soho route. The brief
   shows the time constraint and preferences: Tudor architecture, history, and
   Chinese food. Narration keeps exploring the current place until a location
   update reaches the next stop; speaking interrupts it so you can ask a
   question.
6. Say **“Can we talk about music?”** to exercise the nearby music search and
   route re-ranking. The page also shows the V2 removed/added stops and the
   preference delta.
7. Use **1 · Switch to music**, **2 · Remember mural**, **3 · Simulate wrong
   turn**, and **4 · Find nearby food** under **Preview the story beats** to run
   the deterministic fake events. **Start simulation** sends location updates
   when the WebSocket is live and moves the dot locally when offline.
8. Click **End** to close the WebSocket and release the microphone.

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
The route, points of interest, and stories are fictional prototype data.
Transcripts, podcast state, route diffs, rehearsal decisions, and tool activity
appear on the page, while detailed tool execution is logged in the terminal.

Microphone access requires localhost or HTTPS. This demo has no authentication,
so keep it bound to `127.0.0.1`. Add application authentication and use `wss://`
before exposing the relay beyond a trusted development network.

## WebSocket protocol

The browser connects to `ws://127.0.0.1:8888/gemini/voice`. It sends raw signed
PCM16 little-endian mono microphone frames at 16 kHz and receives PCM16 mono
model audio at 24 kHz. JSON frames carry readiness, transcripts, tool activity,
route updates, podcast state, location progress, barge-in output clearing, turn
completion, reconnection, and errors.

The setup endpoint is `http://127.0.0.1:8888/gemini/health`.

Gemini can call six focused Pydantic AI tools: `plan_walk`, `change_topic`,
`remember_place`, `handle_route_deviation`, `find_nearby_food`, and
`get_walk_status`. Location updates are ordinary WebSocket events rather than
model tool calls, so GPS can update the current stop without spending a model
turn on every fix.

The browser rehearsal controls use fake route data so the complete Chinatown /
Soho conversation can be demonstrated without a key: V1 starts at 25 minutes,
V2 searches nearby for music and counterculture, V3 recalls a mural, V3B asks
whether to take the detour, and V4 adds a food stop. The controls send the
corresponding `demo_theme` preferences when a live WebSocket is open.

## Files

- `main.py`: shared agent instructions, walking tools, route setup, and the
  application entrypoint.
- `gemini_proxy.py`: Pydantic AI Gemini Live WebSocket relay.
- `walk_demo.py`: per-session fake routes, POIs, location progress, and
  location-anchored podcast sequencing.
- `index.html`: browser microphone capture, PCM playback, route UI, simulated
  location, podcast state, and transcripts.
- `tests/test_gemini_proxy.py`: relay configuration and protocol tests.
- `tests/test_walk_demo.py`: route and continuous-podcast state tests.
- `uv.lock`: pinned Python dependencies, including Pydantic AI 2.46.0.
