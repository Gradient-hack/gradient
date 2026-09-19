import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand.dart';
import '../../../../core/widgets/glass_nav_bar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../walk/providers/location_provider.dart';
import '../../domain/tour.dart';
import '../../providers/tour_providers.dart';

/// The three inputs: interests, duration, tone.
class CreateWalkScreen extends ConsumerWidget {
  const CreateWalkScreen({super.key});

  static const _durations = [15, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = ref.watch(tourRequestProvider);
    final notifier = ref.read(tourRequestProvider.notifier);
    final position = ref.watch(positionStreamProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, GlassNavBar.clearanceFor(context)),
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const BrandWordmark(fontSize: 32),
                  const Spacer(),
                  _LocationChip(
                    label: position == null ? 'Locating…' : 'Location on',
                    live: position != null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Make me a walk', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 4),
          const Text(
            'Pick what you’re curious about. Mara and Theo write the show and the route on the spot.',
            style: TextStyle(color: AppColors.gray, height: 1.4),
          ),
          const SizedBox(height: 28),

          const SectionLabel('What are you curious about?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (n, i) in Interest.values.indexed)
                FilterChip(
                  label: Text('${i.emoji}  ${i.label}'),
                  selected: req.interests.contains(i),
                  onSelected: (_) => notifier.toggleInterest(i),
                  // Each interest gets its own accent hue when selected.
                  selectedColor: AppColors.tags[n % AppColors.tags.length].withValues(alpha: 0.16),
                  side: BorderSide(
                    color: req.interests.contains(i)
                        ? AppColors.tags[n % AppColors.tags.length]
                        : AppColors.border,
                    width: req.interests.contains(i) ? 1.5 : 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),

          const SectionLabel('How long have you got?'),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (final d in _durations)
                  Expanded(
                    child: _Segment(
                      label: '$d min',
                      selected: req.durationMinutes == d,
                      onTap: () => notifier.setDuration(d),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          const SectionLabel('How should the hosts sound?'),
          const SizedBox(height: 12),
          for (final t in Tone.values) ...[
            _ToneTile(
              tone: t,
              selected: req.tone == t,
              onTap: () => notifier.setTone(t),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),

          PrimaryButton(
            label: 'Generate my walk',
            gradient: true,
            icon: Icons.auto_awesome_rounded,
            onPressed: req.interests.isEmpty
                ? null
                : () {
                    if (position != null) {
                      notifier.setLocation(position.latitude, position.longitude);
                    }
                    context.push(Routes.generating);
                  },
          ),
        ],
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.label, required this.live});
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            live ? Icons.my_location_rounded : Icons.location_searching_rounded,
            size: 14,
            color: live ? AppColors.mint : AppColors.gray,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.brandGradient : null,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _ToneTile extends StatelessWidget {
  const _ToneTile({required this.tone, required this.selected, required this.onTap});
  final Tone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tone.label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                    const SizedBox(height: 2),
                    Text(tone.description, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
