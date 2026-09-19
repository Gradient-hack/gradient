import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../walk/providers/walk_controller.dart';
import '../../providers/tour_providers.dart';
import '../widgets/tour_map.dart';

/// Map + stop list for the generated tour, and the "Start walking" CTA.
class RoutePreviewScreen extends ConsumerWidget {
  const RoutePreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(currentTourProvider);
    if (tour == null) {
      return const Scaffold(body: Center(child: Text('No tour yet.')));
    }
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TourMap(
              pins: [
                for (final s in tour.stops)
                  MapStopPin(id: s.id, lat: s.lat, lng: s.lng, title: s.name),
              ],
              padding: 80,
            ),
          ),
          // Back button
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 12,
            child: _RoundButton(
              icon: Icons.arrow_back_rounded,
              onTap: () {
                ref.read(currentTourProvider.notifier).clear();
                context.go(Routes.home);
              },
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scroll) => Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GradientText(tour.title, style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(tour.subtitle, style: const TextStyle(color: AppColors.gray)),
                        const SizedBox(height: 16),
                        const _HostsLine(),
                        const SizedBox(height: 20),
                        const SectionLabel('Your stops'),
                        const SizedBox(height: 10),
                        for (final (i, s) in tour.stops.indexed) ...[
                          AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                _NumberBadge(i + 1),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style: theme.textTheme.titleLarge?.copyWith(fontSize: 17),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.directionsHint,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppColors.gray, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
                    child: PrimaryButton(
                      label: 'Start walking',
                      gradient: true,
                      icon: Icons.directions_walk_rounded,
                      onPressed: () {
                        ref.read(walkControllerProvider.notifier).start(tour);
                        context.pushReplacement(Routes.walk);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostsLine extends StatelessWidget {
  const _HostsLine();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        HostAvatar(initial: 'M', color: AppColors.hostA, size: 30),
        SizedBox(width: 6),
        HostAvatar(initial: 'T', color: AppColors.hostB, size: 30),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Hosted by Mara & Theo. They’ll pause to quiz you at every stop.',
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: AppColors.text)),
      ),
    );
  }
}
