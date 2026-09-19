import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../live/live_conversation_controller.dart';

class GeminiLiveScreen extends StatefulWidget {
  const GeminiLiveScreen({required this.configured, super.key});

  final bool configured;

  @override
  State<GeminiLiveScreen> createState() => _GeminiLiveScreenState();
}

class _GeminiLiveScreenState extends State<GeminiLiveScreen>
    with SingleTickerProviderStateMixin {
  late final LiveConversationController _controller;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _controller = LiveConversationController(configured: widget.configured);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 560 ? 20 : 32,
                vertical: constraints.maxWidth < 560 ? 24 : 40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _content(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final live = _controller.isLive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 34),
        Text(
          live ? 'I’m listening.' : 'A calmer way to talk to Gemini.',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          live ? 'Speak naturally. I’ll respond as you go.' : 'Start a low-latency voice conversation with live tool calling.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        _voiceOrb(context),
        const SizedBox(height: 24),
        _statusPill(context),
        const SizedBox(height: 24),
        if (!widget.configured) ...[
          _setupCard(context),
          const SizedBox(height: 20),
        ],
        if (_controller.errorMessage != null) ...[
          _errorCard(context, _controller.errorMessage!),
          const SizedBox(height: 20),
        ],
        if (_controller.lastToolEvent != null) ...[
          _toolCard(context, _controller.lastToolEvent!),
          const SizedBox(height: 20),
        ],
        _transcriptCard(context),
        const SizedBox(height: 24),
        _actions(context),
        const SizedBox(height: 24),
        Text(
          'Audio streams to Gemini only while the active conversation is running.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.graphic_eq, color: theme.colorScheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Text(
          'Gemini Live',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            'PREVIEW',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        const Spacer(),
        if (_controller.isLive && MediaQuery.sizeOf(context).width >= 520)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text('Active session', style: theme.textTheme.labelMedium),
            ],
          ),
      ],
    );
  }

  Widget _voiceOrb(BuildContext context) {
    final theme = Theme.of(context);
    final active = _controller.isLive;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final wave = active
            ? (math.sin(_pulse.value * math.pi * 2) + 1) / 2
            : 0.0;
        return SizedBox(
          height: 178,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Container(
                  width: 152 + wave * 16,
                  height: 152 + wave * 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      width: 12,
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: active ? 124 : 108,
                height: active ? 124 : 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.98),
                      theme.colorScheme.primary.withValues(alpha: 0.72),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(
                        alpha: active ? 0.28 : 0.14,
                      ),
                      blurRadius: active ? 30 : 18,
                      spreadRadius: active ? 5 : 2,
                    ),
                  ],
                ),
                child: Icon(
                  active ? Icons.graphic_eq : Icons.mic_none,
                  color: theme.colorScheme.onPrimary,
                  size: 42,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusPill(BuildContext context) {
    final theme = Theme.of(context);
    final label = _statusLabel(_controller.status);
    final active = _controller.isLive;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }

  String _statusLabel(LiveConversationStatus status) {
    return switch (status) {
      LiveConversationStatus.setupRequired => 'Setup required',
      LiveConversationStatus.requestingPermission => 'Requesting microphone',
      LiveConversationStatus.connecting => 'Connecting to Gemini',
      LiveConversationStatus.live => 'Live conversation',
      LiveConversationStatus.stopping => 'Ending conversation',
      LiveConversationStatus.error => 'Something went wrong',
      LiveConversationStatus.idle => 'Ready when you are',
    };
  }

  Widget _setupCard(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Connect Firebase to go live',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'The preview is ready. Add the shared Firebase values and one '
            'app ID for the current platform. The README has copy-paste run '
            'commands.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '''FIREBASE_API_KEY
FIREBASE_PROJECT_ID
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_ANDROID_APP_ID or FIREBASE_IOS_APP_ID''',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    return _Panel(
      color: theme.colorScheme.errorContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolCard(BuildContext context, String event) {
    final theme = Theme.of(context);
    return _Panel(
      color: theme.colorScheme.tertiaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tool called',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event,
                  style: TextStyle(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcriptCard(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _controller.transcripts;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Conversation', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${entries.length} turns',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              'Your transcript will appear here as you speak.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...entries.take(8).map((entry) => _TranscriptLine(entry: entry)),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final theme = Theme.of(context);
    if (_controller.isLive) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _controller.toggleMute,
              icon: Icon(_controller.isMuted ? Icons.mic_off : Icons.mic),
              label: Text(_controller.isMuted ? 'Unmute' : 'Mute'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: _controller.stop,
              icon: const Icon(Icons.call_end),
              label: const Text('End conversation'),
            ),
          ),
        ],
      );
    }
    final busy =
        _controller.status == LiveConversationStatus.connecting ||
        _controller.status == LiveConversationStatus.requestingPermission;
    return FilledButton.icon(
      onPressed: widget.configured && !busy ? _controller.start : null,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.mic),
      label: Text(busy ? 'Getting ready' : 'Start conversation'),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({required this.entry});

  final TranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = entry.speaker.toLowerCase() == 'you';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: user
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: user ? 'You  ' : 'Gemini  ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: entry.text,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: child,
    );
  }
}
