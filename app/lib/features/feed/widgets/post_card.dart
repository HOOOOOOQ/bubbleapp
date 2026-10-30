import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../widgets/common.dart';
import '../../polls/widgets/poll_widget.dart';

class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.compact = false, this.onRefresh});
  final Post post; final bool compact; final VoidCallback? onRefresh;
  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _liking = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final author = p.author;
    return GlassCard(
      onTap: () => context.push('/feed/${p.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundImage: author?.avatarUrl != null ? CachedNetworkImageProvider(author!.avatarUrl!) : null, child: author?.avatarUrl == null ? Text((author?.displayName ?? 'U')[0]) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(author?.displayName ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)), if (author?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedMark(size: 14))]),
            Text('@${author?.username ?? ''} • ${_timeAgo(p.createdAt)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ])),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => _showPostMenu(p)),
          if (p.isPinned) const StatusBadge(label: 'Pinned'),
        ]),
        if (p.body != null && p.body!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: _LinkedText(text: p.body!, onHashtag: (tag) => context.push('/hashtag/$tag'), onMention: (user) => context.push('/user/$user'))),
        if (p.mediaPaths.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _MediaGrid(paths: p.mediaPaths))),
        if (p.linkUrl != null) Padding(padding: const EdgeInsets.only(top: 10), child: _LinkPreview(url: p.linkUrl!, preview: p.linkPreview)),
        if (p.pollId != null) Padding(padding: const EdgeInsets.only(top: 10), child: PollWidget(pollId: p.pollId!)),
        if (p.sharedPostId != null) Padding(padding: const EdgeInsets.only(top: 10), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.repeat, size: 16), const SizedBox(width: 6), Expanded(child: Text('Shared post ${p.sharedPostId!.substring(0,8)}', style: const TextStyle(fontSize: 12)))]))),
        Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
          _Action(icon: p.myReaction == '❤️' ? Icons.favorite : Icons.favorite_border, color: p.myReaction != null ? BubbleColors.danger : null, label: p.reactionCount > 0 ? '${p.reactionCount}' : 'Like', onTap: () async { setState(() => _liking = true); try { if (p.myReaction != null) { await ref.read(socialRepositoryProvider).unreactToPost(p.id, p.myReaction!); } else { await ref.read(socialRepositoryProvider).reactToPost(p.id, '❤️'); } widget.onRefresh?.call(); } catch (e) { if (mounted) showMessage(context, friendlyError(e)); } finally { if (mounted) setState(() => _liking = false); } }),
          const SizedBox(width: 16),
          _Action(icon: Icons.chat_bubble_outline, label: p.commentCount > 0 ? '${p.commentCount}' : 'Comment', onTap: () => context.push('/feed/${p.id}')),
          const SizedBox(width: 16),
          _Action(icon: p.isBookmarked ? Icons.bookmark : Icons.bookmark_border, label: 'Save', onTap: () async { if (p.isBookmarked) await ref.read(socialRepositoryProvider).unbookmarkPost(p.id); else await ref.read(socialRepositoryProvider).bookmarkPost(p.id); widget.onRefresh?.call(); }),
          const Spacer(),
          _Action(icon: Icons.share_outlined, label: 'Share', onTap: () async { await ref.read(socialRepositoryProvider).sharePost(p.id); if (mounted) showMessage(context, 'Shared to your feed'); widget.onRefresh?.call(); }),
        ])),
      ]),
    );
  }

  void _showPostMenu(Post p) {
    final isOwn = ref.read(socialRepositoryProvider).uid == p.authorId;
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (isOwn) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit post'), onTap: () { Navigator.pop(ctx); _editPost(p); }),
      if (isOwn) ListTile(leading: const Icon(Icons.delete_outline, color: BubbleColors.danger), title: const Text('Delete post', style: TextStyle(color: BubbleColors.danger)), onTap: () async { Navigator.pop(ctx); await runAction(context, () => ref.read(socialRepositoryProvider).deletePost(p.id), success: 'Deleted'); widget.onRefresh?.call(); }),
      if (isOwn) ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(p.isPinned ? 'Unpin' : 'Pin'), onTap: () async { Navigator.pop(ctx); await ref.read(socialRepositoryProvider).pinPost(p.id, !p.isPinned); widget.onRefresh?.call(); }),
      ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Report'), onTap: () { Navigator.pop(ctx); context.push('/reports/new', extra: {'type': 'post', 'id': p.id}); }),
      ListTile(leading: const Icon(Icons.visibility_outlined), title: const Text('View profile'), onTap: () { Navigator.pop(ctx); context.push('/user/${p.authorId}'); }),
    ])));
  }

  void _editPost(Post p) {
    final ctrl = TextEditingController(text: p.body ?? '');
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Edit post'), content: TextField(controller: ctrl, maxLines: 4), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async { Navigator.pop(ctx); await runAction(context, () => ref.read(socialRepositoryProvider).editPost(p.id, ctrl.text), success: 'Updated'); widget.onRefresh?.call(); }, child: const Text('Save'))]));
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, this.label, this.color, required this.onTap});
  final IconData icon; final String? label; final Color? color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Row(children: [Icon(icon, size: 18, color: color), if (label != null) ...[const SizedBox(width: 4), Text(label!, style: TextStyle(fontSize: 12, color: color))]])));
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.paths});
  final List<String> paths;
  @override
  Widget build(BuildContext context) {
    if (paths.length == 1) return CachedNetworkImage(imageUrl: paths.first, fit: BoxFit.cover, height: 220, width: double.infinity, errorWidget: (_, __, ___) => Container(height: 220, color: Theme.of(context).colorScheme.surfaceVariant, child: const Icon(Icons.image_outlined)));
    return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1), itemCount: paths.length, itemBuilder: (c,i) => ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: paths[i], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceVariant))));
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.url, this.preview});
  final String url; final Map<String, dynamic>? preview;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor)), child: Row(children: [const Icon(Icons.link, size: 18), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(preview?['title'] ?? url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))]))]));
}

class _LinkedText extends StatelessWidget {
  const _LinkedText({required this.text, required this.onHashtag, required this.onMention});
  final String text; final void Function(String tag) onHashtag; final void Function(String user) onMention;
  @override
  Widget build(BuildContext context) {
    // Simple: render whole text, plus interactive chips for hashtags/mentions extracted
    final hashtags = RegExp(r'#([a-zA-Z0-9_]{2,64})').allMatches(text).map((m) => m.group(1)!).toSet();
    final mentions = RegExp(r'@([a-zA-Z0-9_]{3,32})').allMatches(text).map((m) => m.group(1)!).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
      if (hashtags.isNotEmpty || mentions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [
        for (final h in hashtags) ActionChip(label: Text('#$h', style: const TextStyle(fontSize: 12)), onPressed: () => onHashtag(h), backgroundColor: BubbleColors.blue.withOpacity(0.1)),
        for (final m in mentions) ActionChip(label: Text('@$m', style: const TextStyle(fontSize: 12)), onPressed: () => onMention(m)),
      ])),
    ]);
  }
}
