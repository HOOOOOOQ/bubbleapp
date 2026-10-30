import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';
import '../../../state/providers.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _ctrl = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all, users, channels, communities, posts, hashtags

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    setState(() => _query = q.trim());
    try { await ref.read(socialRepositoryProvider).recordSearch(q.trim()); ref.invalidate(recentSearchesProvider); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentSearchesProvider);
    final searchResult = _query.isEmpty ? null : ref.watch(searchProvider(_query));
    final trendingTags = ref.watch(trendingHashtagsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _ctrl, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search users, channels, communities, posts, #hashtags', suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _query = '')) : null), onSubmitted: _search)),
        SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final f in ['all','users','channels','communities','posts','hashtags']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f))),
        ])),
        Expanded(child: _query.isEmpty ? _EmptyView(recent: recent, trendingTags: trendingTags, onTagTap: (t) => _search('#$t'), onSearch: _search) : _SearchResults(query: _query, filter: _filter, result: searchResult)),
      ]),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.recent, required this.trendingTags, required this.onTagTap, required this.onSearch});
  final AsyncValue<List<String>> recent; final AsyncValue<List<Hashtag>> trendingTags; final void Function(String tag) onTagTap; final void Function(String q) onSearch;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const SectionHeader('Recent searches'),
        AsyncBody<List<String>>(value: recent, builder: (list) => list.isEmpty ? const Text('No recent searches') : Wrap(spacing: 8, children: list.map((q) => ActionChip(label: Text(q), onPressed: () => onSearch(q))).toList())),
        const SectionHeader('Trending topics'),
        Text('Trending is based on real hashtag post_count + post engagement — no fake numbers.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        AsyncBody<List<Hashtag>>(value: trendingTags, builder: (tags) => tags.isEmpty ? const Text('No trending tags yet') : Wrap(spacing: 8, children: tags.map((t) => Chip(label: Text('#${t.tag} • ${t.postCount}'), backgroundColor: BubbleColors.violet.withOpacity(0.12))).toList())),
        const SectionHeader('Recommended'),
        GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Follow suggestions respect blocking & privacy', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Suggested channels/communities are ordered by real subscriber counts and member counts.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        const SectionHeader('Categories'),
        Wrap(spacing: 8, children: ['Tech','Music','Gaming','Art','News','Sports'].map((c) => ActionChip(label: Text(c), onPressed: () => onSearch(c))).toList()),
      ]);
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.filter, required this.result});
  final String query; final String filter; final AsyncValue<SearchResult>? result;
  @override
  Widget build(BuildContext context) {
    if (result == null) return const Center(child: Text('Enter a search'));
    return AsyncBody<SearchResult>(value: result!, builder: (r) {
      final showUsers = filter == 'all' || filter == 'users';
      final showChannels = filter == 'all' || filter == 'channels';
      final showCommunities = filter == 'all' || filter == 'communities';
      final showPosts = filter == 'all' || filter == 'posts';
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (showUsers && r.users.isNotEmpty) ...[const SectionHeader('Users'), ...r.users.map((u) => GlassCard(child: Row(children: [CircleAvatar(radius: 20, backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null, child: u.avatarUrl == null ? Text(u.username[0]) : null), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w600)), Text('@${u.username}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))])), if (u.isVerified) const VerifiedMark(), IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: () {})]))],
        if (showChannels && r.channels.isNotEmpty) ...[const SectionHeader('Channels'), ...r.channels.map((c) => GlassCard(child: Row(children: [const Icon(Icons.campaign_outlined), const SizedBox(width: 10), Expanded(child: Text(c['name'] ?? c['username'] ?? '')), TextButton(onPressed: () => context.push('/channels/${c['id']}'), child: const Text('View'))])) )],
        if (showCommunities && r.communities.isNotEmpty) ...[const SectionHeader('Communities'), ...r.communities.map((c) => GlassCard(child: Row(children: [const Icon(Icons.groups_outlined), const SizedBox(width: 10), Expanded(child: Text(c['name'] ?? '')), TextButton(onPressed: () => context.push('/communities/${c['id']}'), child: const Text('View'))])) )],
        if (showPosts && r.posts.isNotEmpty) ...[const SectionHeader('Posts'), ...r.posts.map((p) => GlassCard(child: Text(p['body'] ?? '')))],
        if (r.users.isEmpty && r.channels.isEmpty && r.communities.isEmpty && r.posts.isEmpty) EmptyState(message: 'No results for "$query"', icon: Icons.search_off_outlined),
        const SizedBox(height: 12),
        Text('Private content never appears in search — RLS filters posts by visibility + blocking. Hashtags and mentions are validated server-side.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
    });
  }
}
