import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/features/voice/data/relay_protocol.dart';
import 'package:gradient/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Smoke test for the Gemini voice relay: open the dev screen, connect,
/// reach "Live", hang up. Verifies the socket handshake and audio start on
/// device; it can't judge audio quality, do that by ear on a real iPhone.
///
/// Run on a booted iOS simulator (grant the mic first):
///   xcrun simctl privacy `<udid>` grant microphone com.gradient.gradient
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/voice_call_test.dart -d `<udid>` \
///     --dart-define=PYDANTIC_WS_URL=wss://`<host>`/gemini/voice
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 1000]) =>
      t.pump(Duration(milliseconds: ms));

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot(name);
  }

  Future<bool> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 2; i++) {
      if (f.evaluate().isNotEmpty) return true;
      await settle(t, 500);
    }
    return false;
  }

  testWidgets('voice call connects and hangs up', (tester) async {
    unawaited(app.main());
    await settle(tester, 2500);

    await tester.tap(find.text('Voice test (dev)'));
    await settle(tester, 1500);
    await shot(tester, 'v01_voice_idle');

    // Point at the relay from the build-time define (persisted URL may be stale).
    await tester.enterText(find.byType(TextField), kDefaultRelayUrl);
    await settle(tester, 300);
    await tester.tap(find.text('Start call'));
    await settle(tester, 1000);

    final live = await waitFor(tester, find.textContaining('Live ·'));
    await shot(tester, live ? 'v02_voice_live' : 'v02_voice_failed');
    if (!live) {
      // Surface the on-screen error in the test output.
      await tester.tap(find.byTooltip('Connection log'));
      await settle(tester, 500);
      await shot(tester, 'v02b_voice_log');
    }
    expect(
      live,
      isTrue,
      reason: 'expected the call to reach Live (see screenshots)',
    );

    // Hold the line briefly so the relay/Gemini session is exercised.
    await settle(tester, 6000);
    await tester.tap(find.byTooltip('Connection log'));
    await settle(tester, 500);
    await shot(tester, 'v03_voice_live_log');

    await tester.tap(find.text('End call'));
    await settle(tester, 1500);
    expect(find.text('Idle'), findsOneWidget);
    await shot(tester, 'v04_voice_ended');
  });
}
