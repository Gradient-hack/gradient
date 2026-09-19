# Gemini Live Flutter demo

This app is a small, local Flutter client for Gemini Live. It streams 16 kHz
PCM microphone audio to Firebase AI Logic and plays the model's 24 kHz audio
response as it arrives. The demo also includes a `get_current_time` function tool so
you can test a tool call inside a live voice session.

The live model used by the demo is
`gemini-2.5-flash-native-audio-preview-12-2025`. You can override it with
`--dart-define=GEMINI_LIVE_MODEL=<model-id>` when Firebase publishes a newer
compatible Live model.

## Firebase setup

1. Create or select a Firebase project in the [Firebase console](https://console.firebase.google.com/).
2. In **Build > AI Logic**, enable the Gemini Developer API (or configure the
   provider and billing required by your project).
3. Add an Android app and/or an iOS app to the project. Copy each app's
   Firebase application ID, along with the project's API key, project ID, and
   Cloud Messaging sender ID.
4. From this directory, run the app with the values for the platform you are
   testing. Keep the API key restricted to this Firebase project in the Google
   Cloud credentials page.

Android:

```bash
flutter run -d <android-device> \
  --dart-define=FIREBASE_API_KEY=AIza... \
  --dart-define=FIREBASE_PROJECT_ID=my-project \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
  --dart-define=FIREBASE_ANDROID_APP_ID=1:1234567890:android:abcdef
```

iOS:

```bash
flutter run -d <ios-device> \
  --dart-define=FIREBASE_API_KEY=AIza... \
  --dart-define=FIREBASE_PROJECT_ID=my-project \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
  --dart-define=FIREBASE_IOS_APP_ID=1:1234567890:ios:abcdef
```

The app reports a setup state when one of these values is missing. A generated
`firebase_options.dart` from `flutterfire configure` is a good next step for a
real application, but the demo keeps its configuration in `--dart-define`
values so no project credentials need to be committed.

## Run and test

Use a physical device for the meaningful test: microphone capture, speaker
playback, network handoff, and Bluetooth audio routing are not represented by
the desktop or simulator alone. Android needs the microphone permission at
runtime; iOS shows the permission prompt using the description in
`ios/Runner/Info.plist`.

```bash
flutter pub get
flutter test
flutter analyze
```

The first conversation should be short. Ask “What time is it in Tokyo?” to
exercise the function tool, then interrupt the response to check barge-in
behavior. End the call before closing the app so the audio session and live
connection are released.

## Production hardening

The local demo leaves Firebase App Check activation out to avoid requiring
debug-token registration while testing on a personal device. Before shipping,
configure a platform attestation provider and enable enforcement in Firebase.
The dependency graph currently has one separate compatibility workaround:
`audio_io` 0.6.1 declares an older `package:web` constraint, so `pubspec.yaml`
uses a narrow override to the current `package:web` release required by the
Firebase dependencies. That override is unrelated to App Check. Do not treat a
client-side API key as a secret; restrict it in Google Cloud and use the
Firebase security controls appropriate to the deployed app.
