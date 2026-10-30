import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../widgets/common.dart';
import '../state/call_manager.dart';

class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({super.key, required this.callId});
  final String callId;
  @override
  ConsumerState<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _listen() {
    ref.listen(callManagerProvider, (prev, next) {
      if (next.uiState == CallUiState.connected || next.uiState == CallUiState.connecting) {
        if (mounted) context.go('/calls/active/${widget.callId}');
      }
      if (next.uiState == CallUiState.ended) {
        if (mounted) context.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callManagerProvider);
    final s = state.session;
    final other = s?.calleeProfile ?? s?.callerProfile;
    final name = other?.displayName.isNotEmpty == true ? other!.displayName : (other?.username ?? s?.isGroup == true ? 'Group' : 'Calling…');
    final avatar = other?.avatarUrl;

    String statusText() {
      switch (state.uiState) {
        case CallUiState.outgoingRinging: return 'Ringing…';
        case CallUiState.connecting: return 'Connecting…';
        case CallUiState.reconnecting: return 'Reconnecting…';
        case CallUiState.connected: return 'Connected';
        case CallUiState.ended: return state.error ?? 'Ended';
        default: return 'Calling…';
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)])),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 56),
              Text(statusText(), style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 24),
              CircleAvatar(radius: 56, backgroundColor: Colors.white.withOpacity(0.12), backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.w800)) : null),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                if (other?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 8), child: VerifiedMark(size: 18)),
              ]),
              if (other != null) Text('@${other.username}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
              if (s?.isGroup == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Group ${s?.isVideo == true ? 'video' : 'voice'} call', style: TextStyle(color: Colors.white.withOpacity(0.7)))),
              const Spacer(),
              // Network indicator
              if (state.networkQuality == 'poor') Container(margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.signal_cellular_alt, size: 16, color: Colors.amber), SizedBox(width: 6), Text('Poor connection', style: TextStyle(color: Colors.amber))]) ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: GestureDetector(
                  onTap: () async { await ref.read(callManagerProvider.notifier).cancel(); if (context.mounted) context.pop(); },
                  child: Container(width: 72, height: 72, decoration: BoxDecoration(color: BubbleColors.danger, shape: BoxShape.circle, boxShadow: [BoxShadow(color: BubbleColors.danger.withOpacity(0.4), blurRadius: 16)]), child: const Icon(Icons.call_end, color: Colors.white, size: 30)),
                ),
              ),
              Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
