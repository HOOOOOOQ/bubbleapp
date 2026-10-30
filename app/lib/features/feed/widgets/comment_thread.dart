import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../widgets/common.dart';

class CommentThread extends ConsumerWidget {
  const CommentThread({super.key, required this.comment, required this.allComments, required this.onReply, this.onRefresh});
  final Comment comment;
  final List<Comment> allComments;
  final void Function(Comment parent) onReply;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = allComments.where((c) => c.parentId == comment.id).toList();
    return Padding(padding: EdgeInsets.only(left: comment.depth * 12.0, bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 14, backgroundImage: comment.author?.avatarUrl != null ? NetworkImage(comment.author!.avatarUrl!) : null, child: comment.author?.avatarUrl == null ? Text((comment.author?.displayName ?? '?')[0], style: const TextStyle(fontSize: 10)) : null),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(comment.author?.displayName ?? comment.authorId.substring(0,8), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Text('@${comment.author?.username ?? ''}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
          Text(_timeAgo(comment.createdAt), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          PopupMenuButton<String>(onSelected: (v) async { if (v == 'edit') _edit(context, ref); else if (v == 'delete') { await runAction(context, () => ref.read(socialRepositoryProvider).deleteComment(comment.id)); onRefresh?.call(); } else if (v == 'report') showMessage(context, 'Reported'); }, itemBuilder: (_) => [if (ref.read(socialRepositoryProvider).uid == comment.authorId) const PopupMenuItem(value: 'edit', child: Text('Edit')), if (ref.read(socialRepositoryProvider).uid == comment.authorId || true) const PopupMenuItem(value: 'delete', child: Text('Delete')), const PopupMenuItem(value: 'report', child: Text('Report'))]),
        ]),
        const SizedBox(height: 6),
        Text(comment.body, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Row(children: [
          InkWell(onTap: () async { await ref.read(socialRepositoryProvider).reactToComment(comment.id, '❤️'); onRefresh?.call(); }, child: Row(children: [Icon(comment.myReaction != null ? Icons.favorite : Icons.favorite_border, size: 14, color: comment.myReaction != null ? Colors.red : null), const SizedBox(width: 4), Text('${comment.reactionCount > 0 ? comment.reactionCount : ''} Like', style: const TextStyle(fontSize: 12))])),
          const SizedBox(width: 12),
          InkWell(onTap: () => onReply(comment), child: const Row(children: [Icon(Icons.reply_outlined, size: 14), SizedBox(width: 4), Text('Reply', style: TextStyle(fontSize: 12))])),
          if (comment.isEdited) Padding(padding: const EdgeInsets.only(left: 8), child: Text('edited', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ]),
      ])),
      ...replies.map((r) => CommentThread(comment: r, allComments: allComments, onReply: onReply, onRefresh: onRefresh)),
    ]));
  }

  String _timeAgo(DateTime? dt) { if (dt == null) return ''; final d = DateTime.now().difference(dt); if (d.inMinutes < 1) return 'now'; if (d.inMinutes < 60) return '${d.inMinutes}m'; if (d.inHours < 24) return '${d.inHours}h'; return '${d.inDays}d'; }
  void _edit(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: comment.body);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Edit comment'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async { Navigator.pop(ctx); await runAction(context, () => ref.read(socialRepositoryProvider).editComment(comment.id, ctrl.text)); onRefresh?.call(); }, child: const Text('Save'))]));
  }
}
