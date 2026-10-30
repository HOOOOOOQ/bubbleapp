import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';
import '../../../widgets/common.dart';

/// Long-press on a chat row — expands the card, blurs background, shows avatar + quick actions.
class ChatProfilePreview extends StatelessWidget {
  const ChatProfilePreview({
    super.key,
    required this.conversation,
    required this.isOnline,
    required this.onMessage,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onViewProfile,
    required this.onMute,
    required this.onArchive,
    required this.onPin,
    required this.onDismiss,
  });

  final ConversationSummary conversation;
  final bool isOnline;
  final VoidCallback onMessage;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  final VoidCallback onViewProfile;
  final VoidCallback onMute;
  final VoidCallback onArchive;
  final VoidCallback onPin;
  final VoidCallback onDismiss;

  static Future<void> show(
    BuildContext context, {
    required ConversationSummary conversation,
    required bool isOnline,
    required VoidCallback onMessage,
    required VoidCallback onVoiceCall,
    required VoidCallback onVideoCall,
    required VoidCallback onViewProfile,
    required VoidCallback onMute,
    required VoidCallback onArchive,
    required VoidCallback onPin,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Chat preview',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, a, b) => ChatProfilePreview(
        conversation: conversation,
        isOnline: isOnline,
        onMessage: () { Navigator.pop(ctx); onMessage(); },
        onVoiceCall: () { Navigator.pop(ctx); onVoiceCall(); },
        onVideoCall: () { Navigator.pop(ctx); onVideoCall(); },
        onViewProfile: () { Navigator.pop(ctx); onViewProfile(); },
        onMute: () { Navigator.pop(ctx); onMute(); },
        onArchive: () { Navigator.pop(ctx); onArchive(); },
        onPin: () { Navigator.pop(ctx); onPin(); },
        onDismiss: () => Navigator.pop(ctx),
      ),
      transitionBuilder: (ctx, a, b, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = conversation.otherParticipant;
    final name = conversation.displayName(p?.username ?? 'Chat');
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Blur backdrop
          BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: GestureDetector(onTap: onDismiss, child: Container(color: Colors.black.withValues(alpha: 0.25)))),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Expanded card
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 360),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))]),
                    child: Column(children: [
                      // Header with avatar
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        decoration: BoxDecoration(gradient: BubbleColors.brandGradient, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                        child: Column(children: [
                          Stack(children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: Colors.white,
                              backgroundImage: (conversation.avatarUrl ?? p?.avatarUrl) != null ? NetworkImage((conversation.avatarUrl ?? p!.avatarUrl)!) : null,
                              child: (conversation.avatarUrl ?? p?.avatarUrl) == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: BubbleColors.blue)) : null,
                            ),
                            if (isOnline)
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: BubbleColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                              ),
                          ]),
                          const SizedBox(height: 12),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (p?.isVerified == true) ...[const SizedBox(width: 6), const Icon(Icons.verified, size: 16, color: Colors.white)],
                          ]),
                          if (p != null) Text('@${p.username}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(isOnline ? 'Online' : 'Tap to view profile', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                        ]),
                      ),
                      // Quick actions grid
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Row(children: [
                            _ActionChip(icon: Icons.message_outlined, label: 'Message', onTap: onMessage),
                            const SizedBox(width: 8),
                            _ActionChip(icon: Icons.call_outlined, label: 'Voice call', onTap: onVoiceCall),
                            const SizedBox(width: 8),
                            _ActionChip(icon: Icons.videocam_outlined, label: 'Video call', onTap: onVideoCall),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _ActionChip(icon: Icons.person_outline, label: 'View profile', onTap: onViewProfile),
                            const SizedBox(width: 8),
                            _ActionChip(icon: conversation.isMuted ? Icons.volume_up_outlined : Icons.volume_off_outlined, label: conversation.isMuted ? 'Unmute' : 'Mute', onTap: onMute),
                            const SizedBox(width: 8),
                            _ActionChip(icon: conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, label: conversation.isArchived ? 'Unarchive' : 'Archive', onTap: onArchive),
                          ]),
                          const SizedBox(height: 8),
                          SizedBox(width: double.infinity, child: _ActionChip(icon: conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin, label: conversation.isPinned ? 'Unpin conversation' : 'Pin conversation', onTap: onPin, fullWidth: true)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // Dismiss handle
                  GestureDetector(onTap: onDismiss, child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(2)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap, this.fullWidth = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
