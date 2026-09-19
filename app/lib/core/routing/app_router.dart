import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/keepsake/presentation/summary_screen.dart';
import '../../features/keepsake/providers/keepsake_providers.dart';
import '../../features/shell/main_tabs_screen.dart';
import '../../features/tour/presentation/screens/generating_screen.dart';
import '../../features/tour/presentation/screens/route_preview_screen.dart';
import '../../features/voice/presentation/voice_test_screen.dart';
import '../../features/walk/presentation/walk_screen.dart';
import '../../features/welcome/welcome_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.welcome,
    routes: [
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const MainTabsScreen()),
      GoRoute(path: Routes.generating, builder: (_, _) => const GeneratingScreen()),
      GoRoute(path: Routes.preview, builder: (_, _) => const RoutePreviewScreen()),
      GoRoute(path: Routes.walk, builder: (_, _) => const WalkScreen()),
      GoRoute(path: Routes.summary, builder: (_, _) => const SummaryScreen()),
      GoRoute(path: Routes.voiceTest, builder: (_, _) => const VoiceTestScreen()),
      GoRoute(
        path: Routes.keepsake,
        builder: (context, state) => _KeepsakeDetail(id: state.pathParameters['id']!),
      ),
    ],
  );
});

class _KeepsakeDetail extends ConsumerWidget {
  const _KeepsakeDetail({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(keepsakesProvider).value?.where((e) => e.id == id).firstOrNull;
    if (k == null) {
      return const Scaffold(body: Center(child: Text('Keepsake not found.')));
    }
    return KeepsakeView(keepsake: k, showBack: true);
  }
}
