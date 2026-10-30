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

class CommunityDirectoryScreen extends ConsumerStatefulWidget {
  const CommunityDirectoryScreen({super.key});
  @override
  ConsumerState<CommunityDirectoryScreen> createState() => _CommunityDirectoryScreenState();
}

class _CommunityDirectoryScreenState extends ConsumerState<CommunityDirectoryScreen> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final communitiesAsync = ref.watch(communitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Communities'), actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Create community', onPressed: () => context.push('/communities/new'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search communities', suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _query = '')) : null), onChanged: (v) => setState(() => _query = v))),
        Expanded(child: AsyncBody<List<Community>>(
          value: communitiesAsync,
          builder: (list) {
            final filtered = _query.isEmpty ? list : list.where((c) => c.name.toLowerCase().contains(_query.toLowerCase()) || (c.description.toLowerCase().contains(_query.toLowerCase()))).toList();
            if (filtered.isEmpty) return const EmptyState(message: 'No communities yet. Create one to get started.', icon: Icons.groups_outlined);
            return RefreshIndicator(onRefresh: () async => ref.invalidate(communitiesProvider), child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: filtered.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (context, i) {
              final c = filtered[i];
              return _CommunityCard(community: c, onJoin: () async { final ok = await runAction(context, () => ref.read(socialRepositoryProvider).joinCommunity(c.id), success: 'Joined ${c.name}'); if (ok) ref.invalidate(communitiesProvider); });
            }));
          },
        )),
      ]),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.community, required this.onJoin});
  final Community community; final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => context.push('/communities/${community.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (community.coverUrl != null) ClipRRect(borderRadius: BorderRadius.circular(16), child: CachedNetworkImage(imageUrl: community.coverUrl!, height: 110, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(height: 110, color: Theme.of(context).colorScheme.surfaceVariant))),
        const SizedBox(height: 12),
        Row(children: [
          CircleAvatar(radius: 22, backgroundImage: community.avatarUrl != null ? CachedNetworkImageProvider(community.avatarUrl!) : null, child: community.avatarUrl == null ? Text(community.name[0].toUpperCase()) : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(community.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('@${community.username ?? community.id.substring(0,8)} • ${community.category ?? 'Community'} • ${community.memberCount} members', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: community.visibility == CommunityVisibility.public ? BubbleColors.success.withOpacity(0.12) : BubbleColors.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(999)), child: Text(community.visibility == CommunityVisibility.public ? 'Public' : 'Private', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: community.visibility == CommunityVisibility.public ? BubbleColors.success : BubbleColors.warning))),
        ]),
        if (community.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(community.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
        const SizedBox(height: 10),
        Row(children: [
          if (community.joinApproval) const StatusBadge(label: 'Approval required', color: BubbleColors.warning),
          const Spacer(),
          FilledButton.icon(onPressed: onJoin, icon: const Icon(Icons.group_add_outlined, size: 16), label: Text(community.joinApproval ? 'Request to join' : 'Join')),
        ]),
      ]),
    );
  }
}
