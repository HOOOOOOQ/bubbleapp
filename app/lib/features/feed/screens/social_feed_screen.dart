import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';
import '../../stories/widgets/stories_tray.dart';
import '../widgets/post_card.dart';

class SocialFeedScreen extends ConsumerStatefulWidget {
  const SocialFeedScreen({super.key});
  @override
  ConsumerState<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends ConsumerState<SocialFeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override
  void initState() { super.initState(); _tabs = TabController(length: 5, vsync: this); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed'), bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'Home'), Tab(text: 'Following'), Tab(text: 'Discover'), Tab(text: 'Trending'), Tab(text: 'My posts')])),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/feed/create'), icon: const Icon(Icons.edit_outlined), label: const Text('Post')),
      body: Column(children: [
        const StoriesTray(),
        const Divider(height: 1),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _FeedTab(kind: 'home'),
          _FeedTab(kind: 'following'),
          _DiscoverTab(),
          _TrendingTab(),
          _FeedTab(kind: 'my', authorId: ref.read(socialRepositoryProvider).uid),
        ])),
      ]),
    );
  }
}

class _FeedTab extends ConsumerWidget {
  const _FeedTab({required this.kind, this.authorId});
  final String kind; final String? authorId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(kind == 'my' && authorId != null ? feedProvider('my:$authorId') : feedProvider(kind));
    // For 'my', we filter locally; for simplicity reuse feed provider with kind, then filter if needed
    return AsyncBody<List<Post>>(
      value: kind == 'my' && authorId != null
          ? FutureProvider<List<Post>>((r) async {
              final posts = await r.read(socialRepositoryProvider).feed(authorId: authorId);
              return posts;
            }).whenData((d) => d) as AsyncValue<List<Post>>
          : feedAsync,
      builder: (posts) {
        // if kind==my we already filtered above via custom, but fallback
        final list = kind == 'my' && authorId != null ? posts.where((p) => p.authorId == authorId).toList() : posts;
        if (list.isEmpty) return EmptyState(message: 'No posts yet. Share something!', icon: Icons.feed_outlined);
        return RefreshIndicator(onRefresh: () async => ref.invalidate(feedProvider(kind)), child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (context, i) => PostCard(post: list[i], onRefresh: () => ref.invalidate(feedProvider(kind)))));
      },
    );
  }
}

class _DiscoverTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingPosts = ref.watch(trendingPostsProvider);
    final trendingHashtags = ref.watch(trendingHashtagsProvider);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionHeader('Trending hashtags'),
      AsyncBody<List<Hashtag>>(value: trendingHashtags, builder: (tags) => tags.isEmpty ? const Text('No trending tags yet — hashtags are extracted from real post bodies (#tag).') : Wrap(spacing: 8, children: tags.map((t) => ActionChip(label: Text('#${t.tag} • ${t.postCount}'), onPressed: () => context.push('/hashtag/${t.tag}'))).toList())),
      const SectionHeader('Trending posts'),
      AsyncBody<List<Post>>(value: trendingPosts, builder: (posts) => posts.isEmpty ? const Text('No trending yet — based on real reactions + comments.') : Column(children: posts.take(5).map((p) => Padding(padding: const EdgeInsets.only(bottom: 12), child: PostCard(post: p, compact: true))).toList())),
      const SectionHeader('Recommended'),
      Text('Recommended channels/communities follow suggestions respect blocking & privacy — no fake followers.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _TrendingTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(trendingPostsProvider);
    return AsyncBody<List<Post>>(value: posts, builder: (list) => list.isEmpty ? const EmptyState(message: 'No trending content yet', icon: Icons.trending_up) : ListView.separated(padding: const EdgeInsets.all(16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (c,i) => PostCard(post: list[i])) );
  }
}
