import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand.dart';
import '../../providers/tour_providers.dart';

/// "Writing the show" loader. Kicks off generation and moves on to the
/// preview when the tour is ready.
class GeneratingScreen extends ConsumerStatefulWidget {
  const GeneratingScreen({super.key});

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen> {
  static const _steps = [
    'Reading the streets around you…',
    'Digging up the good stories…',
    'Plotting a route you can actually follow…',
    'Mara and Theo are arguing about the intro…',
    'Checking the sources…',
  ];

  int _step = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) setState(() => _step = (_step + 1) % _steps.length);
    });
    unawaited(_generate());
  }

  Future<void> _generate() async {
    try {
      await ref.read(currentTourProvider.notifier).generate();
      if (mounted) context.pushReplacement(Routes.preview);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.softGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PulsingHosts(),
                const SizedBox(height: 40),
                GradientText(
                  'Writing your walk',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _error ?? _steps[_step],
                    key: ValueKey(_error ?? _step),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error == null ? AppColors.gray : AppColors.error,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  TextButton(onPressed: () => context.pop(), child: const Text('Back')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingHosts extends StatefulWidget {
  const _PulsingHosts();

  @override
  State<_PulsingHosts> createState() => _PulsingHostsState();
}

class _PulsingHostsState extends State<_PulsingHosts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = _c.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HostAvatar(initial: 'M', color: AppColors.hostA, size: 64 + 8 * a, speaking: a > 0.5),
            const SizedBox(width: 24),
            HostAvatar(initial: 'T', color: AppColors.hostB, size: 72 - 8 * a, speaking: a <= 0.5),
          ],
        );
      },
    );
  }
}
