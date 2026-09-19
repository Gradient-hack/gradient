import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/glass_nav_bar.dart';
import '../domain/keepsake.dart';
import '../providers/keepsake_providers.dart';

/// List of past walks.
class KeepsakesScreen extends ConsumerWidget {
  const KeepsakesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepsakes = ref.watch(keepsakesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Keepsakes')),
      body: keepsakes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(20, 8, 20, GlassNavBar.clearanceFor(context)),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _KeepsakeCard(
                  keepsake: list[i],
                  onTap: () => context.push(Routes.keepsakePath(list[i].id)),
                ),
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 56, color: AppColors.border),
            const SizedBox(height: 16),
            Text('No walks yet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text(
              'Finish a walk and your route, photos, score and sources land here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepsakeCard extends StatelessWidget {
  const _KeepsakeCard({required this.keepsake, required this.onTap});
  final Keepsake keepsake;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = keepsake;
    final theme = Theme.of(context);
    final cover = k.photoPaths.where((p) => File(p).existsSync()).firstOrNull;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: cover != null
                ? Image.file(File(cover), fit: BoxFit.cover)
                : const DecoratedBox(
                    decoration: BoxDecoration(gradient: AppColors.brandGradient),
                    child: Center(child: Icon(Icons.headphones_rounded, color: Colors.white, size: 36)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '${k.neighbourhood} · ${k.stops.length} stops · ${k.correctCount}/${k.answeredCount} right · ${k.photoPaths.length} photos',
                  style: const TextStyle(color: AppColors.gray, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
