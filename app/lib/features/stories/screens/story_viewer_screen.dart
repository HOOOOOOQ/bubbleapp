import 'dart:async';
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

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.authorId, this.initialStories});
  final String authorId;
  final List<Story>? initialStories;
  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> with TickerProviderStateMixin {
  late List<Story> _stories;
  int _index = 0;
  Timer? _timer;
  AnimationController? _progressController;
  bool _paused = false;
  bool _showReply = false;
  final _replyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stories = widget.initialStories ?? [];
    _startProgress();
    _markViewed();
    if (_stories.isEmpty) _load();
  }

  Future<void> _load() async {
    final stories = await ref.read(socialRepositoryProvider).storiesByAuthor(widget.authorId);
    setState(() => _stories = stories);
    _startProgress();
  }

  void _startProgress() {
    _progressController?.dispose();
    _progressController = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _progressController!.forward().whenComplete(() {
      if (_index < _stories.length - 1) {
        setState(() => _index++);
        _startProgress();
        _markViewed();
      } else {
        if (mounted) context.pop();
      }
    });
    _timer?.cancel();
  }

  void _markViewed() {
    if (_stories.isEmpty) return;
    ref.read(socialRepositoryProvider).viewStory(_stories[_index].id).catchError((_) {});
  }

  void _pause() { setState(() => _paused = true); _progressController?.stop(); }
  void _resume() { setState(() => _paused = false); _progressController?.forward(); }

  @override
  void dispose() { _timer?.cancel(); _progressController?.dispose(); _replyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Stories')), body: const Center(child: CircularProgressIndicator(color: Colors.white)));
    final story = _stories[_index];
    final author = story.author;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 3) {
            if (_index > 0) setState(() => _index--); else _startProgress();
          } else if (d.globalPosition.dx > w * 2 / 3) {
            if (_index < _stories.length - 1) setState(() => _index++); else context.pop();
            _startProgress(); _markViewed();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragEnd: (d) { if (d.primaryVelocity != null && d.primaryVelocity! > 400) context.pop(); },
        child: Stack(children: [
          // Media
          Positioned.fill(child: _StoryMedia(story: story)),
          // Top gradient
          Positioned(top: 0, left: 0, right: 0, child: Container(height: 120, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.6), Colors.transparent])))),
          // Progress
          Positioned(top: MediaQuery.of(context).padding.top + 8, left: 8, right: 8, child: Row(children: List.generate(_stories.length, (i) {
            return Expanded(child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: AnimatedBuilder(animation: _progressController!, builder: (_, __) {
                double value = 0;
                if (i < _index) value = 1;
                else if (i == _index) value = _progressController!.value;
                return ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: value, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 2));
              }),
            ));
          }))),
          // Header
          Positioned(top: MediaQuery.of(context).padding.top + 24, left: 12, right: 12, child: Row(children: [
            CircleAvatar(radius: 18, backgroundImage: author?.avatarUrl != null ? CachedNetworkImageProvider(author!.avatarUrl!) : null, child: author?.avatarUrl == null ? Text((author?.displayName ?? '?')[0]) : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(author?.displayName ?? author?.username ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))), if (author?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedMark(size: 14))]),
              Text(_timeAgo(story.createdAt), style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
            ])),
            IconButton(onPressed: () => _showOptions(story), icon: const Icon(Icons.more_horiz, color: Colors.white)),
            IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close, color: Colors.white)),
          ])),
          // Bottom actions
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            padding: EdgeInsets.fromLTRB(12, 16, 12, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.7), Colors.transparent])),
            child: Column(children: [
              if (story.caption != null && story.caption!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(story.caption!, style: const TextStyle(color: Colors.white, fontSize: 15), textAlign: TextAlign.center)),
              Row(children: [
                Expanded(child: GestureDetector(onTap: () => setState(() => _showReply = !_showReply), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white24)), child: const Text('Reply...', style: TextStyle(color: Colors.white70))))),
                const SizedBox(width: 8),
                _RoundAction(icon: Icons.favorite_border, onTap: () async { await ref.read(socialRepositoryProvider).reactToStory(story.id, '❤️'); if (mounted) showMessage(context, 'Reacted ❤️'); }),
                const SizedBox(width: 8),
                _RoundAction(icon: Icons.send_outlined, onTap: () => _share(story)),
              ]),
              if (_showReply) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
                Expanded(child: TextField(controller: _replyCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Reply to story...', hintStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: () async { if (_replyCtrl.text.trim().isEmpty) return; await ref.read(socialRepositoryProvider).replyToStory(story.id, _replyCtrl.text.trim()); _replyCtrl.clear(); setState(() => _showReply = false); if (mounted) showMessage(context, 'Reply sent'); }, icon: const Icon(Icons.send)),
              ])),
            ]),
          )),
          if (_paused) const Center(child: Icon(Icons.pause_circle_filled, color: Colors.white54, size: 64)),
        ]),
      ),
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  void _showOptions(Story story) {
    showModalBottomSheet(context: context, backgroundColor: Theme.of(context).colorScheme.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.visibility_outlined), title: const Text('View insights'), onTap: () { Navigator.pop(ctx); context.push('/stories/insights/${story.id}'); }),
      ListTile(leading: const Icon(Icons.volume_off_outlined), title: Text('Mute ${story.author?.displayName ?? 'author'}'), onTap: () async { Navigator.pop(ctx); await ref.read(socialRepositoryProvider).muteStoryAuthor(story.authorId); if (mounted) showMessage(context, 'Muted'); }),
      ListTile(leading: const Icon(Icons.block_outlined), title: const Text('Block user'), onTap: () async { Navigator.pop(ctx); await ref.read(socialRepositoryProvider).report(targetType: 'user', targetId: story.authorId, reason: 'Blocked from story'); if (mounted) showMessage(context, 'Blocked'); }),
      ListTile(leading: const Icon(Icons.flag_outlined, color: BubbleColors.danger), title: const Text('Report story', style: TextStyle(color: BubbleColors.danger)), onTap: () { Navigator.pop(ctx); context.push('/reports/new', extra: {'type': 'story', 'id': story.id}); }),
    ]))));
  }
  void _share(Story story) { showMessage(context, 'Share link copied'); }
}

class _StoryMedia extends StatelessWidget {
  const _StoryMedia({required this.story});
  final Story story;
  @override
  Widget build(BuildContext context) {
    final bg = story.backgroundColor != null ? _parseColor(story.backgroundColor!) : null;
    if (story.mediaPath != null && story.mediaPath!.isNotEmpty) {
      // Try to show network image; fallback to placeholder if private path
      final isUrl = story.mediaPath!.startsWith('http');
      return isUrl
          ? CachedNetworkImage(imageUrl: story.mediaPath!, fit: BoxFit.cover, placeholder: (_, __) => Container(color: bg ?? Colors.grey.shade900), errorWidget: (_, __, ___) => Container(color: bg ?? Colors.black, child: Center(child: Text(story.body ?? '', style: const TextStyle(color: Colors.white, fontSize: 22)))) )
          : Container(color: bg ?? Colors.black, child: Center(child: Icon(story.kind == StoryKind.video ? Icons.videocam : Icons.image, color: Colors.white24, size: 80)));
    }
    return Container(
      decoration: BoxDecoration(color: bg, gradient: bg == null ? BubbleColors.premiumGradient : null),
      child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(story.body ?? story.caption ?? '', style: TextStyle(color: story.textColor != null ? _parseColor(story.textColor!) : Colors.white, fontSize: 26, fontWeight: FontWeight.w700), textAlign: TextAlign.center))),
    );
  }
  Color? _parseColor(String hex) {
    try { if (hex.startsWith('#')) return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000); return null; } catch (_) { return null; }
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(icon, color: Colors.white, size: 20)));
}
