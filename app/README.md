# Gradient

Mobile preview: https://patrick91--gradient-walking-podcast-web.eu-west.modal.run/

**A personal walking tour, hosted as a podcast.** Two hosts talk you through a
neighbourhood while the app walks you to every place they mention.

Tell it where you are, what you're curious about, and how long you've got. It
writes and hosts a walking tour on the spot: two voices chatting about the
streets you're standing on, stitched to a route you can actually follow. The
map keeps you on track between stops, the hosts pause to quiz you on what
you're looking at, and you're nudged to photograph each place as you go. At the
end you get a keepsake: your route, your snaps, the answers you got right, and
the sources behind the stories.

> Hackathon prototype by team Gradient. iOS only, demo only.

## The loop

1. **Create** — pick interests, duration (15/30/45/60 min) and tone.
2. **Generate** — the app writes the show and the route.
3. **Preview** — route on an Apple Map plus the stop list.
4. **Walk** — map follows you; Mara & Theo talk on the way and at each stop.
   Arrive (auto within 35 m, or tap _I'm here_) → listen → answer a question →
   take a photo → continue.
5. **Keepsake** — route, photo strip, trivia score, sources. Saved locally.

## Running

```sh
flutter pub get
flutter run            # iPhone or iOS simulator
flutter test
```

Location, camera and photo-library permissions are declared in
`ios/Runner/Info.plist`. Voices come from the on-device iOS speech
synthesiser (no network needed).

## Status / what's mocked

- Tour content is hand-written for **Soho, London** (`lib/features/tour/data/demo_tours.dart`)
  and assembled by `MockTourGenerator` from your interests + duration. Swap in a
  real generator (LLM script + TTS) by implementing `TourGenerator`.
- Directions are straight-line distance + compass bearing + a written hint per
  stop. No turn-by-turn routing yet.
- The two hosts are two iOS system voices via `flutter_tts`.
