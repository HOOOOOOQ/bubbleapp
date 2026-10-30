import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../state/call_manager.dart';

/// Global incoming call overlay — shown over any screen when a call arrives.
/// Inserted in BubbleApp root via Stack.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callManagerProvider);
    // Only show for incoming ringing not already on call screen
    final shouldShow = state.uiState == CallUiState.incomingRinging && state.session != null;
    return Stack(children: [
      child,
      if (shouldShow) _IncomingBanner(state: state, onAccept: () async { await ref.read(callManagerProvider.notifier).accept(); if (context.mounted) context.go('/calls/active/${state.session!.id}'); }, onDecline: () async { await ref.read(callManagerProvider.notifier).decline(); }),
    ]);
  }
}

class _IncomingBanner extends StatelessWidget {
  const _IncomingBanner({required this.state, required this.onAccept, required this.onDecline});
  final CallState state;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  @override
  Widget build(BuildContext context) {
    final s = state.session!;
    final name = s.callerProfile?.displayName ?? s.callerProfile?.username ?? 'Incoming call';
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: BubbleColors.blue.withOpacity(0.2))),
          child: Row(children: [
            CircleAvatar(radius: 20, backgroundImage: s.callerProfile?.avatarUrl != null ? NetworkImage(s.callerProfile!.avatarUrl!) : null, child: s.callerProfile?.avatarUrl == null ? Text(name[0].toUpperCase()) : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), Text(s.isVideo ? 'Video call' : 'Voice call', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
            IconButton.filledTonal(onPressed: onDecline, icon: const Icon(Icons.call_end, color: BubbleColors.danger)),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: onAccept, icon: const Icon(Icons.call, size: 16), label: const Text('Answer'), style: FilledButton.styleFrom(backgroundColor: BubbleColors.success)),
          ]),
        ),
      ),
    );
  }
}
