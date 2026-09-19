# CLAUDE.md

Gradient — hackathon prototype (team Gradient). iOS-only Flutter app that
generates a personal walking tour as a two-host podcast and walks you to each
stop. Demo only: no login, no backend, not for the App Store (TestFlight at most).
Structure and visual style are ported from `../Repos_Flashforce/FrontendFlashForce`,
deliberately simplified.

## Commands
- `flutter pub get` — install deps
- `flutter analyze` / `flutter test` — lint / tests
- `flutter run` — run on a connected iPhone or simulator (maps + TTS need iOS)
- Full-loop smoke test with screenshots (booted simulator; set a Soho location first with
  `xcrun simctl location <udid> set 51.5152,-0.1322`):
  `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/walkthrough_test.dart -d <udid>`
  → screenshots land in `build/screenshots/`.
- go_router is pinned to ^17: v18 pulls in `material_ui`, which doesn't compile on Flutter 3.44.
- Voice-call prototype against the team relay (`Gradient-hack/gradient`, `gemini_proxy.py`):
  open “Voice test (dev)” on the welcome screen. Pass the relay URL at build time (the
  trycloudflare host changes on every backend restart; the screen also lets you edit it):
  `flutter run -d <udid> --dart-define=PYDANTIC_WS_URL=wss://<host>/gemini/voice`.
  Real audio needs a physical iPhone: `audio_io` aborts on the simulator when enabling voice
  processing, so on the simulator the screen connects signalling-only. Smoke test:
  `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/voice_call_test.dart -d <udid> --dart-define=PYDANTIC_WS_URL=…`
- `flutter build ipa` — for TestFlight (needs signing set up in Xcode)

## Architecture
Feature-first, Riverpod (hand-written Notifiers, no codegen), go_router (flat, no guards).

- `core/theme` — palette (`AppColors`, incl. the brand gradient) and `AppTheme` (Bricolage Grotesque headings via google_fonts, stadium buttons, bordered white cards).
- `core/widgets` — `PrimaryButton` (flat or gradient), `GlassNavBar`, brand bits (`BrandWordmark`, `GradientText`, `HostAvatar`, `AppCard`, `SectionLabel`).
- `features/tour` — `Tour`/`TourStop`/`ScriptLine`/`QuizQuestion` models, `TourGenerator` interface with `MockTourGenerator` + hand-written Soho content in `demo_tours.dart`, create/generating/preview screens, `TourMap` (apple_maps_flutter).
- `features/walk` — `WalkController` state machine (navigating → listening → quiz → photo → next / finished), `Narrator` (flutter_tts, two iOS voices), location stream + geo helpers, `WalkScreen`.
- `features/keepsake` — `Keepsake` model, SharedPreferences store, summary + list screens.

## Conventions
- Keep it simple: this is a demo. Prefer plain Dart classes over codegen.
- To plug in a real backend, implement `TourGenerator` and override `tourGeneratorProvider`.
- Content is English only; no l10n.
- Demo tip: the walk auto-arrives within 35 m of a stop, but the “I’m here” button always works, so the full loop can be demoed anywhere (including the simulator).
