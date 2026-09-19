import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/relay_protocol.dart';
import '../providers/voice_call_controller.dart';

/// Dev-only harness for the Gemini voice relay: start/end a call, mute, see
/// the live transcript, tool activity and connection log.
///
/// The call is stopped when the screen is left (provider auto-dispose) and
/// when the app goes to the background.
class VoiceTestScreen extends ConsumerStatefulWidget {
  const VoiceTestScreen({super.key});

  @override
  ConsumerState<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends ConsumerState<VoiceTestScreen>
    with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  bool _showLog = false;
  // Captured up front: the provider is app-wide, and ref isn't for dispose().
  late final VoiceCallController _call;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _call = ref.read(voiceCallProvider.notifier);
    _call.loadRelayUrl().then((url) {
      if (mounted && _urlController.text.isEmpty) _urlController.text = url;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    // Leaving the screen ends the test call.
    _call.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(voiceCallProvider.notifier).stop();
    }
  }

  void _start() {
    FocusScope.of(context).unfocus();
    // Show the URL that will actually be dialled (wss://, /gemini/voice …).
    _urlController.text = normalizeRelayUrl(_urlController.text);
    ref.read(voiceCallProvider.notifier).start(_urlController.text);
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(voiceCallProvider);
    final ctrl = ref.read(voiceCallProvider.notifier);
    final theme = Theme.of(context);
    final editable =
        call.status == VoiceCallStatus.idle ||
        call.status == VoiceCallStatus.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice test'),
        actions: [
          IconButton(
            tooltip: 'Connection log',
            icon: Icon(_showLog ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  const SectionLabel('Relay'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlController,
                    enabled: editable,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'wss://<host>/gemini/voice',
                      helperText:
                          'Pasting the https:// tunnel page URL is fine.',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _StatusCard(call: call),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: call.holdMicWhileSpeaking,
                    onChanged: (_) => ctrl.toggleHoldMic(),
                    title: const Text(
                      'Hold mic while host speaks',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      'No interrupting, but stops speaker echo from cutting replies off.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.gray,
                      ),
                    ),
                  ),
                  if (call.error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(
                      message: call.error!,
                      onRetry: editable ? _start : null,
                    ),
                  ],
                  if (call.notice != null &&
                      call.status != VoiceCallStatus.idle) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            call.notice!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.gray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const SectionLabel('Transcript'),
                  const SizedBox(height: 6),
                  AppCard(
                    child: call.turns.isEmpty
                        ? Text(
                            call.isLive
                                ? 'Say something. Try “What time is it in Tokyo?”'
                                : 'The conversation will appear here.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.gray,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final t in call.turns) _TurnRow(turn: t),
                            ],
                          ),
                  ),
                  if (call.lastToolEvent != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.build_circle_outlined,
                          size: 18,
                          color: AppColors.gray,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          call.lastToolEvent!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_showLog) ...[
                    const SizedBox(height: 16),
                    const SectionLabel('Connection log'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        call.log.isEmpty ? '(empty)' : call.log.join('\n'),
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 11,
                          fontFamily: 'Menlo',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (call.isLive) ...[
                    _MuteButton(muted: call.muted, onPressed: ctrl.toggleMute),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: call.isLive
                        ? PrimaryButton(
                            label: 'End call',
                            icon: Icons.call_end_rounded,
                            onPressed: ctrl.stop,
                          )
                        : PrimaryButton(
                            label: call.status == VoiceCallStatus.connecting
                                ? 'Connecting…'
                                : 'Start call',
                            gradient: true,
                            icon: Icons.call_rounded,
                            loading: call.isBusy,
                            onPressed: editable ? _start : null,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.call});
  final VoiceCallState call;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (call.status) {
      VoiceCallStatus.idle => ('Idle', AppColors.hint),
      VoiceCallStatus.connecting => ('Connecting…', AppColors.amber),
      VoiceCallStatus.live => (
        call.muted
            ? 'Live · muted'
            : call.holdMicWhileSpeaking && call.assistantSpeaking
            ? 'Live · host speaking'
            : 'Live · start talking',
        AppColors.primary,
      ),
      VoiceCallStatus.stopping => ('Ending…', AppColors.amber),
      VoiceCallStatus.error => ('Failed', AppColors.error),
    };
    return AppCard(
      child: Row(
        children: [
          HostAvatar(
            initial: 'G',
            color: call.isLive ? AppColors.hostA : AppColors.hint,
            size: 44,
            speaking: call.assistantSpeaking,
          ),
          const SizedBox(width: 14),
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
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (call.model != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    call.model!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.gray),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TurnRow extends StatelessWidget {
  const _TurnRow({required this.turn});
  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final user = turn.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              user ? 'You' : 'Host',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: user ? AppColors.gray : AppColors.hostA,
              ),
            ),
          ),
          Expanded(
            child: Text(
              turn.text.trim(),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onPressed});
  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: muted
              ? AppColors.accent.withValues(alpha: 0.12)
              : null,
          side: BorderSide(
            color: muted ? AppColors.accent : AppColors.borderStrong,
          ),
        ),
        child: Icon(
          muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: muted ? AppColors.accent : AppColors.text,
        ),
      ),
    );
  }
}
