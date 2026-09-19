import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gradient/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Smoke test: taps through the whole loop (create → generate → preview →
/// walk every stop → keepsake) and screenshots each screen.
///
/// Run on a booted iOS simulator:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/walkthrough_test.dart -d `<simulator-udid>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 1200]) =>
      t.pump(Duration(milliseconds: ms));

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await t.tap(f.first);
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot(name);
  }

  testWidgets('full walk loop', (tester) async {
    unawaited(app.main());
    await settle(tester, 2500);
    await shot(tester, '01_welcome');

    await tapText(tester, 'Start a walk');
    await settle(tester, 1500);
    await shot(tester, '02_create');

    // The CTA sits below the fold of a lazy ListView.
    await tester.scrollUntilVisible(
      find.text('Generate my walk'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester, 600);
    await tapText(tester, 'Generate my walk');
    await settle(tester, 800);
    await shot(tester, '03_generating');
    // Mock generator takes ~4 s; wait until the preview CTA shows up.
    for (var i = 0; i < 20 && find.text('Start walking').evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 2000);
    await shot(tester, '04_preview');

    await tapText(tester, 'Start walking');
    await settle(tester, 3000);
    await shot(tester, '05_walk_navigating');

    var stop = 0;
    while (true) {
      // Arrive (button label flips to "You’re here!" once within radius).
      // (If the simulator is parked on the stop, arrival can already have
      // happened automatically — then we're straight in the listening panel.)
      final here = find.byIcon(Icons.place_rounded);
      if (here.evaluate().isNotEmpty) {
        await tester.tap(here);
      }
      await settle(tester, 1800);
      if (stop == 0) await shot(tester, '06_walk_listening');

      await tapText(tester, 'Skip to question');
      await settle(tester, 800);
      if (stop == 0) await shot(tester, '07_walk_quiz');

      await tapText(tester, 'A');
      await settle(tester, 1000);
      if (stop == 0) await shot(tester, '08_walk_photo');

      final finish = find.text('Finish the walk');
      if (finish.evaluate().isNotEmpty) {
        await tester.tap(finish);
        await settle(tester, 2500);
        break;
      }
      await tapText(tester, 'Continue walking');
      await settle(tester, 1000);
      stop++;
      expect(stop, lessThan(12), reason: 'runaway loop');
    }

    await shot(tester, '09_walk_outro');
    await tapText(tester, 'See your keepsake');
    await settle(tester, 3000);
    await shot(tester, '10_summary');

    await tapText(tester, 'Done');
    await settle(tester, 1500);
    await tester.tap(find.byIcon(Icons.photo_library_rounded));
    await settle(tester, 2000);
    await shot(tester, '11_keepsakes');
    expect(find.text('No walks yet'), findsNothing);
  });
}
