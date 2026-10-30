import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../models/social.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';

/// Premium stories tray — horizontal avatars with gradient rings, Liquid Glass card.
class StoriesTray extends ConsumerWidget {
  const StoriesTray({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesFeedProvider);
    return AsyncBody<List<Story>>(
      value: storiesAsync,
      builder: (stories) {
        // Group by author for tray (show latest per author)
        final byAuthor = <String, List<Story>>{};
        for (final s in stories) {
          byAuthor.putIfAbsent(s.authorId, () => []).add(s);
        }
        final authors = byAuthor.entries.toList();
        if (authors.isEmpty) {
          return _EmptyTray(onCreate: () => context.push('/stories/create'));
        }
        return SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: authors.length + 1, // +1 for create
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == 0) return _CreateStoryTile();
              final entry = authors[i - 1];
              final authorStories = entry.value;
              final latest = authorStories.first;
              final author = latest.author;
              return _StoryAvatar(
                name: author?.displayName ?? author?.username ?? 'User',
                avatarUrl: author?.avatarUrl,
                isVerified: author?.isVerified ?? false,
                count: authorStories.length,
                onTap: () => context.push('/stories/view/${latest.authorId}', extra: authorStories),
              );
            },
          ),
        );
      },
    );
  }
}

class _CreateStoryTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/stories/create'),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BubbleColors.brandGradient,
            boxShadow: [BoxShadow(color: BubbleColors.blue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 6),
        Text('Your story', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({required this.name, this.avatarUrl, required this.isVerified, required this.count, required this.onTap});
  final String name; final String? avatarUrl; final bool isVerified; final int count; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Stack(alignment: Alignment.bottomRight, children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: BubbleColors.premiumGradient,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl!) : null,
                child: avatarUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null,
              ),
            ),
          ),
          if (isVerified) const Positioned(right: 2, bottom: 2, child: VerifiedMark(size: 14)),
          if (count > 1)
            Positioned(
              bottom: 0, left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: BubbleColors.violet, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        SizedBox(width: 68, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _EmptyTray extends StatelessWidget {
  const _EmptyTray({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: GlassCard(
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, gradient: BubbleColors.brandGradient), child: const Icon(Icons.auto_stories, color: Colors.white)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Stories', style: TextStyle(fontWeight: FontWeight.w700)), Text('Share a moment that disappears in 24 hours', style: TextStyle(fontSize: 12))])),
            FilledButton(onPressed: onCreate, child: const Text('Create')),
          ]),
        ),
      );
}
