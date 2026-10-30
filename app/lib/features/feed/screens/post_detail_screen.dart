import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../state/social_providers.dart';
import '../../../widgets/common.dart';
import '../widgets/post_card.dart';
import '../widgets/comment_thread.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;
  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  String? _replyTo;
  int _replyDepth = 0;

  @override void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await ref.read(socialRepositoryProvider).addComment(widget.postId, text, parentId: _replyTo);
      _commentCtrl.clear();
      setState(() { _replyTo = null; _replyDepth = 0; });
      ref.invalidate(commentsProvider(widget.postId));
      if (mounted) showMessage(context, 'Comment added');
    } catch (e) { if (mounted) showMessage(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postProvider(widget.postId));
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          AsyncBody<Post?>(value: postAsync, builder: (post) => post == null ? const EmptyState(message: 'Post not found') : PostCard(post: post, onRefresh: () => ref.invalidate(postProvider(widget.postId)))),
          const SizedBox(height: 12),
          const SectionHeader('Comments'),
          AsyncBody<List<Comment>>(value: commentsAsync, builder: (comments) {
            if (comments.isEmpty) return const EmptyState(message: 'No comments yet. Be the first!', icon: Icons.chat_bubble_outline);
            // Build nested thread: top-level then replies
            final topLevel = comments.where((c) => c.parentId == null).toList();
            return Column(children: topLevel.map((c) => CommentThread(comment: c, allComments: comments, onReply: (parent) { setState(() { _replyTo = parent.id; _replyDepth = parent.depth + 1; }); }, onRefresh: () => ref.invalidate(commentsProvider(widget.postId)))).toList());
          }),
        ])),
        Container(padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            if (_replyTo != null) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text('Replying depth $_replyDepth'), onDeleted: () => setState(() => _replyTo = null))),
            Expanded(child: TextField(controller: _commentCtrl, decoration: InputDecoration(hintText: _replyTo == null ? 'Add a comment... Use @mentions' : 'Reply...', suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _sendComment)), onSubmitted: (_) => _sendComment())),
            const SizedBox(width: 8),
            FilledButton(onPressed: _sendComment, child: const Text('Post')),
          ]),
        ),
      ]),
    );
  }
}
