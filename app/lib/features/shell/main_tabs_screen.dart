import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/glass_nav_bar.dart';
import '../keepsake/presentation/keepsakes_screen.dart';
import '../tour/presentation/screens/create_walk_screen.dart';

final tabIndexProvider = NotifierProvider<_TabIndex, int>(_TabIndex.new);

class _TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

/// Two tabs: make a walk, look back at walks.
class MainTabsScreen extends ConsumerWidget {
  const MainTabsScreen({super.key});

  static const _tabs = [CreateWalkScreen(), KeepsakesScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: GlassNavBar(
        selectedIndex: index,
        onSelected: (i) => ref.read(tabIndexProvider.notifier).select(i),
        items: const [
          GlassNavItem(icon: Icons.explore_rounded, label: 'New walk'),
          GlassNavItem(icon: Icons.photo_library_rounded, label: 'Keepsakes'),
        ],
      ),
    );
  }
}
