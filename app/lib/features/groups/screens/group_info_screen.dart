import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../core/bubble_error.dart';
import '../../../data/messaging_repository.dart';
import '../../../data/social_repository.dart';
import '../../../models/messaging.dart';
import '../../../models/social.dart';
import '../../../state/messaging_providers.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(conversationMembersProvider(widget.conversationId));
    final settingsAsync = ref.watch(groupSettingsProvider(widget.conversationId));
    final convAsync = ref.watch(conversationProvider(widget.conversationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AsyncBody<ConversationSummary?>(value: convAsync, builder: (conv) => conv == null ? const SizedBox.shrink() : GlassCard(child: Row(children: [
          CircleAvatar(radius: 28, backgroundImage: conv.avatarUrl != null ? NetworkImage(conv.avatarUrl!) : null, child: conv.avatarUrl == null ? Text((conv.title ?? 'G')[0]) : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(conv.title ?? 'Group', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), Text('${conv.kind} • ${membersAsync.valueOrNull?.length ?? 0} members', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))])),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
        ]))),
        const SectionHeader('Permissions'),
        AsyncBody<GroupSettings>(value: settingsAsync, builder: (s) => GlassCard(child: Column(children: [
          _PermTile(title: 'Send messages', value: s.allowSendMessages),
          _PermTile(title: 'Send media', value: s.allowSendMedia),
          _PermTile(title: 'Add members', value: s.allowAddMembers),
          _PermTile(title: 'Change group info', value: s.allowChangeInfo),
          _PermTile(title: 'Pin messages', value: s.allowPinMessages),
          _PermTile(title: 'Create polls', value: s.allowCreatePolls),
          _PermTile(title: 'Start group calls', value: s.allowStartCalls),
          _PermTile(title: 'Manage invitations', value: s.allowManageInvites),
          _PermTile(title: 'Require approval', value: s.requireApproval),
          Text('All permissions are enforced by group_settings + RLS. Admin/owner rank is checked server-side.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          FilledButton.tonalIcon(onPressed: () async { final newSettings = GroupSettings(conversationId: s.conversationId, allowSendMessages: !s.allowSendMessages); await runAction(context, () => ref.read(socialRepositoryProvider).updateGroupSettings(newSettings)); ref.invalidate(groupSettingsProvider(widget.conversationId)); }, icon: const Icon(Icons.edit_outlined), label: const Text('Edit permissions')),
        ]))),
        const SectionHeader('Members'),
        AsyncBody<List<ConversationMember>>(value: membersAsync, builder: (members) => Column(children: members.map((m) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GlassCard(child: Row(children: [
          CircleAvatar(radius: 18, child: Text(m.profile?.displayName.isNotEmpty == true ? m.profile!.displayName[0] : '?')),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.profile?.displayName ?? m.userId.substring(0,8), style: const TextStyle(fontWeight: FontWeight.w600)), Text(m.role, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
          PopupMenuButton<String>(onSelected: (v) async { if (v == 'makeAdmin') {/* TODO */} }, itemBuilder: (_) => [const PopupMenuItem(value: 'makeAdmin', child: Text('Make admin')), const PopupMenuItem(value: 'remove', child: Text('Remove'))]),
        ])))).toList())),
        const SectionHeader('Invite'),
        AsyncBody<GroupSettings>(value: settingsAsync, builder: (s) => GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Invite link: ${s.inviteLink ?? '—'}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(onPressed: () async { final inv = await ref.read(socialRepositoryProvider).createGroupInvite(widget.conversationId); if (mounted) showMessage(context, 'Invite: ${inv.code}'); ref.invalidate(groupSettingsProvider(widget.conversationId)); }, icon: const Icon(Icons.link), label: const Text('Create invite')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => context.push('/groups/${widget.conversationId}/invites'), child: const Text('Manage invites')),
          ]),
        ]))),
        const SectionHeader('Group features'),
        GlassCard(child: Column(children: [
          ListTile(leading: const Icon(Icons.announcement_outlined), title: const Text('Announcements'), subtitle: const Text('Pinned messages visible to all'), onTap: () {}),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Media gallery'), subtitle: const Text('Group attachments'), onTap: () {}),
          ListTile(leading: const Icon(Icons.search_outlined), title: const Text('Search in group'), onTap: () {}),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Start group call'), subtitle: const Text('Requires allow_start_calls'), onTap: () => context.push('/calls/active/${widget.conversationId}')),
        ])),
      ]),
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({required this.title, required this.value});
  final String title; final bool value;
  @override
  Widget build(BuildContext context) => ListTile(dense: true, title: Text(title, style: const TextStyle(fontSize: 13)), trailing: Icon(value ? Icons.check_circle : Icons.cancel_outlined, color: value ? BubbleColors.success : Theme.of(context).colorScheme.onSurfaceVariant, size: 18));
}
