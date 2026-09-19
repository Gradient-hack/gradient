# Gradient web prototype and realtime backend

This directory contains both the horizontal browser storyboard and the backend
shared by the web and Flutter clients. FastAPI serves the prototype, Pydantic AI
defines the walking tools, and Gemini Live provides the realtime conversation.
The Google API key stays on the server.

For the complete system overview, start with the [repository README](../README.md).

## Run locally

Requires [uv](https://docs.astral.sh/uv/) and Python 3.13 or newer.

```sh
cp .env.example .env
# Add GOOGLE_API_KEY to .env
uv run uvicorn main:app --host 127.0.0.1 --port 8888
```

Open <http://127.0.0.1:8888>. Microphone access works on localhost. The page
reads configuration for each new call, so saving `.env` is enough; shell
environment variables take precedence.

The storyboard follows this sequence:

```text
Home -> Generate -> Start podcast -> Reroute note -> Photo -> End
```

The visual flow and fake controls work without a key. With a live connection,
the browser sends microphone audio and structured demo events to the backend.
Use the wrong-location button below the podcast phone to send a
`route_deviation`; the committed route appears inline on the podcast stage so
the conversation does not jump to a separate screen.

## Realtime architecture

The browser or Flutter app connects to `/gemini/voice`. The server creates two
pieces of state for that socket:

- a Pydantic AI Gemini Live session for audio, transcripts, interruptions, and
  model tool calls;
- a `WalkSessionDeps` instance for the current route, location, preferences,
  narrated places, and route version.

Binary frames carry signed PCM16 little-endian mono audio: 16 kHz from the
microphone and 24 kHz from the model. Text frames carry JSON control and state
events. The health endpoint is `/gemini/health`.

The client can send:

| Event | Purpose |
| --- | --- |
| `ping`, `close` | Connection lifecycle. |
| `interrupt` | Stop the current model output using the number of bytes already played. |
| `location_update` | Record an ordered GPS fix and advance location-anchored narration. |
| `route_deviation` | Ask the route service to reroute from an app-detected off-route position. |
| `demo_plan`, `demo_theme` | Drive deterministic rehearsal states in the browser. |

The server emits readiness, transcripts, tool calls and results, route and
podcast state, location progress, output clearing, turn completion,
reconnection, acknowledgements, and errors.

Location events are intentionally separate from model tools. The client can
send frequent GPS updates without creating a model turn. A deviation event is
validated against the current route version, committed to the session, emitted
to the UI, and queued for Gemini to explain when it can speak without cutting
off an active turn.

## Agent tools

Gemini can call five Pydantic AI tools:

| Tool | Responsibility |
| --- | --- |
| `plan_walk` | Build the initial timed route. |
| `change_topic` | Update interests and rerank nearby places, including the music use case. |
| `remember_place` | Save a reaction and use it to adapt later stories. |
| `find_nearby_food` | Compare and insert a nearby food stop. |
| `get_walk_status` | Read the latest route and location state. |

The route, points of interest, and stories are fictional prototype data around
Chinatown and Soho. Detailed tool execution is logged in the server terminal.

## Configuration

| Variable | Default |
| --- | --- |
| `GOOGLE_API_KEY` | Required to start a Gemini call |
| `GEMINI_REALTIME_MODEL` | `google:gemini-2.5-flash-native-audio-latest` |
| `GEMINI_REALTIME_VOICE` | `Puck` |

Audio is sent to Gemini and usage is billed to the configured Google account.
The relay has no application authentication, so keep local development bound to
`127.0.0.1`. Add authentication before exposing a new deployment publicly.

## Deploy on Modal

The Modal workspace uses the `2025.06` image builder so the deployment can run
on Python 3.13.

```sh
uvx modal setup
uvx modal workspace settings set image-builder-version 2025.06
uvx modal secret create gradient-google --from-dotenv .env
uvx modal serve modal_app.py
uvx modal deploy modal_app.py
```

The generated `modal.run` URL serves HTTPS and the browser connects to the
matching `wss://` endpoint. The deployment scales to zero while idle and lets a
walk stay connected for up to one hour.

## Files

- `main.py` defines the agent instructions, tools, app, and static routes.
- `gemini_proxy.py` bridges the client WebSocket to Pydantic AI Gemini Live.
- `walk_demo.py` owns isolated per-call route and narration state.
- `index.html` contains the browser storyboard, microphone capture, and demo
  event controls.
- `assets/` contains the map and other static prototype media.
- `modal_app.py` packages the ASGI app for Modal.
- `docs/walking-podcast-flow.md` describes the intended GPS and photo flows.
- `tests/` covers the relay contract, route changes, and podcast state.
- `uv.lock` pins the Python environment, including Pydantic AI 2.46.0.

## Verify

```sh
uv run pytest
```
