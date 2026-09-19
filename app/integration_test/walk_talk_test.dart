import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/features/voice/data/relay_protocol.dart';
import 'package:gradient/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-walk voice call: start a walk, arrive at the first stop, tap the mic,
/// reach Live against the relay, hang up, and land back on the listening
/// panel. On the simulator the call is signalling-only (see DeviceEnv).
///
/// Run on a booted iOS simulator:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/walk_talk_test.dart -d `<udid>` \
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

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await t.tap(f.first);
    await settle(t);
  }

  testWidgets('ask the hosts mid-walk and come back', (tester) async {
    // The walk dials whatever URL was last used; pin it to the build define.
    SharedPreferences.setMockInitialValues({
      'voice_test.relay_url': kDefaultRelayUrl,
      'voice_test.relay_url_default': kDefaultRelayUrl,
    });

    unawaited(app.main());
    await settle(tester, 2500);
    await tapText(tester, 'Start a walk');
    await settle(tester, 1500);
    await tester.scrollUntilVisible(
      find.text('Generate my walk'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester, 600);
    await tapText(tester, 'Generate my walk');
    expect(await waitFor(tester, find.text('Start walking')), isTrue);
    await settle(tester, 1500);
    await tapText(tester, 'Start walking');
    await settle(tester, 2500);

    // Arrive so we're on the listening panel with the story playing.
    await tester.tap(find.byIcon(Icons.place_rounded));
    await settle(tester, 1500);
    expect(find.text('Skip to question'), findsOneWidget);
    await shot(tester, 'w01_listening_with_mic');

    await tester.tap(find.byIcon(Icons.mic_rounded).first);
    await settle(tester, 1000);
    expect(find.text('Ask the hosts'), findsOneWidget);
    await shot(tester, 'w02_calling');

    final live = await waitFor(tester, find.textContaining('Live ·'));
    await shot(tester, live ? 'w03_talk_live' : 'w03_talk_failed');
    expect(live, isTrue, reason: 'expected the in-walk call to reach Live');
    await settle(tester, 3000);

    await tapText(tester, 'Hang up');
    await settle(tester, 1500);
    expect(find.text('Ask the hosts'), findsNothing);
    expect(find.text('Skip to question'), findsOneWidget);
    await shot(tester, 'w04_back_to_story');
  });
}
