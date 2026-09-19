import 'dart:io';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' show LatLng;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../tour/domain/tour.dart';
import '../../tour/presentation/widgets/tour_map.dart';
import '../../voice/providers/voice_call_controller.dart';
import '../domain/walk_state.dart';
import '../providers/location_provider.dart';
import '../providers/walk_controller.dart';

/// The walk itself: map on top, a phase-driven panel below.
class WalkScreen extends ConsumerWidget {
  const WalkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Once the outro is done, hand over to the summary.
    ref.listen(walkControllerProvider, (prev, next) {
      if (next != null &&
          next.phase == WalkPhase.finished &&
          !next.playing &&
          prev?.playing == true) {
        context.pushReplacement(Routes.summary);
      }
    });

    final walk = ref.watch(walkControllerProvider);
    final position = ref.watch(positionStreamProvider).value;

    if (walk == null) {
      return const Scaffold(body: Center(child: Text('No active walk.')));
    }

    final pins = [
      for (final (i, s) in walk.tour.stops.indexed)
        MapStopPin(
          id: s.id,
          lat: s.lat,
          lng: s.lng,
          title: s.name,
          highlighted: i == walk.stopIndex,
          done: i < walk.stopIndex,
        ),
    ];

    final focus = walk.phase == WalkPhase.navigating && position != null
        ? LatLng(position.latitude, position.longitude)
        : LatLng(walk.stop.lat, walk.stop.lng);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TourMap(
                    pins: pins,
                    focus: focus,
                    showUserLocation: true,
                  ),
                ),
                Positioned(
                  top: MediaQuery.viewPaddingOf(context).top + 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _RoundButton(
                        icon: Icons.close_rounded,
                        onTap: () => _confirmQuit(context, ref),
                      ),
                      const Spacer(),
                      _ProgressPill(
                        current: walk.stopIndex + 1,
                        total: walk.tour.stops.length,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: walk.talking
                    ? _TalkPanel(key: const ValueKey('talk'), walk: walk)
                    : switch (walk.phase) {
                        WalkPhase.navigating => _NavigatingPanel(
                          key: ValueKey('nav${walk.stopIndex}'),
                          walk: walk,
                        ),
                        WalkPhase.listening => _ListeningPanel(
                          key: ValueKey('listen${walk.stopIndex}'),
                          walk: walk,
                        ),
                        WalkPhase.quiz => _QuizPanel(
                          key: ValueKey('quiz${walk.stopIndex}'),
                          walk: walk,
                        ),
                        WalkPhase.photo => _PhotoPanel(
                          key: ValueKey('photo${walk.stopIndex}'),
                          walk: walk,
                        ),
                        WalkPhase.finished => _OutroPanel(
                          key: const ValueKey('outro'),
                          walk: walk,
                        ),
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmQuit(BuildContext context, WidgetRef ref) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this walk?'),
        content: const Text('Your progress on this walk won’t be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep walking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'End walk',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (quit == true && context.mounted) {
      ref.read(walkControllerProvider.notifier).end();
      context.go(Routes.home);
    }
  }
}

// ── Panels ───────────────────────────────────────────────────────────────────

class _PanelScaffold extends StatelessWidget {
  const _PanelScaffold({required this.header, required this.body, this.footer});
  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: header,
        ),
        Expanded(child: body),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottom),
            child: footer,
          ),
      ],
    );
  }
}

class _NavigatingPanel extends ConsumerWidget {
  const _NavigatingPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(walkControllerProvider.notifier);
    final d = walk.distanceToStop;
    final b = walk.bearingToStop;
    final showTranscript = walk.activeScript.isNotEmpty;

    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Walking to'),
          const SizedBox(height: 4),
          Text(walk.stop.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Transform.rotate(
                  angle: (b ?? 0) * 3.14159 / 180,
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d == null
                            ? 'Finding you…'
                            : '${formatDistance(d)} ${compassLabel(b!)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        walk.stop.directionsHint,
                        style: const TextStyle(
                          color: AppColors.gray,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: showTranscript
          ? _Transcript(lines: walk.activeScript, current: walk.currentLine)
          : const _MutedNote('The hosts will pick up again when you arrive.'),
      footer: Row(
        children: [
          if (showTranscript) ...[
            _PlayButton(walk: walk),
            const SizedBox(width: 12),
          ],
          const _TalkButton(),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: walk.arrived ? 'You’re here!' : 'I’m here',
              gradient: walk.arrived,
              icon: Icons.place_rounded,
              onPressed: ctrl.arrive,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListeningPanel extends ConsumerWidget {
  const _ListeningPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(walkControllerProvider.notifier);
    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Stop ${walk.stopIndex + 1} · Now playing'),
          const SizedBox(height: 4),
          Text(walk.stop.name, style: theme.textTheme.headlineSmall),
        ],
      ),
      body: _Transcript(lines: walk.stop.script, current: walk.currentLine),
      footer: Row(
        children: [
          _PlayButton(walk: walk),
          const SizedBox(width: 12),
          const _TalkButton(),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: ctrl.skip,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Skip to question'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizPanel extends ConsumerWidget {
  const _QuizPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = walk.stop.quiz;
    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Look around'),
          const SizedBox(height: 4),
          Row(
            children: [
              const HostAvatar(
                initial: 'T',
                color: AppColors.hostB,
                size: 32,
                speaking: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.question,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        children: [
          for (final (i, o) in q.options.indexed) ...[
            AppCard(
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.read(walkControllerProvider.notifier).answer(i);
              },
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      String.fromCharCode(65 + i),
                      style: const TextStyle(
                        color: Color(0xFFB07A00),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      o,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PhotoPanel extends ConsumerStatefulWidget {
  const _PhotoPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  ConsumerState<_PhotoPanel> createState() => _PhotoPanelState();
}

class _PhotoPanelState extends ConsumerState<_PhotoPanel> {
  bool _busy = false;

  Future<void> _capture(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file != null) {
        ref.read(walkControllerProvider.notifier).attachPhoto(file.path);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera unavailable: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walk = widget.walk;
    final theme = Theme.of(context);
    final ctrl = ref.read(walkControllerProvider.notifier);
    final answer = walk.answers[walk.stopIndex];
    final correct = answer != null && answer == walk.stop.quiz.correctIndex;
    final photo = walk.photos[walk.stopIndex];

    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: correct ? AppColors.mint : AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                correct ? 'Correct!' : 'Not quite',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: correct ? AppColors.mint : AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            walk.stop.quiz.explanation,
            style: const TextStyle(color: AppColors.gray, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Text('Snap it before you go', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(walk.stop.photoPrompt, style: const TextStyle(fontSize: 14)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: photo == null
            ? _PhotoPlaceholder(
                busy: _busy,
                onCamera: () => _capture(ImageSource.camera),
                onLibrary: () => _capture(ImageSource.gallery),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(photo), fit: BoxFit.cover),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _RoundButton(
                        icon: Icons.refresh_rounded,
                        onTap: () => _capture(ImageSource.camera),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      footer: PrimaryButton(
        label: walk.isLastStop ? 'Finish the walk' : 'Continue walking',
        gradient: photo != null,
        icon: walk.isLastStop
            ? Icons.flag_rounded
            : Icons.directions_walk_rounded,
        onPressed: ctrl.continueWalk,
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({
    required this.busy,
    required this.onCamera,
    required this.onLibrary,
  });
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: busy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.photo_camera_rounded,
                  size: 40,
                  color: AppColors.amber,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onCamera,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(180, 48),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Take photo'),
                ),
                TextButton(
                  onPressed: onLibrary,
                  child: const Text('Choose from library'),
                ),
              ],
            ),
    );
  }
}

class _OutroPanel extends ConsumerWidget {
  const _OutroPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('That’s the walk'),
          const SizedBox(height: 4),
          GradientText('Nice one.', style: theme.textTheme.headlineMedium),
        ],
      ),
      body: _Transcript(lines: walk.tour.outro, current: walk.currentLine),
      footer: PrimaryButton(
        label: 'See your keepsake',
        gradient: true,
        icon: Icons.card_giftcard_rounded,
        onPressed: () {
          ref.read(narratorProvider).stop();
          context.pushReplacement(Routes.summary);
        },
      ),
    );
  }
}

/// Live voice call with the hosts, in place of the phase panel while it's
/// open. Narration is paused underneath and resumes on hang-up.
class _TalkPanel extends ConsumerWidget {
  const _TalkPanel({required this.walk, super.key});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final call = ref.watch(voiceCallProvider);
    final voice = ref.read(voiceCallProvider.notifier);
    final walkCtrl = ref.read(walkControllerProvider.notifier);

    final (status, dotColor) = switch (call.status) {
      VoiceCallStatus.connecting => ('Calling the hosts…', AppColors.amber),
      VoiceCallStatus.live => (
        call.muted
            ? 'Muted'
            : call.assistantSpeaking
            ? 'Host is speaking'
            : 'Live · ask anything about ${walk.stop.name}',
        AppColors.primary,
      ),
      VoiceCallStatus.stopping => ('Hanging up…', AppColors.amber),
      VoiceCallStatus.error => ('Call failed', AppColors.error),
      VoiceCallStatus.idle => ('Call ended', AppColors.hint),
    };

    return _PanelScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Ask the hosts'),
          const SizedBox(height: 4),
          Row(
            children: [
              HostAvatar(
                initial: 'M',
                color: AppColors.hostA,
                size: 36,
                speaking: call.assistantSpeaking,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (call.error != null)
                      Text(
                        call.error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: call.turns.isEmpty
          ? _MutedNote(
              call.status == VoiceCallStatus.live
                  ? 'Go ahead, they’re listening.'
                  : call.status == VoiceCallStatus.error
                  ? 'Couldn’t reach the hosts. Set the relay URL in “Voice test (dev)” on the welcome screen.'
                  : 'Connecting…',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                for (final t in call.turns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HostAvatar(
                          initial: t.isUser ? 'Y' : 'M',
                          color: t.isUser ? AppColors.gray : AppColors.hostA,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.isUser ? 'You' : 'Mara',
                                style: TextStyle(
                                  color: t.isUser
                                      ? AppColors.gray
                                      : AppColors.hostA,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.text.trim(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      footer: Row(
        children: [
          Material(
            color: call.muted
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.white,
            shape: CircleBorder(
              side: BorderSide(
                color: call.muted ? AppColors.accent : AppColors.text,
                width: 1.5,
              ),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: call.isLive ? voice.toggleMute : null,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: call.muted ? AppColors.accent : AppColors.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: call.status == VoiceCallStatus.error
                  ? 'Back to the walk'
                  : 'Hang up',
              icon: Icons.call_end_rounded,
              onPressed: walkCtrl.endTalk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Round mic button that opens the live call.
class _TalkButton extends ConsumerWidget {
  const _TalkButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.text, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(walkControllerProvider.notifier).askHosts();
        },
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.mic_rounded, size: 26, color: AppColors.text),
        ),
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

/// Scrolling two-host transcript; the line being spoken is highlighted and
/// kept in view.
class _Transcript extends StatefulWidget {
  const _Transcript({required this.lines, required this.current});
  final List<ScriptLine> lines;
  final int current;

  @override
  State<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<_Transcript> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _Transcript old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current && widget.current >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.current]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.3,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: widget.lines.length,
      itemBuilder: (context, i) {
        final line = widget.lines[i];
        final active = i == widget.current;
        final past = i < widget.current;
        final color = line.host == Host.a ? AppColors.hostA : AppColors.hostB;
        return Padding(
          key: _keys.putIfAbsent(i, GlobalKey.new),
          padding: const EdgeInsets.only(bottom: 14),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: active
                ? 1
                : past
                ? 0.55
                : 0.35,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HostAvatar(
                  initial: line.host.initial,
                  color: color,
                  size: 30,
                  speaking: active,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.host.name,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line.text,
                        style: TextStyle(
                          fontSize: active ? 16 : 15,
                          height: 1.35,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.walk});
  final WalkState walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.text, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => ref.read(walkControllerProvider.notifier).togglePlay(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(
            walk.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 30,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.gray),
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        'Stop $current of $total',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
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
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.text),
        ),
      ),
    );
  }
}
