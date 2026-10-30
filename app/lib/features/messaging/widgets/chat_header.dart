import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';
import '../../../widgets/common.dart';

/// iOS-inspired conversation header: avatar, name, verified/partner, online/last seen, call buttons.
class ChatHeader extends StatelessWidget implements PreferredSizeWidget {
  const ChatHeader({
    super.key,
    required this.conversation,
    required this.isOnline,
    required this.lastSeenAt,
    required this.onTapProfile,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onMore,
    this.onBack,
  });

  final ConversationSummary conversation;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final VoidCallback onTapProfile;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  final VoidCallback onMore;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final p = conversation.otherParticipant;
    final name = conversation.displayName(p?.username ?? 'Chat');
    return AppBar(
      leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: onBack) : null,
      leadingWidth: onBack != null ? 40 : 0,
      titleSpacing: 0,
      title: InkWell(
        onTap: onTapProfile,
        borderRadius: BorderRadius.circular(12),
        child: Row(children: [
          Stack(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage: (conversation.avatarUrl ?? p?.avatarUrl) != null ? NetworkImage((conversation.avatarUrl ?? p!.avatarUrl)!) : null,
              child: (conversation.avatarUrl ?? p?.avatarUrl) == null ? Text(name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)) : null,
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(width: 11, height: 11, decoration: BoxDecoration(color: BubbleColors.success, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2))),
              ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                if (p?.isVerified == true) ...[const SizedBox(width: 4), const VerifiedMark(size: 14)],
                if (conversation.isPinned) ...[const SizedBox(width: 4), Icon(Icons.push_pin, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)],
              ]),
              Text(
                isOnline ? 'Online' : _lastSeenLabel(lastSeenAt ?? p?.lastSeenAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: isOnline ? BubbleColors.success : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: onVoiceCall, tooltip: 'Voice call'),
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: onVideoCall, tooltip: 'Video call'),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'more') onMore();
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'more', child: Text('More options')),
          ],
        ),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: Theme.of(context).dividerColor)),
    );
  }

  String _lastSeenLabel(DateTime? t) {
    if (t == null) return conversation.isDirect ? 'Tap to view profile' : '${conversation.kind} · ${conversation.role}';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inHours < 1) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'last seen ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'last seen ${diff.inDays}d ago';
    return 'last seen ${t.day}/${t.month}/${t.year}';
  }
}

/// Full profile sheet shown when tapping the header.
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key, required this.conversation, required this.members, required this.isOnline, this.onMessage, this.onVoiceCall, this.onVideoCall, this.onMute, this.onArchive, this.onPin});

  final ConversationSummary conversation;
  final List<ConversationMember> members;
  final bool isOnline;
  final VoidCallback? onMessage;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onMute;
  final VoidCallback? onArchive;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    final p = conversation.otherParticipant;
    final name = conversation.displayName(p?.username ?? 'Chat');
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
        child: Column(children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 48,
            backgroundImage: (conversation.avatarUrl ?? p?.avatarUrl) != null ? NetworkImage((conversation.avatarUrl ?? p!.avatarUrl)!) : null,
            child: (conversation.avatarUrl ?? p?.avatarUrl) == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)) : null,
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            if (p?.isVerified == true) ...[const SizedBox(width: 6), const VerifiedMark(size: 18)],
          ]),
          if (p != null) Text('@${p.username}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(isOnline ? 'Online' : 'Last seen ${_lastSeenLabel(p?.lastSeenAt)}', style: TextStyle(fontSize: 13, color: isOnline ? BubbleColors.success : Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _QuickAction(icon: Icons.message_outlined, label: 'Message', onTap: onMessage),
            _QuickAction(icon: Icons.call_outlined, label: 'Voice', onTap: onVoiceCall),
            _QuickAction(icon: Icons.videocam_outlined, label: 'Video', onTap: onVideoCall),
            _QuickAction(icon: Icons.person_outline, label: 'Profile', onTap: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          _ActionListTile(icon: conversation.isMuted ? Icons.volume_up_outlined : Icons.volume_off_outlined, label: conversation.isMuted ? 'Unmute' : 'Mute', onTap: onMute),
          _ActionListTile(icon: conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, label: conversation.isArchived ? 'Unarchive' : 'Archive', onTap: onArchive),
          _ActionListTile(icon: conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin, label: conversation.isPinned ? 'Unpin' : 'Pin', onTap: onPin),
          if (conversation.isGroup) ...[
            const Divider(),
            Align(alignment: Alignment.centerLeft, child: Text('Members (${members.length})', style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: 8),
            for (final m in members)
              ListTile(
                leading: CircleAvatar(backgroundImage: m.profile?.avatarUrl != null ? NetworkImage(m.profile!.avatarUrl!) : null, child: m.profile?.avatarUrl == null ? Text((m.profile?.displayName ?? m.userId)[0].toUpperCase()) : null),
                title: Text(m.profile?.displayName ?? m.userId.substring(0, 8)),
                subtitle: Text('@${m.profile?.username ?? ''} · ${m.role}'),
                trailing: m.profile?.isVerified == true ? const VerifiedMark(size: 14) : null,
              ),
          ],
        ]),
      ),
    );
  }

  String _lastSeenLabel(DateTime? t) {
    if (t == null) return 'recently';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 5) return 'just now';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: BubbleColors.blue.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(icon, color: BubbleColors.blue)),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );
}

class _ActionListTile extends StatelessWidget {
  const _ActionListTile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(label), onTap: onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
}
