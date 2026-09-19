import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/primary_button.dart';

/// Landing screen: wordmark, typed taglines (ported from the FlashForce
/// intro), one CTA. No login — this is a demo.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.softGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                const BrandWordmark(fontSize: 56),
                const SizedBox(height: 16),
                const SizedBox(height: 72, child: _TypedTaglines()),
                const Spacer(),
                const _HostsPreview(),
                const SizedBox(height: 32),
                PrimaryButton(
                  label: 'Start a walk',
                  gradient: true,
                  icon: Icons.headphones_rounded,
                  onPressed: () => context.go(Routes.home),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A walking tour, hosted like a podcast.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.gray, fontSize: 14),
                ),
                const SizedBox(height: 8),
                // Dev harness for the live voice backend; not part of the demo flow.
                TextButton.icon(
                  onPressed: () => context.push(Routes.voiceTest),
                  icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                  label: const Text('Voice test (dev)'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.hint,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HostsPreview extends StatelessWidget {
  const _HostsPreview();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HostAvatar(initial: 'M', color: AppColors.hostA, size: 44, speaking: true),
        SizedBox(width: 12),
        Text('Mara & Theo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        SizedBox(width: 12),
        HostAvatar(initial: 'T', color: AppColors.hostB, size: 44),
      ],
    );
  }
}

class _TypedTaglines extends StatefulWidget {
  const _TypedTaglines();

  @override
  State<_TypedTaglines> createState() => _TypedTaglinesState();
}

class _TypedTaglinesState extends State<_TypedTaglines> {
  static const _lines = [
    'Two hosts. One neighbourhood. Your route.',
    'Listen. Look. Answer. Capture. Walk.',
    'Tell it what you like and how long you have.',
  ];

  String _typed = '';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    var i = 0;
    while (!_disposed) {
      final line = _lines[i % _lines.length];
      for (var c = 1; c <= line.length; c++) {
        if (_disposed) return;
        setState(() => _typed = line.substring(0, c));
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          unawaited(HapticFeedback.selectionClick());
        }
        await Future<void>.delayed(const Duration(milliseconds: 45));
      }
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      i++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _typed,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
    );
  }
}
