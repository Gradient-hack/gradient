import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../tour/presentation/widgets/tour_map.dart';
import '../../walk/providers/walk_controller.dart';
import '../domain/keepsake.dart';
import '../providers/keepsake_providers.dart';

/// Shown right after a walk finishes. Builds the keepsake from the walk
/// state, saves it, and renders it.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  Keepsake? _keepsake;

  @override
  void initState() {
    super.initState();
    final walk = ref.read(walkControllerProvider);
    if (walk != null) {
      _keepsake = Keepsake.fromWalk(walk);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(keepsakesProvider.notifier).save(_keepsake!);
        ref.read(walkControllerProvider.notifier).end();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _keepsake;
    if (k == null) {
      return Scaffold(
        body: Center(
          child: TextButton(onPressed: () => context.go(Routes.home), child: const Text('Back home')),
        ),
      );
    }
    return KeepsakeView(
      keepsake: k,
      footer: PrimaryButton(
        label: 'Done',
        gradient: true,
        onPressed: () => context.go(Routes.home),
      ),
    );
  }
}

/// Route map, photo strip, score, sources. Shared by the fresh summary and
/// the saved-keepsake detail.
class KeepsakeView extends StatelessWidget {
  const KeepsakeView({required this.keepsake, super.key, this.footer, this.showBack = false});

  final Keepsake keepsake;
  final Widget? footer;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final k = keepsake;
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final mins = k.duration.inMinutes;

    return Scaffold(
      appBar: showBack ? AppBar(title: const Text('Keepsake')) : null,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (!showBack) SizedBox(height: MediaQuery.viewPaddingOf(context).top + 8),
                const SectionLabel('Your keepsake'),
                const SizedBox(height: 4),
                GradientText(k.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  '${k.neighbourhood} · ${_date(k.startedAt)} · ${mins < 1 ? '<1' : mins} min',
                  style: const TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 16),

                // Route
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 200,
                    child: IgnorePointer(
                      child: TourMap(
                        interactive: false,
                        padding: 40,
                        pins: [
                          for (final s in k.stops)
                            MapStopPin(id: s.name, lat: s.lat, lng: s.lng, title: s.name, done: true),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Score row
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.quiz_rounded,
                        value: '${k.correctCount}/${k.answeredCount}',
                        label: 'answers right',
                        color: AppColors.mint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.place_rounded,
                        value: '${k.stops.length}',
                        label: 'stops',
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.photo_camera_rounded,
                        value: '${k.photoPaths.length}',
                        label: 'photos',
                        color: AppColors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Photo strip
                const SectionLabel('Photo strip'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 150,
                  child: k.stops.every((s) => s.photoPath == null)
                      ? const AppCard(
                          child: Center(
                            child: Text('No photos this time.', style: TextStyle(color: AppColors.gray)),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: k.stops.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, i) => _PhotoTile(stop: k.stops[i], index: i),
                        ),
                ),
                const SizedBox(height: 24),

                // Stops + answers
                const SectionLabel('Stops'),
                const SizedBox(height: 10),
                for (final (i, s) in k.stops.indexed) ...[
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Text('${i + 1}', style: theme.textTheme.titleLarge?.copyWith(color: AppColors.gray)),
                        const SizedBox(width: 14),
                        Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (s.correct != null)
                          Icon(
                            s.correct! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: s.correct! ? AppColors.mint : AppColors.accent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),

                // Sources
                const SectionLabel('Sources'),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (final src in k.sources)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded, size: 18, color: AppColors.primary),
                          title: Text(src.title, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            src.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.gray),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (footer != null)
            Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottom), child: footer),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, required this.color});
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          // FlashForce-style tinted icon disc.
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.gray)),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.stop, required this.index});
  final KeepsakeStop stop;
  final int index;

  @override
  Widget build(BuildContext context) {
    final path = stop.photoPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null && File(path).existsSync())
              Image.file(File(path), fit: BoxFit.cover)
            else
              const DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.softGradient),
                child: Center(child: Icon(Icons.no_photography_rounded, color: AppColors.gray)),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  ),
                ),
                child: Text(
                  '${index + 1}. ${stop.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
