from __future__ import annotations

import unittest
from collections.abc import Mapping
from typing import Any

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.exceptions import UserError
from pydantic_ai.messages import SystemPromptPart

from gemini_proxy import (
    GeminiConfigurationError,
    RelayClient,
    _receive_microphone,
    create_gemini_router,
    make_gemini_realtime,
)
from walk_demo import WalkSessionDeps


def empty_configuration() -> Mapping[str, str | None]:
    return {}


class FakeWebSocket:
    def __init__(self, messages: list[dict[str, Any]]) -> None:
        self.messages = iter(messages)
        self.events: list[dict[str, Any]] = []

    async def receive(self) -> dict[str, Any]:
        return next(self.messages)

    async def send_json(self, event: dict[str, Any]) -> None:
        self.events.append(event)

    async def send_bytes(self, _chunk: bytes) -> None:
        raise AssertionError("The microphone path must not send audio to the client")


class FakeSession:
    def __init__(self) -> None:
        self.interruptions: list[int] = []
        self.enqueued: list[tuple[SystemPromptPart, str]] = []

    async def interrupt(self, *, played_bytes: int) -> bool:
        self.interruptions.append(played_bytes)
        return True

    def enqueue(self, prompt: SystemPromptPart, *, priority: str) -> None:
        self.enqueued.append((prompt, priority))


class UnsupportedInterruptSession(FakeSession):
    async def interrupt(self, *, played_bytes: int) -> bool:
        raise UserError("This realtime model does not support interruption.")


class GeminiProxyTest(unittest.TestCase):
    def test_health_reports_missing_configuration(self) -> None:
        app = FastAPI()
        app.include_router(create_gemini_router(Agent(), empty_configuration))

        with TestClient(app) as client:
            response = client.get("/gemini/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "configured": False,
                "model": "google:gemini-2.5-flash-native-audio-latest",
                "voice": "Puck",
                "protocol": 1,
            },
        )

    def test_websocket_returns_actionable_configuration_error(self) -> None:
        app = FastAPI()
        app.include_router(create_gemini_router(Agent(), empty_configuration))

        with TestClient(app) as client:
            with client.websocket_connect("/gemini/voice") as websocket:
                event = websocket.receive_json()

        self.assertEqual(event["type"], "error")
        self.assertEqual(event["code"], "not_configured")
        self.assertTrue(event["fatal"])
        self.assertIn("GOOGLE_API_KEY", event["message"])

    def test_model_factory_requires_google_api_key(self) -> None:
        with self.assertRaisesRegex(GeminiConfigurationError, "GOOGLE_API_KEY"):
            make_gemini_realtime(Agent(), empty_configuration())


class MicrophoneProtocolTest(unittest.IsolatedAsyncioTestCase):
    async def test_audio_and_control_messages_are_processed(self) -> None:
        websocket = FakeWebSocket(
            [
                {"type": "websocket.receive", "bytes": b"\x00"},
                {"type": "websocket.receive", "text": "not-json"},
                {"type": "websocket.receive", "text": '{"type":"ping"}'},
                {
                    "type": "websocket.receive",
                    "text": '{"type":"interrupt","played_bytes":640}',
                },
                {"type": "websocket.receive", "bytes": b"\x00\x01"},
                {"type": "websocket.receive", "text": '{"type":"close"}'},
            ]
        )
        session = FakeSession()
        client = RelayClient(websocket)  # type: ignore[arg-type]

        chunks = [
            chunk
            async for chunk in _receive_microphone(  # type: ignore[arg-type]
                websocket, session, client
            )
        ]

        self.assertEqual(chunks, [b"\x00\x01"])
        self.assertEqual(session.interruptions, [640])
        self.assertEqual(
            [event["type"] for event in websocket.events],
            ["error", "error", "pong", "clear_output"],
        )
        self.assertEqual(websocket.events[0]["code"], "invalid_audio")
        self.assertEqual(websocket.events[1]["code"], "invalid_json")

    async def test_demo_plan_starts_the_first_podcast_chapter(self) -> None:
        websocket = FakeWebSocket(
            [
                {
                    "type": "websocket.receive",
                    "text": '{"type":"demo_plan","theme":"music"}',
                },
                {"type": "websocket.receive", "text": '{"type":"close"}'},
            ]
        )
        session = FakeSession()
        client = RelayClient(websocket)  # type: ignore[arg-type]
        deps = WalkSessionDeps()

        chunks = [
            chunk
            async for chunk in _receive_microphone(  # type: ignore[arg-type]
                websocket, session, client, deps
            )
        ]

        self.assertEqual(chunks, [])
        self.assertEqual(len(session.enqueued), 1)
        prompt, priority = session.enqueued[0]
        self.assertIn("We are at", prompt.content)
        self.assertEqual(priority, "asap")
        self.assertEqual(deps.state.podcast_status, "playing")
        self.assertEqual(websocket.events[-1]["type"], "podcast_state")
        self.assertEqual(websocket.events[-1]["state"], "playing")

    async def test_route_deviation_commits_route_and_enqueues_explanation(self) -> None:
        websocket = FakeWebSocket(
            [
                {
                    "type": "websocket.receive",
                    "text": ('{"type":"demo_plan","theme":"music"}'),
                },
                {
                    "type": "websocket.receive",
                    "text": (
                        '{"type":"route_deviation","route_version":1,'
                        '"latitude":51.513,"longitude":-0.1337,'
                        '"distance_from_route_m":54,"heading_deg":270}'
                    ),
                },
                {"type": "websocket.receive", "text": '{"type":"close"}'},
            ]
        )
        session = FakeSession()
        client = RelayClient(websocket)  # type: ignore[arg-type]
        deps = WalkSessionDeps()

        chunks = [
            chunk
            async for chunk in _receive_microphone(  # type: ignore[arg-type]
                websocket, session, client, deps
            )
        ]

        self.assertEqual(chunks, [])
        self.assertEqual(deps.state.route_version, 2)
        self.assertEqual(deps.state.storyboard_version, "v3b")
        self.assertEqual(
            [event["type"] for event in websocket.events],
            [
                "walk_ack",
                "podcast_state",
                "walk_ack",
                "route_update",
                "podcast_state",
            ],
        )
        self.assertEqual(websocket.events[2]["action"], "route_deviation")
        prompt, priority = session.enqueued[-1]
        self.assertIn("via Berwick Street", prompt.content)
        self.assertEqual(priority, "asap")

    async def test_stale_route_deviation_is_rejected_without_enqueueing(self) -> None:
        websocket = FakeWebSocket(
            [
                {
                    "type": "websocket.receive",
                    "text": '{"type":"demo_plan"}',
                },
                {
                    "type": "websocket.receive",
                    "text": '{"type":"route_deviation","route_version":0,"distance_from_route_m":54}',
                },
                {"type": "websocket.receive", "text": '{"type":"close"}'},
            ]
        )
        session = FakeSession()
        client = RelayClient(websocket)  # type: ignore[arg-type]
        deps = WalkSessionDeps()

        [
            chunk
            async for chunk in _receive_microphone(  # type: ignore[arg-type]
                websocket, session, client, deps
            )
        ]

        self.assertEqual(websocket.events[-1]["code"], "stale_route_version")
        self.assertEqual(deps.state.route_version, 1)
        self.assertEqual(len(session.enqueued), 1)

    async def test_unsupported_explicit_interrupt_is_not_fatal(self) -> None:
        websocket = FakeWebSocket(
            [
                {
                    "type": "websocket.receive",
                    "text": '{"type":"interrupt","played_bytes":640}',
                },
                {"type": "websocket.receive", "text": '{"type":"close"}'},
            ]
        )
        client = RelayClient(websocket)  # type: ignore[arg-type]

        chunks = [
            chunk
            async for chunk in _receive_microphone(  # type: ignore[arg-type]
                websocket, UnsupportedInterruptSession(), client
            )
        ]

        self.assertEqual(chunks, [])
        self.assertEqual(websocket.events[0]["code"], "interrupt_unsupported")
        self.assertFalse(websocket.events[0]["fatal"])


if __name__ == "__main__":
    unittest.main()
