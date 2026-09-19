import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'ui/gemini_live_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = DemoFirebaseOptions.isConfigured;
  if (configured) {
    await Firebase.initializeApp(options: DemoFirebaseOptions.currentPlatform);
  }
  runApp(GeminiLiveApp(configured: configured));
}

class GeminiLiveApp extends StatelessWidget {
  const GeminiLiveApp({required this.configured, super.key});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Live',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: GeminiLiveScreen(configured: configured),
    );
  }
}
