"""Deterministic walking-podcast state and fake route data for the local demo.

The real application will eventually replace the route builder with Places and
Routes adapters. Keeping the state machine here means the WebSocket protocol
and model tools can be exercised without making network calls.
"""

from __future__ import annotations

import math
import uuid
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from pydantic_ai.messages import SystemPromptPart

EventSink = Callable[[dict[str, Any]], Awaitable[None]]


class RouteVersionMismatchError(ValueError):
    """A client event was based on a route that is no longer current."""


@dataclass(frozen=True)
class FakePoi:
    id: str
    name: str
    subtitle: str
    latitude: float
    longitude: float
    story: str
    kind: str
    themes: tuple[str, ...]


# These coordinates are deliberately close together so a browser can simulate
# progress using the controls without having to walk a real route. The names
# and ordering mirror the four storyboard beats used by the web prototype.
FAKE_POIS: tuple[FakePoi, ...] = (
    FakePoi(
        "chinatown-gate",
        "Chinatown Gate",
        "The southern entrance to Chinatown",
        51.5117,
        -0.1310,
        "The Chinatown Gate opens the walk into Gerrard Street, where London's Chinese community has made food, language, and celebration part of Soho's daily rhythm.",
        "landmark",
        ("history", "tudor", "chinese food", "food"),
    ),
    FakePoi(
        "gerrard-street",
        "Gerrard Street",
        "Chinatown's restaurant spine",
        51.5115,
        -0.1318,
        "Gerrard Street's signs, restaurants, bakeries, and late-night kitchens show how a neighbourhood can be both a destination and a living community.",
        "street",
        ("history", "chinese food", "food"),
    ),
    FakePoi(
        "st-annes-soho",
        "St Anne's Soho",
        "A church at the centre of the old parish",
        51.5136,
        -0.1315,
        "St Anne's Soho anchors a parish whose history reaches back through the area's older village edges and into the dense, restless West End around it.",
        "church",
        ("history", "tudor", "architecture"),
    ),
    FakePoi(
        "soho-square",
        "Soho Square",
        "A pocket of green in the West End",
        51.5135,
        -0.1329,
        "Soho Square compresses centuries of London into one garden: formal terraces, changing communities, and the constant movement of the West End.",
        "square",
        ("history", "tudor", "architecture", "music", "counterculture"),
    ),
    FakePoi(
        "berwick-street",
        "Berwick Street",
        "Market, music, and Soho life",
        51.5128,
        -0.1344,
        "Berwick Street has held together market stalls, independent shops, and music history, making it a natural detour when the walker's curiosity pulls west.",
        "market",
        ("history", "music", "counterculture", "food"),
    ),
    FakePoi(
        "old-compton-street",
        "Old Compton Street",
        "The bright, noisy heart of Soho",
        51.5127,
        -0.1318,
        "Old Compton Street carries Soho's music, nightlife, and queer history in a compact run of theatres, bars, cafés, and changing façades.",
        "street",
        ("music", "counterculture", "history"),
    ),
    FakePoi(
        "ronnie-scotts",
        "Ronnie Scott's",
        "A jazz club with a global sound",
        51.5133,
        -0.1320,
        "Ronnie Scott's brought international jazz into the Soho night, helping make this small part of London a destination for musicians and listeners.",
        "music-venue",
        ("music", "counterculture"),
    ),
    FakePoi(
        "spirit-of-soho-mural",
        "Spirit of Soho Mural",
        "A public memory painted on a wall",
        51.5130,
        -0.1337,
        "The Spirit of Soho mural turns a wall into a neighbourhood scrapbook, holding the faces, venues, and countercultural memories that shaped modern Soho.",
        "mural",
        ("music", "counterculture", "mural", "memory"),
    ),
    FakePoi(
        "nearby-food-stop",
        "Chinatown Food Stop",
        "A quick nearby bite",
        51.5120,
        -0.1322,
        "This fictional food stop is close enough for a short pause, keeping the walk's Chinese food thread alive without sending the walker far off route.",
        "food",
        ("food", "chinese food"),
    ),
)

FAKE_POIS_BY_ID = {poi.id: poi for poi in FAKE_POIS}

STORYBOARD_ROUTES: dict[str, tuple[str, ...]] = {
    "v1": (
        "chinatown-gate",
        "gerrard-street",
        "st-annes-soho",
        "soho-square",
        "berwick-street",
    ),
    "v2": (
        "old-compton-street",
        "ronnie-scotts",
        "spirit-of-soho-mural",
        "soho-square",
    ),
    "v3a": (
        "old-compton-street",
        "ronnie-scotts",
        "spirit-of-soho-mural",
        "soho-square",
    ),
    "v3b": (
        "old-compton-street",
        "spirit-of-soho-mural",
        "berwick-street",
        "soho-square",
    ),
    "v4": (
        "old-compton-street",
        "ronnie-scotts",
        "spirit-of-soho-mural",
        "nearby-food-stop",
        "soho-square",
    ),
}

STORYBOARD_PREFERENCES: dict[str, tuple[str, ...]] = {
    "v1": ("Tudor history", "local history", "Chinese food"),
    "v2": ("music", "counterculture"),
    "v3a": (
        "music",
        "counterculture",
        "public art",
        "cultural history",
        "murals",
    ),
    "v3b": (
        "music",
        "counterculture",
        "public art",
        "cultural history",
        "murals",
    ),
    "v4": ("music", "counterculture", "nearby food"),
}

STORYBOARD_LABELS = {
    "v1": "Chinatown history and food",
    "v2": "Soho music and counterculture",
    "v3a": "Soho murals and remembered places",
    "v3b": "Soho via Berwick Street",
    "v4": "Soho music with a nearby food stop",
}


def _normalise_theme(theme: str | None, interests: Sequence[str] | None) -> str:
    if theme is not None and not isinstance(theme, str):
        raise ValueError("theme must be a string.")
    if isinstance(interests, str):
        interests = (interests,)
    elif interests is not None and not isinstance(interests, Sequence):
        raise ValueError("interests must be a list of strings.")
    values = [
        str(value).strip().lower() for value in (interests or ()) if str(value).strip()
    ]
    if theme and theme.strip():
        values.insert(0, theme.strip().lower())
    return values[0] if values else "architecture"


def _distance_m(
    latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float
) -> float:
    """Return a good-enough local distance for the fake London route."""

    latitude_scale = 111_320.0
    longitude_scale = 111_320.0 * math.cos(math.radians((latitude_a + latitude_b) / 2))
    return math.hypot(
        (latitude_b - latitude_a) * latitude_scale,
        (longitude_b - longitude_a) * longitude_scale,
    )


@dataclass
class WalkSessionState:
    walk_id: str = field(default_factory=lambda: f"walk_{uuid.uuid4().hex[:8]}")
    route_version: int = 0
    theme: str = "history"
    duration_minutes: int = 25
    loop: bool = True
    geometry: list[tuple[float, float]] = field(default_factory=list)
    points_of_interest: list[FakePoi] = field(default_factory=list)
    storyboard_version: str = "v1"
    route_label: str = STORYBOARD_LABELS["v1"]
    preferences: list[str] = field(
        default_factory=lambda: list(STORYBOARD_PREFERENCES["v1"])
    )
    preference_deltas: dict[str, list[str]] = field(
        default_factory=lambda: {"added": [], "removed": []}
    )
    search_origin: dict[str, float] | None = None
    deviation: str | None = None
    deviation_distance_m: float | None = None
    deviation_heading_deg: float | None = None
    deviation_reason: str | None = None
    memories: list[dict[str, str]] = field(default_factory=list)
    latest_location: dict[str, Any] | None = None
    last_location_seq: int = -1
    narrated_poi_ids: set[str] = field(default_factory=set)
    podcast_active: bool = False
    podcast_status: str = "listening"
    chapter_queue: list[FakePoi] = field(default_factory=list)
    current_chapter: FakePoi | None = None
    scheduled_chapter_id: str | None = None
    scheduled_prompt_kind: str | None = None
    queued_transition_id: str | None = None
    current_stop_id: str | None = None
    current_stop_index: int | None = None
    beat_number: int = 0

    def __post_init__(self) -> None:
        if not self.points_of_interest:
            self._build_route("v1")

    def _build_route(
        self,
        storyboard_version: str,
        *,
        search_origin: dict[str, float] | None = None,
        deviation: str | None = None,
    ) -> None:
        poi_ids = STORYBOARD_ROUTES[storyboard_version]
        self.storyboard_version = storyboard_version
        self.route_label = STORYBOARD_LABELS[storyboard_version]
        self.points_of_interest = [FAKE_POIS_BY_ID[poi_id] for poi_id in poi_ids]
        self.geometry = [
            (poi.latitude, poi.longitude) for poi in self.points_of_interest
        ]
        self.preferences = list(STORYBOARD_PREFERENCES[storyboard_version])
        self.search_origin = search_origin
        self.deviation = deviation
        self.deviation_distance_m = None
        self.deviation_heading_deg = None
        self.deviation_reason = None

    def _set_preference_deltas(self, previous: Sequence[str]) -> None:
        current = set(self.preferences)
        previous_set = set(previous)
        self.preference_deltas = {
            "added": sorted(current - previous_set),
            "removed": sorted(previous_set - current),
        }

    def _seed_podcast(self) -> None:
        """Reset the future narration queue while retaining completed chapters."""

        self.chapter_queue = list(self.points_of_interest)
        self.current_chapter = None
        self.scheduled_chapter_id = None
        self.scheduled_prompt_kind = None
        self.queued_transition_id = None
        self.current_stop_id = None
        self.current_stop_index = None
        self.beat_number = 0
        self.podcast_active = bool(self.chapter_queue)
        self.podcast_status = "listening"

    def _set_anchor(self, poi: FakePoi) -> None:
        self.current_stop_id = poi.id
        self.current_stop_index = self.points_of_interest.index(poi)
        self.current_chapter = poi
        self.beat_number = 0
        self.chapter_queue = self.points_of_interest[self.current_stop_index + 1 :]

    def start_next_chapter(self) -> SystemPromptPart | None:
        """Reserve another story beat for the current route stop."""

        if not self.podcast_active or self.scheduled_chapter_id is not None:
            return None
        if self.current_chapter is None:
            if not self.points_of_interest:
                self.podcast_active = False
                self.podcast_status = "completed"
                return None
            self._set_anchor(self.points_of_interest[0])
        if self.current_chapter is None:
            self.podcast_active = False
            self.podcast_status = "completed"
            return None
        chapter = self.current_chapter
        self.beat_number += 1
        self.scheduled_chapter_id = chapter.id
        self.scheduled_prompt_kind = "beat"
        self.podcast_status = "playing"
        transitions = (
            "Start with the setting and one vivid detail. ",
            "Now add a human detail or a connection to the neighbourhood. ",
            "Draw out one more angle before letting the street carry us onward. ",
        )
        transition = transitions[(self.beat_number - 1) % len(transitions)]
        return SystemPromptPart(
            f"{transition}Speak for roughly 30 to 60 seconds in a natural, connected way. "
            "Stay with this place until a location update says we have reached another stop. "
            "Do not imply that the walker has moved on, and avoid repeating facts or wording "
            "from earlier beats. Deepen the story through a fresh sensory, human, or historical angle. "
            "Do not ask whether the walker wants to hear more or offer to stop. "
            f"We are at {chapter.name}. {chapter.story}"
        )

    def complete_current_chapter(self) -> None:
        """Commit the reserved chapter after its assistant turn completes."""

        if self.scheduled_chapter_id is None and not self.podcast_active:
            return
        if self.scheduled_chapter_id is None:
            # A user/tool response can finish before any location-anchored beat
            # has been reserved. Keep the walk alive so the relay can start the
            # first beat instead of treating that conversational turn as the
            # end of the route.
            self.podcast_status = "listening"
            return
        self.scheduled_chapter_id = None
        self.scheduled_prompt_kind = None
        if self.queued_transition_id is not None:
            transition = FAKE_POIS_BY_ID[self.queued_transition_id]
            self.queued_transition_id = None
            self._set_anchor(transition)
            self.scheduled_chapter_id = transition.id
            self.scheduled_prompt_kind = "transition"
            self.podcast_status = "playing"
            return
        if self.current_stop_id is not None:
            self.podcast_active = True
            self.podcast_status = "listening"
        else:
            self.podcast_active = False
            self.podcast_status = "completed"

    def interrupt_podcast(self) -> None:
        """Return an interrupted chapter to the front for post-answer resume."""

        self.scheduled_chapter_id = None
        self.scheduled_prompt_kind = None
        self.queued_transition_id = None
        if self.podcast_active:
            self.podcast_status = "listening"

    def podcast_event(self) -> dict[str, Any]:
        current = self.current_chapter
        next_chapter = self.chapter_queue[0] if self.chapter_queue else None

        def chapter_payload(chapter: FakePoi | None) -> dict[str, str] | None:
            if chapter is None:
                return None
            return {
                "id": chapter.id,
                "name": chapter.name,
                "subtitle": chapter.subtitle,
                "story": chapter.story,
            }

        return {
            "type": "podcast_state",
            "walk_id": self.walk_id,
            "route_version": self.route_version,
            "state": self.podcast_status,
            "status": self.podcast_status,
            "current_chapter_id": current.id if current else None,
            "current_chapter": chapter_payload(current),
            "current_stop_id": self.current_stop_id,
            "beat_number": self.beat_number,
            "next_chapter_id": next_chapter.id if next_chapter else None,
            "next_chapter": chapter_payload(next_chapter),
            "completed_chapter_ids": sorted(self.narrated_poi_ids),
        }

    def plan(
        self,
        *,
        duration_minutes: int = 25,
        theme: str | None = None,
        interests: Sequence[str] | None = None,
        loop: bool = True,
    ) -> str:
        previous_preferences = tuple(self.preferences)
        self.duration_minutes = max(5, min(int(duration_minutes), 180))
        requested_theme = _normalise_theme(theme, interests)
        storyboard_version = (
            "v2" if requested_theme in {"music", "counterculture"} else "v1"
        )
        self.theme = "music" if storyboard_version == "v2" else "history"
        self.loop = bool(loop)
        self.route_version += 1
        self.narrated_poi_ids.clear()
        self._build_route(storyboard_version)
        self._set_preference_deltas(previous_preferences)
        self._seed_podcast()
        return (
            f"I planned a {self.duration_minutes}-minute {self.route_label} walk "
            f"with {len(self.points_of_interest)} stops."
        )

    def revise(
        self,
        *,
        theme: str | None = None,
        interests: Sequence[str] | None = None,
        topic: str | None = None,
        memory: str | None = None,
        deviation: str | None = None,
        insert_nearby_food: bool = False,
        current_location: dict[str, float] | None = None,
        reroute_if_needed: bool = True,
    ) -> str:
        previous_preferences = tuple(self.preferences)
        requested = " ".join(
            value.lower()
            for value in (theme, topic, memory, deviation)
            if isinstance(value, str)
        )
        if interests:
            requested = (
                f"{requested} {' '.join(str(value).lower() for value in interests)}"
            )
        if insert_nearby_food or any(
            phrase in requested
            for phrase in ("nearby food", "food stop", "eat", "lunch")
        ):
            storyboard_version = "v4"
        elif any(
            phrase in requested for phrase in ("deviation", "berwick", "wrong turn")
        ):
            storyboard_version = "v3b"
        elif any(phrase in requested for phrase in ("mural", "memory", "really like")):
            storyboard_version = "v3a"
        elif any(phrase in requested for phrase in ("music", "counterculture", "jazz")):
            storyboard_version = "v2"
        else:
            storyboard_version = "v1"

        self.theme = "music" if storyboard_version != "v1" else "history"
        if reroute_if_needed:
            self.route_version += 1
            origin = current_location or self._latest_search_origin()
            self._build_route(
                storyboard_version,
                search_origin=origin if storyboard_version != "v1" else None,
                deviation=(
                    "via Berwick Street"
                    if storyboard_version == "v3b"
                    else "nearby food insertion"
                    if storyboard_version == "v4"
                    else None
                ),
            )
            self._set_preference_deltas(previous_preferences)
            if storyboard_version == "v3a":
                self.memories.append(
                    {
                        "place_id": "spirit-of-soho-mural",
                        "place": "Spirit of Soho Mural",
                        "reaction": memory or "I really like this",
                    }
                )
        self._seed_podcast()
        if storyboard_version == "v2":
            origin_text = " around your current location" if self.search_origin else ""
            return (
                "I switched the route to music and counterculture"
                f"{origin_text}: Old Compton Street, Ronnie Scott's, "
                "the Spirit of Soho Mural, and Soho Square."
            )
        if storyboard_version == "v3a":
            return "I remembered that you liked the Spirit of Soho Mural and raised public art, cultural history, and murals in your taste profile. The route stays unchanged."
        if storyboard_version == "v3b":
            return "I detected the Berwick Street deviation and continued without backtracking, keeping the arrival time and interest fit on target."
        if storyboard_version == "v4":
            return "I added a nearby food stop where the detour is feasible, then rejoined the Soho route."
        return f"I restored the Chinatown history and food route with {len(self.points_of_interest)} stops."

    def apply_route_deviation(
        self,
        *,
        current_location: dict[str, float] | None,
        distance_from_route_m: float,
        heading_deg: float | None = None,
        reason: str | None = None,
    ) -> str:
        """Commit the deterministic fake route chosen for an automatic deviation."""

        previous_preferences = tuple(self.preferences)
        if current_location is not None:
            self.latest_location = dict(current_location)
        origin = current_location or self._latest_search_origin()
        self.route_version += 1
        self.theme = "music"
        self._build_route(
            "v3b",
            search_origin=origin,
            deviation="via Berwick Street",
        )
        self._set_preference_deltas(previous_preferences)
        self.deviation_distance_m = distance_from_route_m
        self.deviation_heading_deg = heading_deg
        self.deviation_reason = reason or "wrong direction"
        self._seed_podcast()
        return (
            "I detected the route deviation and continued via Berwick Street "
            "without backtracking, keeping the arrival time and interest fit on target."
        )

    def _latest_search_origin(self) -> dict[str, float] | None:
        if self.latest_location is None:
            return None
        return {
            "latitude": float(self.latest_location["latitude"]),
            "longitude": float(self.latest_location["longitude"]),
        }

    def route_event(self) -> dict[str, Any]:
        return {
            "type": "route_update",
            "walk_id": self.walk_id,
            "route_version": self.route_version,
            "storyboard_version": self.storyboard_version,
            "route_label": self.route_label,
            "theme": self.theme,
            "duration_minutes": self.duration_minutes,
            "distance_m": self._route_distance_m(),
            "preferences": list(self.preferences),
            "preference_deltas": self.preference_deltas,
            "search_origin": self.search_origin,
            "current_location": self.latest_location,
            "deviation": self.deviation,
            "deviation_distance_m": self.deviation_distance_m,
            "deviation_heading_deg": self.deviation_heading_deg,
            "deviation_reason": self.deviation_reason,
            "memories": list(self.memories),
            "geometry": [
                {"latitude": latitude, "longitude": longitude}
                for latitude, longitude in self.geometry
            ],
            # polyline is intentionally represented as the same lightweight
            # geometry in the fake protocol; production can replace it with an
            # encoded polyline without changing the browser contract.
            "polyline": [
                {"latitude": latitude, "longitude": longitude}
                for latitude, longitude in self.geometry
            ],
            "points_of_interest": [
                {
                    "id": poi.id,
                    "name": poi.name,
                    "subtitle": poi.subtitle,
                    "latitude": poi.latitude,
                    "longitude": poi.longitude,
                    "story": poi.story,
                    "kind": poi.kind,
                    "visited": poi.id in self.narrated_poi_ids,
                }
                for poi in self.points_of_interest
            ],
        }

    def _route_distance_m(self) -> int:
        return round(
            sum(
                _distance_m(*start, *end)
                for start, end in zip(self.geometry, self.geometry[1:])
            )
        )

    def update_location(
        self,
        *,
        seq: int,
        timestamp: str,
        latitude: float,
        longitude: float,
        accuracy_m: float,
    ) -> tuple[dict[str, Any], SystemPromptPart | None]:
        self.last_location_seq = seq
        self.latest_location = {
            "seq": seq,
            "timestamp": timestamp,
            "latitude": latitude,
            "longitude": longitude,
            "accuracy_m": accuracy_m,
        }
        nearest = min(
            self.points_of_interest,
            key=lambda poi: _distance_m(
                latitude, longitude, poi.latitude, poi.longitude
            ),
            default=None,
        )
        nearest_distance = (
            round(_distance_m(latitude, longitude, nearest.latitude, nearest.longitude))
            if nearest
            else None
        )
        nearest_index = (
            self.points_of_interest.index(nearest) if nearest is not None else None
        )
        narration: SystemPromptPart | None = None
        anchor_changed = (
            nearest is not None
            and nearest_distance is not None
            and nearest_distance <= 80
            and nearest.id != self.current_stop_id
            and (
                self.current_stop_index is None
                or nearest_index is not None
                and nearest_index > self.current_stop_index
            )
        )
        if anchor_changed and nearest is not None:
            self._set_anchor(nearest)
            self.narrated_poi_ids.add(nearest.id)
            self.podcast_active = True
            self.podcast_status = "playing"
            narration = SystemPromptPart(
                f"We have reached {nearest.name}. Briefly acknowledge the change of place, "
                f"then ease into this connected story beat: {nearest.story}"
            )
            if self.scheduled_chapter_id is None:
                self.scheduled_chapter_id = nearest.id
                self.scheduled_prompt_kind = "transition"
            else:
                self.queued_transition_id = nearest.id
        progress = {
            "type": "walk_progress",
            "walk_id": self.walk_id,
            "route_version": self.route_version,
            "seq": seq,
            "latitude": latitude,
            "longitude": longitude,
            "accuracy_m": accuracy_m,
            "nearest_poi_id": nearest.id if nearest else None,
            "nearest_poi_distance_m": nearest_distance,
            "current_stop_id": self.current_stop_id,
            "current_stop_index": self.current_stop_index,
            "narration_pending": narration is not None,
            "visited_poi_ids": sorted(self.narrated_poi_ids),
        }
        return progress, narration


@dataclass
class WalkSessionDeps:
    """Mutable state and event sink scoped to one realtime WebSocket."""

    state: WalkSessionState = field(default_factory=WalkSessionState)
    event_sink: EventSink | None = None
    emitted_events: list[dict[str, Any]] = field(default_factory=list)

    async def emit(self, event: dict[str, Any]) -> None:
        self.emitted_events.append(event)
        if self.event_sink is not None:
            await self.event_sink(event)

    async def plan_walk(
        self,
        *,
        duration_minutes: int = 25,
        theme: str | None = None,
        interests: Sequence[str] | None = None,
        loop: bool = True,
    ) -> str:
        summary = self.state.plan(
            duration_minutes=duration_minutes,
            theme=theme,
            interests=interests,
            loop=loop,
        )
        await self.emit(self.state.route_event())
        await self.emit(self.state.podcast_event())
        return summary

    async def revise_walk(
        self,
        *,
        theme: str | None = None,
        interests: Sequence[str] | None = None,
        topic: str | None = None,
        memory: str | None = None,
        deviation: str | None = None,
        insert_nearby_food: bool = False,
        current_location: dict[str, float] | None = None,
        reroute_if_needed: bool = True,
    ) -> str:
        summary = self.state.revise(
            theme=theme,
            interests=interests,
            topic=topic,
            memory=memory,
            deviation=deviation,
            insert_nearby_food=insert_nearby_food,
            current_location=current_location,
            reroute_if_needed=reroute_if_needed,
        )
        await self.emit(self.state.route_event())
        await self.emit(self.state.podcast_event())
        return summary

    def location_from_control(
        self, control: dict[str, Any]
    ) -> tuple[dict[str, Any], SystemPromptPart | None]:
        seq = control.get("seq")
        timestamp = control.get("timestamp")
        latitude = control.get("latitude")
        longitude = control.get("longitude")
        accuracy_m = control.get("accuracy_m")
        if isinstance(seq, bool) or not isinstance(seq, int) or seq < 0:
            raise ValueError("location_update.seq must be a non-negative integer.")
        if seq <= self.state.last_location_seq:
            raise ValueError(
                "location_update.seq must be greater than the last location sequence."
            )
        if not isinstance(timestamp, str) or not timestamp.strip():
            raise ValueError("location_update.timestamp must be a non-empty string.")
        try:
            datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        except ValueError:
            raise ValueError(
                "location_update.timestamp must be an ISO-8601 timestamp."
            ) from None
        if (
            isinstance(latitude, bool)
            or not isinstance(latitude, (int, float))
            or not math.isfinite(latitude)
            or not -90 <= latitude <= 90
        ):
            raise ValueError("location_update.latitude must be between -90 and 90.")
        if (
            isinstance(longitude, bool)
            or not isinstance(longitude, (int, float))
            or not math.isfinite(longitude)
            or not -180 <= longitude <= 180
        ):
            raise ValueError("location_update.longitude must be between -180 and 180.")
        if (
            isinstance(accuracy_m, bool)
            or not isinstance(accuracy_m, (int, float))
            or not math.isfinite(accuracy_m)
            or accuracy_m < 0
        ):
            raise ValueError(
                "location_update.accuracy_m must be a non-negative number."
            )
        return self.state.update_location(
            seq=seq,
            timestamp=timestamp,
            latitude=float(latitude),
            longitude=float(longitude),
            accuracy_m=float(accuracy_m),
        )

    def _deviation_location_from_control(
        self, control: dict[str, Any]
    ) -> dict[str, float] | None:
        candidate = control.get("current_location")
        if candidate is None:
            candidate = control.get("location")
        if candidate is None and ("latitude" in control or "longitude" in control):
            candidate = {
                "latitude": control.get("latitude"),
                "longitude": control.get("longitude"),
                "accuracy_m": control.get("accuracy_m"),
            }
        if candidate is None:
            if self.state.latest_location is None:
                return None
            candidate = self.state.latest_location
        if not isinstance(candidate, dict):
            raise ValueError(
                "route_deviation.current_location must be an object with latitude and longitude."
            )

        latitude = candidate.get("latitude")
        longitude = candidate.get("longitude")
        if (
            isinstance(latitude, bool)
            or not isinstance(latitude, (int, float))
            or not math.isfinite(latitude)
            or not -90 <= latitude <= 90
        ):
            raise ValueError(
                "route_deviation.current_location.latitude must be between -90 and 90."
            )
        if (
            isinstance(longitude, bool)
            or not isinstance(longitude, (int, float))
            or not math.isfinite(longitude)
            or not -180 <= longitude <= 180
        ):
            raise ValueError(
                "route_deviation.current_location.longitude must be between -180 and 180."
            )
        accuracy_m = candidate.get("accuracy_m")
        if accuracy_m is not None and (
            isinstance(accuracy_m, bool)
            or not isinstance(accuracy_m, (int, float))
            or not math.isfinite(accuracy_m)
            or accuracy_m < 0
        ):
            raise ValueError(
                "route_deviation.current_location.accuracy_m must be a non-negative number."
            )
        location = {
            "latitude": float(latitude),
            "longitude": float(longitude),
        }
        if accuracy_m is not None:
            location["accuracy_m"] = float(accuracy_m)
        return location

    async def route_deviation_from_control(
        self, control: dict[str, Any]
    ) -> tuple[dict[str, Any], SystemPromptPart]:
        """Validate and commit an app-reported route deviation."""

        route_version = control.get("route_version")
        if isinstance(route_version, bool) or not isinstance(route_version, int):
            raise ValueError(
                "route_deviation.route_version must be a non-negative integer."
            )
        if route_version < 0:
            raise ValueError(
                "route_deviation.route_version must be a non-negative integer."
            )
        if route_version != self.state.route_version:
            raise RouteVersionMismatchError(
                "route_deviation.route_version does not match the current route version "
                f"({self.state.route_version}). Refresh the route before retrying."
            )

        distance_from_route_m = control.get("distance_from_route_m")
        if distance_from_route_m is None:
            distance_from_route_m = control.get("distance_m")
        if (
            isinstance(distance_from_route_m, bool)
            or not isinstance(distance_from_route_m, (int, float))
            or not math.isfinite(distance_from_route_m)
            or distance_from_route_m < 0
        ):
            raise ValueError(
                "route_deviation.distance_from_route_m must be a non-negative number."
            )

        heading_deg = control.get("heading_deg")
        if heading_deg is not None and (
            isinstance(heading_deg, bool)
            or not isinstance(heading_deg, (int, float))
            or not math.isfinite(heading_deg)
            or not 0 <= heading_deg <= 360
        ):
            raise ValueError("route_deviation.heading_deg must be between 0 and 360.")
        reason = control.get("reason")
        if reason is not None and (not isinstance(reason, str) or not reason.strip()):
            raise ValueError("route_deviation.reason must be a non-empty string.")
        location = self._deviation_location_from_control(control)
        summary = self.state.apply_route_deviation(
            current_location=location,
            distance_from_route_m=float(distance_from_route_m),
            heading_deg=float(heading_deg) if heading_deg is not None else None,
            reason=reason.strip() if isinstance(reason, str) else None,
        )
        await self.emit(self.state.route_event())
        await self.emit(self.state.podcast_event())
        location_text = (
            f"latitude {location['latitude']:.5f}, longitude {location['longitude']:.5f}"
            if location is not None
            else "the latest known location"
        )
        prompt = SystemPromptPart(
            "The app reported a route deviation and the route service committed the "
            "new fake route via Berwick Street. "
            f"The walker is at {location_text}, {float(distance_from_route_m):.0f} metres "
            "from the previous route. Explain the reroute briefly, mention that it "
            "avoids backtracking, and continue the podcast from the walker's current place. "
            "Do not ask for permission and do not invent live routing details."
        )
        result = {
            "summary": summary,
            "route_version": self.state.route_version,
            "distance_from_route_m": float(distance_from_route_m),
            "current_location": self.state.latest_location,
        }
        return result, prompt
