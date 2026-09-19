"""Local Pydantic AI voice demo with Gemini WebSocket and OpenAI WebRTC relays."""

from __future__ import annotations

import asyncio
import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dotenv import dotenv_values
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic_ai import Agent
from pydantic_ai.agent import AgentRealtime
from pydantic_ai.messages import FunctionToolCallEvent, FunctionToolResultEvent
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.realtime import (
    RealtimeTurnCompleteEvent,
    WebRTCSession,
)
from pydantic_ai.realtime.openai import OpenAIRealtimeModel, OpenAIRealtimeModelSettings

from gemini_proxy import create_gemini_router

ROOT = Path(__file__).parent
logger = logging.getLogger("uvicorn.error")


def configuration() -> dict[str, str | None]:
    # Saving .env is enough; shell variables take precedence.
    return {**dotenv_values(ROOT / ".env"), **os.environ}


INSTRUCTIONS = (
    "You are Roberto, a concise and friendly voice support assistant. "
    "Use `lookup_time` for time questions and `lookup_support_policy` for account or refund questions. "
    "Keep answers short and natural for speech. These support policies are fictional demo policies."
)

INDEX_HTML = (Path(__file__).parent / "index.html").read_text(encoding="utf-8")

agent = Agent(instructions=INSTRUCTIONS)


@agent.tool_plain
def lookup_time(city: str) -> str:
    """Look up the current local time for a city."""
    timezones = {
        "london": "Europe/London",
        "new york": "America/New_York",
        "tokyo": "Asia/Tokyo",
        "sydney": "Australia/Sydney",
        "san francisco": "America/Los_Angeles",
    }
    zone = timezones.get(city.lower())
    if zone is None:
        return f"I only know these example cities: {', '.join(sorted(timezones))}."
    try:
        now = datetime.now(ZoneInfo(zone))
    except ZoneInfoNotFoundError:  # pragma: no cover - depends on the host tz database
        return f"I could not load timezone data for {city}."
    return now.strftime(f"It is %A, %I:%M %p in {city}.")


@agent.tool_plain
def lookup_support_policy(topic: str) -> str:
    """Return a short canned support policy answer."""
    policies = {
        "refund": "Refunds are available within 30 days for billing errors or duplicate charges.",
        "return": "Physical returns can be started within 14 days of the delivery date.",
        "password": "Reset your password from the sign-in page using the email verification flow.",
    }
    return policies.get(
        topic.lower(), "I only have example policies for refund, return, and password."
    )


def make_realtime() -> AgentRealtime[None]:
    config = configuration()
    key = config.get("OPENAI_API_KEY")
    if not key or not key.strip():
        raise HTTPException(503, "Add OPENAI_API_KEY to .env, save it, then try again.")

    name = config.get("WEBRTC_REALTIME_MODEL") or "openai:gpt-realtime"
    model = OpenAIRealtimeModel(
        name.removeprefix("openai:"), provider=OpenAIProvider(api_key=key)
    )
    settings = OpenAIRealtimeModelSettings(
        openai_voice=config.get("WEBRTC_REALTIME_VOICE") or "marin"
    )
    if transcription := config.get("WEBRTC_TRANSCRIPTION_MODEL"):
        settings["input_transcription_model"] = transcription

    return agent.realtime(model, model_settings=settings)


@dataclass
class Call:
    """One live WebRTC call and its server-side sideband task."""

    realtime: AgentRealtime[None]
    answer_sdp: str
    provider_session: WebRTCSession
    task: asyncio.Task[None] | None = None
    # Set once the sideband has either attached or failed to; `attach_error` distinguishes the two so
    # `/offer` doesn't return a successful answer for a session that never came up.
    attached: asyncio.Event = field(default_factory=asyncio.Event)
    attach_error: BaseException | None = None


CALLS: dict[str, Call] = {}


async def run_sideband(call: Call) -> None:
    """Attach the sideband session to the WebRTC call and run the agent's tool loop over its events."""
    call_id = call.provider_session.call_id
    try:
        async with call.realtime.session(
            provider_session=call.provider_session
        ) as session:
            call.attached.set()
            async for event in session:
                if isinstance(event, FunctionToolCallEvent):
                    logger.info("Tool called: %s", event.part.tool_name)
                elif isinstance(event, FunctionToolResultEvent):
                    logger.info("Tool completed: %s", event.part.tool_name)
                elif isinstance(event, RealtimeTurnCompleteEvent):
                    logger.info(
                        "Turn complete: %s messages", len(session.all_messages())
                    )
    except asyncio.CancelledError:
        raise
    except Exception as exc:
        logger.exception("Voice session failed: %s", call_id)
        # Record the failure so `/offer` can surface it instead of returning a dead call.
        call.attach_error = exc
        call.attached.set()
    finally:
        CALLS.pop(call_id, None)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    try:
        yield
    finally:
        for call in list(CALLS.values()):
            if call.task is not None:
                call.task.cancel()
                with suppress(asyncio.CancelledError):
                    await call.task


app = FastAPI(lifespan=lifespan)
app.include_router(create_gemini_router(agent, configuration))


@app.get("/")
async def index() -> HTMLResponse:
    return HTMLResponse(INDEX_HTML)


@app.post("/offer")
async def offer(request: Request) -> JSONResponse:
    """Relay the browser's SDP offer to the provider, start the sideband, and return the SDP answer."""
    try:
        sdp_offer = (await request.body()).decode("utf-8")
    except UnicodeDecodeError:
        # The SDP offer is untrusted signaling input; reject malformed bytes as a client error, not a 500.
        raise HTTPException(
            status_code=400, detail="Expected a UTF-8 SDP offer in the request body."
        ) from None
    if not sdp_offer.strip():
        raise HTTPException(
            status_code=400, detail="Expected an SDP offer in the request body."
        )

    realtime = make_realtime()
    try:
        answer = await asyncio.wait_for(
            realtime.answer_webrtc_offer(sdp_offer), timeout=30
        )
    except TimeoutError:
        raise HTTPException(504, "The voice provider timed out. Try again.") from None
    except Exception:
        logger.exception("Could not create voice call")
        raise HTTPException(
            502,
            "Could not start the call. Check your API key, realtime access, and server logs.",
        ) from None

    call = Call(
        realtime=realtime, answer_sdp=answer.sdp, provider_session=answer.session
    )
    CALLS[answer.session.call_id] = call

    # Attach the sideband before returning the answer, so the tools are live before the browser (which
    # only starts sending audio once it has the answer) can speak.
    call.task = asyncio.create_task(run_sideband(call))
    try:
        await asyncio.wait_for(call.attached.wait(), timeout=10)
    except TimeoutError:
        call.task.cancel()
        with suppress(asyncio.CancelledError):
            await call.task
        CALLS.pop(answer.session.call_id, None)
        raise HTTPException(
            status_code=504, detail="Timed out attaching the server-side session."
        )
    except asyncio.CancelledError:
        # The client disconnected before receiving the answer, so it never got the `call_id` and can't
        # call `/hangup`. Cancel the sideband and drop the call here to avoid leaking the provider
        # connection and the background agent task.
        call.task.cancel()
        with suppress(asyncio.CancelledError):
            await call.task
        CALLS.pop(answer.session.call_id, None)
        raise
    if call.attach_error is not None or call.task.done():
        raise HTTPException(
            status_code=502, detail="The server-side session failed to attach."
        )

    return JSONResponse({"sdp": call.answer_sdp, "call_id": answer.session.call_id})


@app.post("/hangup/{call_id}")
async def hangup(call_id: str) -> JSONResponse:
    call = CALLS.get(call_id)
    if call is not None and call.task is not None:
        call.task.cancel()
        with suppress(asyncio.CancelledError):
            await call.task
    return JSONResponse({"stopped": call is not None})


@app.get("/health")
async def health() -> dict[str, str | bool]:
    config = configuration()
    return {
        "configured": bool((config.get("OPENAI_API_KEY") or "").strip()),
        "model": config.get("WEBRTC_REALTIME_MODEL") or "openai:gpt-realtime",
        "voice": config.get("WEBRTC_REALTIME_VOICE") or "marin",
    }


@app.get("/calls/{call_id}")
async def call_status(call_id: str) -> dict[str, bool]:
    return {"active": call_id in CALLS}
