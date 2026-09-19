import 'package:flutter_test/flutter_test.dart';
import 'package:gradient_gemini_live/live/live_conversation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts in setup state when Firebase configuration is missing', () {
    final controller = LiveConversationController(configured: false);

    expect(controller.status, LiveConversationStatus.setupRequired);
    expect(controller.isLive, isFalse);
    expect(controller.transcripts, isEmpty);
  });

  test('does not attempt a connection from the setup state', () async {
    var connectAttempts = 0;
    final controller = LiveConversationController(
      configured: false,
      connect: () async {
        connectAttempts++;
        throw StateError('connection should not be attempted');
      },
    );

    await controller.start();

    expect(connectAttempts, 0);
    expect(controller.status, LiveConversationStatus.setupRequired);
  });

  test(
    'enters error on denied microphone permission without connecting',
    () async {
      var connectAttempts = 0;
      final controller = LiveConversationController(
        connect: () async {
          connectAttempts++;
          throw StateError('connection should not be attempted');
        },
        requestMicrophonePermission: () async => false,
      );

      await controller.start();

      expect(connectAttempts, 0);
      expect(controller.status, LiveConversationStatus.error);
      expect(
        controller.errorMessage,
        contains('Microphone access is required'),
      );
    },
  );
}
