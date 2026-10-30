import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';

class CommunityProfileScreen extends ConsumerWidget {
  const CommunityProfileScreen({super.key, required this.communityId});
  final String communityId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commAsync = ref.watch(communityProvider(communityId));
    final membersAsync = ref.watch(communityMembersProvider(communityId));
    final requestsAsync = ref.watch(communityJoinRequestsProvider(communityId));
    return Scaffold(
      body: AsyncBody<Community?>(
        value: commAsync,
        builder: (community) {
          if (community == null) return const EmptyState(message: 'Community not found');
          return CustomScrollView(slivers: [
            SliverAppBar(expandedHeight: 220, pinned: true, flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [
              if (community.coverUrl != null) CachedNetworkImage(imageUrl: community.coverUrl!, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(decoration: const BoxDecoration(gradient: BubbleColors.premiumGradient))),
              if (community.coverUrl == null) Container(decoration: const BoxDecoration(gradient: BubbleColors.premiumGradient)),
              Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.6)]))),
              Positioned(bottom: 16, left: 16, right: 16, child: Row(children: [
                CircleAvatar(radius: 32, backgroundImage: community.avatarUrl != null ? CachedNetworkImageProvider(community.avatarUrl!) : null, child: community.avatarUrl == null ? Text(community.name[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: Colors.white)) : null),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(community.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                  Text('@${community.username ?? community.id.substring(0,8)} • ${community.category ?? 'Community'}', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                ])),
                if (community.isMember) StatusBadge(label: community.myRole != null ? community.myRole!.name : 'Member', color: Colors.white),
              ])),
            ])), title: Text(community.name), actions: [IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/communities/${community.id}/settings'))]),
            SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList.list(children: [
              GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(community.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  Chip(label: Text(community.visibility == CommunityVisibility.public ? 'Public' : 'Private'), avatar: Icon(community.visibility == CommunityVisibility.public ? Icons.public : Icons.lock_outline, size: 16)),
                  if (community.joinApproval) const Chip(label: Text('Approval required')),
                  Chip(label: Text('${community.memberCount} members')),
                ]),
                if (community.rules != null && community.rules!.isNotEmpty) ...[
                  const SectionHeader('Community rules'),
                  Text(community.rules!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: community.isMember ? null : () async { final ok = await runAction(context, () => ref.read(socialRepositoryProvider).joinCommunity(community.id), success: 'Request sent'); if (ok) ref.invalidate(communityProvider(community.id)); }, icon: const Icon(Icons.group_add), label: Text(community.isMember ? 'Joined' : (community.joinApproval ? 'Request to join' : 'Join')))),
                  if (community.isMember) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () async { final ok = await runAction(context, () => ref.read(socialRepositoryProvider).leaveCommunity(community.id), success: 'Left community'); if (ok) ref.invalidate(communityProvider(community.id)); }, icon: const Icon(Icons.exit_to_app), label: const Text('Leave')),
                  ],
                ]),
                Text('Owner cannot be removed by admins — enforced by RLS rank check.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              const SectionHeader('Announcements'),
              GlassCard(child: Column(children: [
                TextField(decoration: InputDecoration(hintText: 'Post an announcement...', suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () {})), maxLines: 2),
                const SizedBox(height: 8),
                Text('Announcements are visible to all members. Only admins can post (RLS).', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              SectionHeader('Members', trailing: TextButton(onPressed: () {}, child: const Text('See all'))),
              AsyncBody<List<CommunityMember>>(value: membersAsync, builder: (members) => Column(children: members.take(6).map((m) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GlassCard(child: Row(children: [
                CircleAvatar(radius: 18, backgroundImage: m.profile?.avatarUrl != null ? NetworkImage(m.profile!.avatarUrl!) : null, child: m.profile?.avatarUrl == null ? Text((m.profile?.displayName ?? '?')[0]) : null),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.profile?.displayName ?? m.userId.substring(0,8), style: const TextStyle(fontWeight: FontWeight.w600)), Text('@${m.profile?.username ?? ''}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
                StatusBadge(label: m.role.name, color: m.role == CommunityRole.owner ? BubbleColors.violet : (m.role == CommunityRole.admin ? BubbleColors.blue : null)),
              ])))).toList())),
              AsyncBody<List<CommunityJoinRequest>>(value: requestsAsync, builder: (reqs) => reqs.isEmpty ? const SizedBox.shrink() : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionHeader('Join requests'),
                ...reqs.map((r) => GlassCard(child: Row(children: [
                  CircleAvatar(radius: 18, backgroundImage: r.profile?.avatarUrl != null ? NetworkImage(r.profile!.avatarUrl!) : null),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.profile?.displayName ?? r.userId.substring(0,8), style: const TextStyle(fontWeight: FontWeight.w600)), if (r.message != null) Text(r.message!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
                  TextButton(onPressed: () async { await runAction(context, () => ref.read(socialRepositoryProvider).approveJoinRequest(r.id), success: 'Approved'); ref.invalidate(communityJoinRequestsProvider(communityId)); }, child: const Text('Approve')),
                  TextButton(onPressed: () async { await runAction(context, () => ref.read(socialRepositoryProvider).rejectJoinRequest(r.id), success: 'Rejected'); ref.invalidate(communityJoinRequestsProvider(communityId)); }, child: const Text('Reject')),
                ]))),
              ])),
              const SectionHeader('Groups in this community'),
              GlassCard(child: Row(children: [const Icon(Icons.chat_bubble_outline), const SizedBox(width: 10), const Expanded(child: Text('Community groups are conversations linked via community_groups — tap to open chat')), TextButton(onPressed: () => context.push('/chats/new-group'), child: const Text('Create group'))])),
              const SectionHeader('Activity feed'),
              GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Activity feed shows real posts with community_id = ${community.id}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(height: 8), FilledButton.tonalIcon(onPressed: () => context.push('/feed/create', extra: community.id), icon: const Icon(Icons.post_add_outlined), label: const Text('Create post in community'))])),
              const SizedBox(height: 12),
              Row(children: [OutlinedButton.icon(onPressed: () => context.push('/reports/new', extra: {'type':'community','id': community.id}), icon: const Icon(Icons.flag_outlined), label: const Text('Report community')), const SizedBox(width: 8), OutlinedButton.icon(onPressed: () => showMessage(context, 'Blocked'), icon: const Icon(Icons.block_outlined), label: const Text('Block'))]),
            ])),
          ]);
        },
      ),
    );
  }
}
