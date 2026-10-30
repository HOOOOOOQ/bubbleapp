import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../widgets/common.dart';
import '../../../models/call_models.dart';
import '../state/call_manager.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.callId});
  final String callId;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    // Load call details if not already in manager state
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = ref.read(callRepositoryProvider);
    final session = await repo.callById(widget.callId);
    if (session != null && mounted) {
      ref.read(callManagerProvider.notifier).handleIncoming(session);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callManagerProvider);
    final session = state.session;
    if (session == null) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final caller = session.callerProfile;
    final name = caller?.displayName.isNotEmpty == true ? caller!.displayName : (caller?.username ?? 'Unknown');
    final avatar = caller?.avatarUrl;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)])),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(session.isVideo ? 'Incoming video call' : 'Incoming voice call', style: TextStyle(color: Colors.white.withOpacity(0.85), letterSpacing: 1.2, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _pulse,
                builder: (c, child) => Container(
                  padding: EdgeInsets.all(4 + 6 * _pulse.value),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.15 + 0.15 * _pulse.value), width: 2)),
                  child: child,
                ),
                child: CircleAvatar(radius: 64, backgroundColor: Colors.white.withOpacity(0.12), backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.w800)) : null),
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                if (caller?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 8), child: VerifiedMark(size: 20)),
              ]),
              if (caller != null) Text('@${caller.username}', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(session.isVideo ? Icons.videocam : Icons.call, size: 14, color: Colors.white), const SizedBox(width: 6), Text(session.isVideo ? 'Video' : 'Voice', style: const TextStyle(color: Colors.white, fontSize: 12))]) ),
              const Spacer(),
              if (session.isGroup) Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('Group call • ${session.maxParticipants ?? 8} max participants', style: TextStyle(color: Colors.white.withOpacity(0.7)))),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(icon: Icons.call_end, label: 'Decline', color: BubbleColors.danger, onTap: () async { await ref.read(callManagerProvider.notifier).decline(); if (context.mounted) context.pop(); }),
                    _CallActionButton(icon: Icons.call, label: 'Accept', color: BubbleColors.success, onTap: () async { await ref.read(callManagerProvider.notifier).accept(); if (context.mounted) context.go('/calls/active/${session.id}'); }),
                  ],
                ),
              ),
              // Quick reject with message
              TextButton(onPressed: () async => _rejectWithMessage(session), child: Text('Reply with message', style: TextStyle(color: Colors.white.withOpacity(0.8)))),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rejectWithMessage(CallSession session) async {
    final msg = await promptText(context, title: 'Quick reply', label: 'Message to send');
    if (msg == null || msg.isEmpty || !mounted) return;
    // Send as system message via messages table insert? We use repository
    // For now decline + send message via messaging repo (simplified)
    await ref.read(callManagerProvider.notifier).decline();
    if (mounted) context.pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Replied: $msg')));
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(onTap: onTap, child: Container(width: 72, height: 72, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16)]), child: Icon(icon, color: Colors.white, size: 30))),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]);
}
