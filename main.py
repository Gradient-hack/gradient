"""Local Pydantic AI walking podcast demo with a Gemini Live WebSocket relay."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import dotenv_values
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic_ai import Agent, RunContext

from gemini_proxy import create_gemini_router
from walk_demo import WalkSessionDeps

ROOT = Path(__file__).parent


def configuration() -> dict[str, str | None]:
    # Saving .env is enough; shell variables take precedence.
    return {**dotenv_values(ROOT / ".env"), **os.environ}


INSTRUCTIONS = (
    "You are a warm, curious walking companion hosting a live audio podcast. "
    "Help the walker plan a route, tell short connected stories about places, and adapt when their interests change. "
    "Use plan_walk when they ask for a route and get_walk_status for progress questions. "
    "If the walker says exactly 'Can we talk about music?' or expresses an equivalent topic change, you MUST call change_topic with topic='music' before responding; changing narration alone is not enough. "
    "Use remember_place for a memory or reaction, handle_route_deviation for a wrong turn or request to go via Berwick Street, and find_nearby_food for a food request. "
    "Give natural connected narration in short 30 to 60 second beats with varied transitions. "
    "Never ask whether the walker wants to hear more, offer to stop, or end a beat with a permission question; continue the podcast until the walker speaks. "
    "When the walker interrupts, acknowledge them briefly, answer naturally, and then continue the walk. "
    "Never invent a route or claim a live location you do not have. "
    "The route and stories are fictional demo data, so be transparent if asked."
)

agent = Agent(deps_type=WalkSessionDeps, instructions=INSTRUCTIONS)


@agent.tool
async def plan_walk(
    ctx: RunContext[WalkSessionDeps],
    duration_minutes: int = 25,
    theme: str | None = None,
    interests: list[str] | None = None,
    loop: bool = True,
) -> str:
    """Plan a fake London walking route around the walker's interests."""

    return await ctx.deps.plan_walk(
        duration_minutes=duration_minutes,
        theme=theme,
        interests=interests,
        loop=loop,
    )


@agent.tool
async def change_topic(
    ctx: RunContext[WalkSessionDeps],
    topic: str,
    interests: list[str] | None = None,
    reroute_if_needed: bool = True,
) -> str:
    """Change the route when the walker changes the conversation topic.

    Always call this for “Can we talk about music?” and pass topic="music".
    The route search uses the latest location from this live session.
    """

    latest = ctx.deps.state.latest_location
    return await ctx.deps.revise_walk(
        topic=topic,
        interests=interests,
        current_location=(
            {
                "latitude": float(latest["latitude"]),
                "longitude": float(latest["longitude"]),
            }
            if latest is not None
            else None
        ),
        reroute_if_needed=reroute_if_needed,
    )


@agent.tool
async def remember_place(
    ctx: RunContext[WalkSessionDeps],
    memory: str,
    reaction: str | None = None,
) -> str:
    """Record a place memory or reaction and adapt the walk's future stories."""

    detail = f"{memory} {reaction or ''}".strip()
    return await ctx.deps.revise_walk(memory=detail)


@agent.tool
async def handle_route_deviation(
    ctx: RunContext[WalkSessionDeps], deviation: str
) -> str:
    """Handle a wrong turn or requested detour while preserving the walk."""

    return await ctx.deps.revise_walk(deviation=deviation)


@agent.tool
async def find_nearby_food(
    ctx: RunContext[WalkSessionDeps], craving: str | None = None
) -> str:
    """Find and insert a nearby food stop when it fits the remaining route."""

    return await ctx.deps.revise_walk(
        topic=craving or "nearby food", insert_nearby_food=True
    )


@agent.tool
def get_walk_status(ctx: RunContext[WalkSessionDeps]) -> dict[str, object]:
    """Return the current route and location status for the walker."""

    state = ctx.deps.state
    nearest = None
    if state.latest_location is not None:
        nearest = min(
            state.points_of_interest,
            key=lambda poi: (
                abs(poi.latitude - state.latest_location["latitude"])
                + abs(poi.longitude - state.latest_location["longitude"])
            ),
            default=None,
        )
    return {
        "walk_id": state.walk_id,
        "route_version": state.route_version,
        "theme": state.theme,
        "duration_minutes": state.duration_minutes,
        "latest_location": state.latest_location,
        "next_stop": nearest.name if nearest else None,
        "visited_poi_ids": sorted(state.narrated_poi_ids),
    }


app = FastAPI()
app.include_router(create_gemini_router(agent, configuration))


@app.get("/")
async def index() -> HTMLResponse:
    # Read on each request so editing the single-file prototype only needs a refresh.
    return HTMLResponse((ROOT / "index.html").read_text(encoding="utf-8"))


@app.get("/health")
async def health() -> dict[str, str | bool]:
    config = configuration()
    return {
        "configured": bool((config.get("GOOGLE_API_KEY") or "").strip()),
        "model": config.get("GEMINI_REALTIME_MODEL")
        or "google:gemini-2.5-flash-native-audio-latest",
        "voice": config.get("GEMINI_REALTIME_VOICE") or "Puck",
    }
