"""FastAPI WebSocket relay between Flutter PCM audio and Pydantic AI Gemini Live."""

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

logger = logging.getLogger("uvicorn.error")

DEFAULT_MODEL = "google:gemini-2.5-flash-native-audio-latest"
DEFAULT_VOICE = "Puck"
PROTOCOL_VERSION = 1

ConfigurationLoader = Callable[[], Mapping[str, str | None]]


class GeminiConfigurationError(RuntimeError):
    """The local demo is missing required Gemini configuration."""


@dataclass
class RelayClient:
    """Serialize concurrent binary and JSON writes to one Flutter WebSocket."""

    websocket: WebSocket
    _send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def send_audio(self, chunk: bytes) -> None:
        async with self._send_lock:
            await self.websocket.send_bytes(chunk)

    async def send_event(self, event_type: str, **payload: Any) -> None:
        async with self._send_lock:
            await self.websocket.send_json({"type": event_type, **payload})


def make_gemini_realtime(
    agent: Agent[Any, Any], configuration: Mapping[str, str | None]
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
    )
    return agent.realtime(model, model_settings=settings), configured_model


async def _forward_audio(
    audio: AsyncIterator[bytes], client: RelayClient
) -> None:
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
    session: RealtimeSession, client: RelayClient
) -> None:
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
            await client.send_event("clear_output", reason="barge_in")
        elif isinstance(event, RealtimeTurnCompleteEvent):
            await client.send_event("turn_complete")
        elif isinstance(event, RealtimeSessionReconnectEvent):
            await client.send_event(
                "reconnected", state_restored=event.state_restored
            )
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
            interrupted = await session.interrupt(played_bytes=played_bytes)
            if interrupted:
                await client.send_event("clear_output", reason="client_interrupt")
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
) -> None:
    client = RelayClient(websocket)
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

        tasks = {
            asyncio.create_task(
                session.send_audio(_receive_microphone(websocket, session, client)),
                name="gemini-microphone",
            ),
            asyncio.create_task(
                _forward_audio(audio, client), name="gemini-playback"
            ),
            asyncio.create_task(
                _forward_transcripts(transcripts, client),
                name="gemini-transcripts",
            ),
            asyncio.create_task(
                _forward_session_events(session, client), name="gemini-events"
            ),
        }
        done, pending = await asyncio.wait(
            tasks, return_when=asyncio.FIRST_COMPLETED
        )
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
        try:
            realtime, model_name = make_gemini_realtime(
                agent, configuration_loader()
            )
            await _run_relay(websocket, realtime, model_name)
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
            # concurrent sender is finishing. Treat that like a normal hangup.
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
