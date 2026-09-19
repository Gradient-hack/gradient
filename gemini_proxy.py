"""FastAPI WebSocket relay between browser PCM audio and Gemini Live."""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator, Callable, Mapping
from contextlib import suppress
from dataclasses import dataclass, field
from typing import Any

from fastapi import APIRouter, WebSocket
from pydantic_ai import Agent
from pydantic_ai.agent import AgentRealtime
from pydantic_ai.exceptions import UserError
from pydantic_ai.messages import (
    FunctionToolCallEvent,
    FunctionToolResultEvent,
    RealtimeResponseInterruptedEvent,
    RealtimeSessionErrorEvent,
    RealtimeSessionReconnectEvent,
    RealtimeTurnCompleteEvent,
)
from pydantic_ai.providers.google import GoogleProvider
from pydantic_ai.realtime import RealtimeSession, TranscriptUpdate
from pydantic_ai.realtime.google import (
    GoogleRealtimeModel,
    GoogleRealtimeModelSettings,
)
from starlette.websockets import WebSocketDisconnect, WebSocketState

from walk_demo import RouteVersionMismatchError, WalkSessionDeps

logger = logging.getLogger("uvicorn.error")

DEFAULT_MODEL = "google:gemini-2.5-flash-native-audio-latest"
DEFAULT_VOICE = "Puck"
PROTOCOL_VERSION = 1

ConfigurationLoader = Callable[[], Mapping[str, str | None]]


class GeminiConfigurationError(RuntimeError):
    """The local demo is missing required Gemini configuration."""


@dataclass
class RelayClient:
    """Serialize concurrent binary and JSON writes to one browser WebSocket."""

    websocket: WebSocket
    _send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def send_audio(self, chunk: bytes) -> None:
        async with self._send_lock:
            await self.websocket.send_bytes(chunk)

    async def send_event(self, event_type: str, **payload: Any) -> None:
        async with self._send_lock:
            await self.websocket.send_json({"type": event_type, **payload})


def make_gemini_realtime(
    agent: Agent[Any, Any],
    configuration: Mapping[str, str | None],
    *,
    deps: WalkSessionDeps | None = None,
) -> tuple[AgentRealtime[Any], str]:
    """Build a Gemini realtime agent using values reloaded from `.env`."""

    api_key = (configuration.get("GOOGLE_API_KEY") or "").strip()
    if not api_key:
        raise GeminiConfigurationError(
            "Add GOOGLE_API_KEY to .env, save it, then reconnect."
        )

    configured_model = configuration.get("GEMINI_REALTIME_MODEL") or DEFAULT_MODEL
    model_name = configured_model.removeprefix("google:")
    voice = configuration.get("GEMINI_REALTIME_VOICE") or DEFAULT_VOICE
    provider = GoogleProvider(api_key=api_key)
    model = GoogleRealtimeModel(model_name, provider=provider)
    settings = GoogleRealtimeModelSettings(
        google_voice=voice,
        google_input_transcription=True,
        google_output_transcription=True,
        google_activity_handling="interrupts",
        google_vad={
            "start_sensitivity": "high",
            "end_sensitivity": "high",
            "prefix_padding_ms": 100,
            "silence_duration_ms": 300,
        },
        reconnect={
            "max_attempts": 3,
            "max_reconnects": 50,
            "base_delay": 0.5,
            "max_delay": 30,
            "jitter": True,
        },
        google_context_compression={
            "trigger_tokens": 25_000,
            "target_tokens": 8_000,
        },
        google_enable_session_resumption=True,
    )
    return (
        agent.realtime(
            model,
            deps=deps or WalkSessionDeps(),
            model_settings=settings,
        ),
        configured_model,
    )


async def _forward_audio(audio: AsyncIterator[bytes], client: RelayClient) -> None:
    async for chunk in audio:
        await client.send_audio(chunk)


async def _forward_transcripts(
    transcripts: AsyncIterator[TranscriptUpdate], client: RelayClient
) -> None:
    async for update in transcripts:
        await client.send_event(
            "transcript",
            index=update.index,
            speaker=update.speaker,
            text=update.transcript,
            delta=update.delta,
        )


async def _forward_session_events(
    session: RealtimeSession, client: RelayClient, deps: WalkSessionDeps | None = None
) -> None:
    deps = deps or WalkSessionDeps()

    async def send_podcast_state() -> None:
        event = deps.state.podcast_event()
        await client.send_event(event.pop("type"), **event)

    async def schedule_next_chapter() -> None:
        prompt = deps.state.start_next_chapter()
        if prompt is not None:
            try:
                session.enqueue(prompt, priority="asap")
            except (RuntimeError, UserError):
                deps.state.interrupt_podcast()
                logger.debug("Could not enqueue podcast chapter", exc_info=True)
        await send_podcast_state()

    async for event in session:
        if isinstance(event, FunctionToolCallEvent):
            await client.send_event(
                "tool_call",
                name=event.part.tool_name,
                call_id=event.tool_call_id,
            )
        elif isinstance(event, FunctionToolResultEvent):
            await client.send_event(
                "tool_result",
                name=getattr(event.part, "tool_name", None),
                call_id=event.tool_call_id,
            )
        elif isinstance(event, RealtimeResponseInterruptedEvent):
            deps.state.interrupt_podcast()
            await client.send_event("clear_output", reason="barge_in")
            await send_podcast_state()
        elif isinstance(event, RealtimeTurnCompleteEvent):
            await client.send_event("turn_complete")
            deps.state.complete_current_chapter()
            await schedule_next_chapter()
        elif isinstance(event, RealtimeSessionReconnectEvent):
            await client.send_event("reconnected", state_restored=event.state_restored)
        elif isinstance(event, RealtimeSessionErrorEvent):
            await client.send_event(
                "error",
                code=event.code or "provider_session_error",
                message=event.message,
                fatal=not event.recoverable,
            )


async def _receive_microphone(
    websocket: WebSocket,
    session: RealtimeSession,
    client: RelayClient,
    deps: WalkSessionDeps | None = None,
) -> AsyncIterator[bytes]:
    """Yield PCM frames and process client control messages on the same socket."""

    while True:
        message = await websocket.receive()
        if message["type"] == "websocket.disconnect":
            return

        if audio := message.get("bytes"):
            if len(audio) % 2:
                await client.send_event(
                    "error",
                    code="invalid_audio",
                    message="PCM16 audio frames must contain an even number of bytes.",
                    fatal=False,
                )
                continue
            yield audio
            continue

        text = message.get("text")
        if text is None:
            continue
        try:
            control = json.loads(text)
        except json.JSONDecodeError:
            await client.send_event(
                "error",
                code="invalid_json",
                message="Control messages must be valid JSON.",
                fatal=False,
            )
            continue
        if not isinstance(control, dict):
            await client.send_event(
                "error",
                code="invalid_control",
                message="Control messages must be JSON objects.",
                fatal=False,
            )
            continue

        control_type = control.get("type")
        if control_type == "ping":
            await client.send_event("pong")
        elif control_type == "close":
            return
        elif control_type == "interrupt":
            played_bytes = control.get("played_bytes")
            if not isinstance(played_bytes, int) or played_bytes < 0:
                await client.send_event(
                    "error",
                    code="invalid_interrupt",
                    message="interrupt.played_bytes must be a non-negative integer.",
                    fatal=False,
                )
                continue
            try:
                interrupted = await session.interrupt(played_bytes=played_bytes)
            except UserError as error:
                await client.send_event(
                    "error",
                    code="interrupt_unsupported",
                    message=str(error),
                    fatal=False,
                )
                continue
            if interrupted:
                await client.send_event("clear_output", reason="client_interrupt")
        elif control_type == "location_update":
            if deps is None:
                await client.send_event(
                    "error",
                    code="walk_unavailable",
                    message="Walk state is unavailable for this session.",
                    fatal=False,
                )
                continue
            try:
                progress, narration = deps.location_from_control(control)
            except ValueError as error:
                await client.send_event(
                    "error",
                    code="invalid_location",
                    message=str(error),
                    fatal=False,
                )
                continue
            await client.send_event(
                progress.pop("type"),
                **progress,
            )
            if narration is not None:
                try:
                    session.enqueue(narration, priority="when_idle")
                except (RuntimeError, UserError):
                    # The provider can close between receiving a location fix
                    # and enqueueing the narration. The next connection can
                    # continue from a fresh session safely.
                    logger.debug("Could not enqueue POI narration", exc_info=True)
        elif control_type == "route_deviation":
            if deps is None:
                await client.send_event(
                    "error",
                    code="walk_unavailable",
                    message="Walk state is unavailable for this session.",
                    fatal=False,
                )
                continue
            try:
                result, reroute_prompt = await deps.route_deviation_from_control(
                    control
                )
            except RouteVersionMismatchError as error:
                await client.send_event(
                    "error",
                    code="stale_route_version",
                    message=str(error),
                    fatal=False,
                )
                continue
            except (TypeError, ValueError) as error:
                await client.send_event(
                    "error",
                    code="invalid_route_deviation",
                    message=str(error),
                    fatal=False,
                )
                continue

            await client.send_event(
                "walk_ack",
                action="route_deviation",
                summary=result["summary"],
                route_version=result["route_version"],
                distance_from_route_m=result["distance_from_route_m"],
            )
            # State events normally travel through the dependency event sink.
            # Send them directly in isolated protocol tests and other callers
            # that construct WalkSessionDeps without a sink.
            if deps.event_sink is None:
                route_event = deps.state.route_event()
                await client.send_event(route_event.pop("type"), **route_event)
                podcast_event = deps.state.podcast_event()
                await client.send_event(podcast_event.pop("type"), **podcast_event)
            try:
                session.enqueue(reroute_prompt, priority="asap")
            except (RuntimeError, UserError):
                logger.debug(
                    "Could not enqueue route deviation response", exc_info=True
                )
        elif control_type in {"demo_plan", "demo_theme"}:
            if deps is None:
                await client.send_event(
                    "error",
                    code="walk_unavailable",
                    message="Walk state is unavailable for this session.",
                    fatal=False,
                )
                continue
            try:
                if control_type == "demo_plan":
                    summary = await deps.plan_walk(
                        duration_minutes=control.get("duration_minutes", 25),
                        theme=control.get("theme"),
                        interests=control.get("interests"),
                        loop=control.get("loop", True),
                    )
                else:
                    summary = await deps.revise_walk(
                        theme=control.get("theme"),
                        interests=control.get("interests"),
                        topic=control.get("topic"),
                        memory=control.get("memory"),
                        deviation=control.get("deviation"),
                        insert_nearby_food=control.get("insert_nearby_food", False),
                        current_location=control.get("current_location"),
                        reroute_if_needed=control.get("reroute_if_needed", True),
                    )
            except (TypeError, ValueError) as error:
                await client.send_event(
                    "error",
                    code="invalid_walk_control",
                    message=str(error),
                    fatal=False,
                )
                continue
            await client.send_event("walk_ack", action=control_type, summary=summary)
            chapter_prompt = deps.state.start_next_chapter()
            try:
                if chapter_prompt is not None:
                    session.enqueue(chapter_prompt, priority="asap")
            except (RuntimeError, UserError):
                logger.debug("Could not enqueue demo walk response", exc_info=True)
            podcast_event = deps.state.podcast_event()
            await client.send_event(podcast_event.pop("type"), **podcast_event)
        else:
            await client.send_event(
                "error",
                code="unknown_control",
                message=f"Unknown control message: {control_type!r}.",
                fatal=False,
            )


async def _run_relay(
    websocket: WebSocket,
    realtime: AgentRealtime[Any],
    model_name: str,
    deps: WalkSessionDeps | None = None,
) -> None:
    client = RelayClient(websocket)
    deps = deps or WalkSessionDeps()
    async with realtime.session(handle_barge_in=True) as session:
        # Register tap views before announcing readiness so no first-turn audio or
        # transcript can arrive between the client's first frame and subscription.
        audio = session.stream_audio()
        transcripts = session.stream_transcripts(delta=True)
        await client.send_event(
            "ready",
            protocol=PROTOCOL_VERSION,
            model=model_name,
            input_sample_rate=session.audio_input_sample_rate,
            output_sample_rate=session.audio_output_sample_rate,
            encoding="pcm16le",
            channels=1,
        )
        route_event = deps.state.route_event()
        await client.send_event(route_event.pop("type"), **route_event)
        podcast_event = deps.state.podcast_event()
        await client.send_event(podcast_event.pop("type"), **podcast_event)

        tasks = {
            asyncio.create_task(
                session.send_audio(
                    _receive_microphone(websocket, session, client, deps)
                ),
                name="gemini-microphone",
            ),
            asyncio.create_task(_forward_audio(audio, client), name="gemini-playback"),
            asyncio.create_task(
                _forward_transcripts(transcripts, client),
                name="gemini-transcripts",
            ),
            asyncio.create_task(
                _forward_session_events(session, client, deps), name="gemini-events"
            ),
        }
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        results = await asyncio.gather(*done, return_exceptions=True)
        for result in results:
            if isinstance(result, BaseException):
                raise result


def create_gemini_router(
    agent: Agent[Any, Any], configuration_loader: ConfigurationLoader
) -> APIRouter:
    """Create the relay routes while keeping the shared demo agent injectable."""

    router = APIRouter(prefix="/gemini", tags=["gemini-live"])

    @router.get("/health")
    async def health() -> dict[str, str | bool | int]:
        config = configuration_loader()
        return {
            "configured": bool((config.get("GOOGLE_API_KEY") or "").strip()),
            "model": config.get("GEMINI_REALTIME_MODEL") or DEFAULT_MODEL,
            "voice": config.get("GEMINI_REALTIME_VOICE") or DEFAULT_VOICE,
            "protocol": PROTOCOL_VERSION,
        }

    @router.websocket("/voice")
    async def voice_socket(websocket: WebSocket) -> None:
        await websocket.accept()
        client = RelayClient(websocket)
        deps = WalkSessionDeps()

        async def send_walk_event(event: dict[str, Any]) -> None:
            event = dict(event)
            event_type = event.pop("type", "walk_event")
            await client.send_event(event_type, **event)

        deps.event_sink = send_walk_event
        try:
            realtime, model_name = make_gemini_realtime(
                agent, configuration_loader(), deps=deps
            )
            await _run_relay(websocket, realtime, model_name, deps)
        except GeminiConfigurationError as error:
            await client.send_event(
                "error",
                code="not_configured",
                message=str(error),
                fatal=True,
            )
        except asyncio.CancelledError:
            raise
        except RuntimeError as error:
            # Starlette raises RuntimeError when a peer disappears while a
            # concurrent sender is finishing. Treat that like a normal close.
            if websocket.client_state == WebSocketState.CONNECTED:
                logger.exception("Gemini relay failed")
                with suppress(RuntimeError, WebSocketDisconnect):
                    await client.send_event(
                        "error",
                        code="relay_error",
                        message=str(error),
                        fatal=True,
                    )
        except Exception:
            logger.exception("Gemini relay failed")
            if websocket.client_state == WebSocketState.CONNECTED:
                with suppress(RuntimeError, WebSocketDisconnect):
                    await client.send_event(
                        "error",
                        code="relay_error",
                        message="The Gemini Live session failed. Check the server logs.",
                        fatal=True,
                    )
        finally:
            if websocket.client_state == WebSocketState.CONNECTED:
                with suppress(RuntimeError, WebSocketDisconnect):
                    await websocket.close(code=1000)

    return router
