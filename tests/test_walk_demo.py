from __future__ import annotations

import unittest

from walk_demo import WalkSessionDeps


class AgentToolSurfaceTest(unittest.TestCase):
    def test_model_gets_specific_intent_tools(self) -> None:
        import main

        names = set(main.agent._function_toolset.tools)
        self.assertTrue(
            {
                "plan_walk",
                "change_topic",
                "remember_place",
                "handle_route_deviation",
                "find_nearby_food",
                "get_walk_status",
            }.issubset(names)
        )
        self.assertNotIn("revise_walk", names)


class WalkSessionStateTest(unittest.IsolatedAsyncioTestCase):
    async def test_chinatown_storyboard_v1_is_the_default_route(self) -> None:
        deps = WalkSessionDeps()

        await deps.plan_walk()

        self.assertEqual(deps.state.duration_minutes, 25)
        self.assertEqual(deps.state.storyboard_version, "v1")
        self.assertEqual(
            [poi.name for poi in deps.state.points_of_interest],
            [
                "Chinatown Gate",
                "Gerrard Street",
                "St Anne's Soho",
                "Soho Square",
                "Berwick Street",
            ],
        )
        self.assertEqual(
            deps.state.preferences,
            ["Tudor history", "local history", "Chinese food"],
        )

    async def test_music_topic_revises_around_latest_location(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk()
        deps.location_from_control(
            {
                "seq": 1,
                "timestamp": "2026-09-19T12:00:00Z",
                "latitude": 51.5124,
                "longitude": -0.1320,
                "accuracy_m": 5,
            }
        )

        summary = await deps.revise_walk(topic="Can we talk about music?")

        self.assertIn("music and counterculture", summary)
        self.assertEqual(deps.state.storyboard_version, "v2")
        self.assertEqual(
            [poi.name for poi in deps.state.points_of_interest],
            [
                "Old Compton Street",
                "Ronnie Scott's",
                "Spirit of Soho Mural",
                "Soho Square",
            ],
        )
        self.assertEqual(
            deps.state.search_origin, {"latitude": 51.5124, "longitude": -0.132}
        )
        event = deps.emitted_events[-2]
        self.assertEqual(
            event["preference_deltas"]["added"], ["counterculture", "music"]
        )
        self.assertEqual(
            event["preference_deltas"]["removed"],
            ["Chinese food", "Tudor history", "local history"],
        )

    async def test_memory_deviation_and_food_storyboard_versions(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk()
        await deps.revise_walk(topic="music")

        route_before_memory = [poi.id for poi in deps.state.points_of_interest]
        await deps.revise_walk(memory="I really like this mural")
        self.assertEqual(deps.state.storyboard_version, "v3a")
        self.assertEqual(
            [poi.id for poi in deps.state.points_of_interest], route_before_memory
        )
        self.assertEqual(deps.state.memories[-1]["place"], "Spirit of Soho Mural")
        self.assertIn("public art", deps.state.preferences)

        await deps.revise_walk(deviation="wrong turn via Berwick")
        self.assertEqual(deps.state.storyboard_version, "v3b")
        self.assertEqual(
            [poi.name for poi in deps.state.points_of_interest],
            [
                "Old Compton Street",
                "Spirit of Soho Mural",
                "Berwick Street",
                "Soho Square",
            ],
        )
        self.assertEqual(deps.state.deviation, "via Berwick Street")

        await deps.revise_walk(insert_nearby_food=True)
        self.assertEqual(deps.state.storyboard_version, "v4")
        self.assertIn(
            "Chinatown Food Stop", [poi.name for poi in deps.state.points_of_interest]
        )

    async def test_sessions_have_independent_route_state(self) -> None:
        first = WalkSessionDeps()
        second = WalkSessionDeps()

        await first.plan_walk(duration_minutes=30, theme="music")

        self.assertEqual(first.state.theme, "music")
        self.assertEqual(first.state.duration_minutes, 30)
        self.assertEqual(second.state.theme, "history")
        self.assertNotEqual(first.state.walk_id, second.state.walk_id)

    async def test_plan_and_theme_change_emit_rich_route_updates(self) -> None:
        deps = WalkSessionDeps()

        summary = await deps.plan_walk(duration_minutes=60, interests=["music"])
        self.assertIn("60-minute Soho music", summary)
        self.assertEqual(len(deps.emitted_events), 2)
        event = deps.emitted_events[0]
        self.assertEqual(event["type"], "route_update")
        self.assertEqual(event["theme"], "music")
        self.assertIn("geometry", event)
        self.assertIn("points_of_interest", event)
        self.assertTrue(all(poi["story"] for poi in event["points_of_interest"]))

        summary = await deps.revise_walk(theme="architecture")
        self.assertIn("Chinatown history", summary)
        self.assertEqual(deps.state.route_version, 2)
        self.assertEqual(deps.emitted_events[-2]["theme"], "history")

    async def test_podcast_chapters_sequence_after_turn_completion(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk(duration_minutes=45, theme="architecture")

        first_prompt = deps.state.start_next_chapter()
        first_id = deps.state.scheduled_chapter_id
        self.assertIsNotNone(first_prompt)
        self.assertEqual(deps.state.podcast_status, "playing")

        deps.state.complete_current_chapter()
        second_prompt = deps.state.start_next_chapter()

        self.assertIsNotNone(second_prompt)
        self.assertEqual(first_id, deps.state.scheduled_chapter_id)
        self.assertEqual(first_id, deps.state.current_stop_id)
        self.assertIn("We are at", first_prompt.content)

        progress, transition = deps.location_from_control(
            {
                "seq": 1,
                "timestamp": "2026-09-19T12:00:00Z",
                "latitude": 51.5135,
                "longitude": -0.1329,
                "accuracy_m": 5,
            }
        )
        self.assertEqual(progress["current_stop_id"], "soho-square")
        self.assertIsNotNone(transition)

    async def test_tool_response_completion_starts_first_route_stop(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk(theme="music")

        # A voice-triggered planning tool finishes its own assistant response
        # before the relay has reserved a location-anchored narration beat.
        deps.state.complete_current_chapter()
        prompt = deps.state.start_next_chapter()

        self.assertIsNotNone(prompt)
        self.assertEqual(deps.state.current_stop_id, "old-compton-street")
        self.assertEqual(deps.state.scheduled_chapter_id, "old-compton-street")
        self.assertIn("Stay with this place", prompt.content)

    async def test_interrupted_chapter_resumes_before_following_chapter(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk(theme="music")

        first_prompt = deps.state.start_next_chapter()
        first_id = deps.state.scheduled_chapter_id
        deps.state.interrupt_podcast()
        resumed_prompt = deps.state.start_next_chapter()

        self.assertIsNotNone(first_prompt)
        self.assertIsNotNone(resumed_prompt)
        self.assertEqual(first_id, deps.state.scheduled_chapter_id)
        self.assertNotEqual(first_prompt.content, resumed_prompt.content)
        self.assertIn("We are at", resumed_prompt.content)

    async def test_theme_revision_replaces_stale_future_chapters(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk(theme="architecture")
        deps.state.start_next_chapter()
        old_ids = {poi.id for poi in deps.state.chapter_queue}

        await deps.revise_walk(theme="music")

        new_ids = {poi.id for poi in deps.state.chapter_queue}
        self.assertTrue(new_ids)
        self.assertTrue(
            all(
                poi_id
                in {
                    "old-compton-street",
                    "ronnie-scotts",
                    "spirit-of-soho-mural",
                    "soho-square",
                }
                for poi_id in new_ids
            )
        )
        self.assertTrue(old_ids.isdisjoint(new_ids - {"soho-square"}))
        self.assertIsNone(deps.state.scheduled_chapter_id)

    async def test_location_sequence_must_be_monotonic(self) -> None:
        deps = WalkSessionDeps()
        location = {
            "seq": 1,
            "timestamp": "2026-09-19T12:00:00Z",
            "latitude": 51.5117,
            "longitude": -0.1310,
            "accuracy_m": 5,
        }

        progress, narration = deps.location_from_control(location)
        self.assertEqual(progress["seq"], 1)
        self.assertIsNotNone(narration)
        with self.assertRaisesRegex(ValueError, "greater than"):
            deps.location_from_control(location)

    async def test_poi_narration_is_enqueued_once(self) -> None:
        deps = WalkSessionDeps()
        first, first_narration = deps.location_from_control(
            {
                "seq": 1,
                "timestamp": "2026-09-19T12:00:00Z",
                "latitude": 51.5117,
                "longitude": -0.1310,
                "accuracy_m": 4,
            }
        )
        second, second_narration = deps.location_from_control(
            {
                "seq": 2,
                "timestamp": "2026-09-19T12:00:02Z",
                "latitude": 51.5117,
                "longitude": -0.1310,
                "accuracy_m": 4,
            }
        )

        self.assertIsNotNone(first_narration)
        self.assertIsNone(second_narration)
        self.assertTrue(first["narration_pending"])
        self.assertFalse(second["narration_pending"])
        self.assertEqual(first["visited_poi_ids"], second["visited_poi_ids"])

    async def test_location_does_not_duplicate_active_podcast_chapter(self) -> None:
        deps = WalkSessionDeps()
        await deps.plan_walk(theme="architecture")

        progress, narration = deps.location_from_control(
            {
                "seq": 1,
                "timestamp": "2026-09-19T12:00:00Z",
                "latitude": 51.5117,
                "longitude": -0.1310,
                "accuracy_m": 4,
            }
        )

        self.assertIsNotNone(narration)
        self.assertTrue(progress["narration_pending"])
        self.assertEqual(progress["current_stop_id"], "chinatown-gate")


if __name__ == "__main__":
    unittest.main()
