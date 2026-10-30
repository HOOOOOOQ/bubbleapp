import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../../config/theme.dart';
import '../../../data/social_repository.dart';
import '../../../widgets/common.dart';
import '../../polls/widgets/poll_creator.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.communityId});
  final String? communityId;
  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _body = TextEditingController();
  String _visibility = 'public';
  String _kind = 'text';
  List<String> _mediaPaths = [];
  List<Uint8List> _pendingMedia = [];
  String? _pollId;
  String? _linkUrl;
  bool _busy = false;
  final _picker = ImagePicker();

  Future<void> _pickMedia() async {
    final x = await _picker.pickMultiImage(maxWidth: 1080, imageQuality: 85);
    if (x.isEmpty) return;
    final bytesList = await Future.wait(x.map((e) => e.readAsBytes()));
    setState(() { _pendingMedia.addAll(bytesList); _kind = _pendingMedia.length > 1 ? 'images' : 'image'; });
  }

  Future<void> _submit() async {
    if (_body.text.trim().isEmpty) { showMessage(context, 'Write something'); return; }
    setState(() => _busy = true);
    try {
      final repo = ref.read(socialRepositoryProvider);
      // First create post
      final post = await repo.createPost(
        body: _body.text.trim(),
        kind: _kind,
        mediaPaths: _mediaPaths,
        pollId: _pollId,
        linkUrl: _linkUrl,
        communityId: widget.communityId,
        visibility: _visibility,
      );
      // Upload pending media if any
      for (final bytes in _pendingMedia) {
        final path = await repo.uploadPostMedia(post.id, bytes, 'image/jpeg', 'jpg');
        _mediaPaths.add(path);
      }
      if (_mediaPaths.isNotEmpty) {
        await repo.updatePostMedia(post.id, _mediaPaths);
      }
      if (mounted) { showMessage(context, 'Posted'); context.pop(); }
    } catch (e) { if (mounted) showMessage(context, 'Failed: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create post'), actions: [TextButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post'))]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.communityId != null) GlassCard(child: Row(children: [const Icon(Icons.groups_outlined), const SizedBox(width: 8), Text('Posting to community ${widget.communityId!.substring(0,8)}', style: const TextStyle(fontWeight: FontWeight.w600))])),
          TextField(controller: _body, maxLines: 6, decoration: const InputDecoration(hintText: 'What\'s on your mind? Use #hashtags and @mentions', border: InputBorder.none), style: const TextStyle(fontSize: 16)),
          if (_pendingMedia.isNotEmpty) Wrap(spacing: 8, children: _pendingMedia.map((b) => Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, width: 100, height: 100, fit: BoxFit.cover)), Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => setState(() => _pendingMedia.remove(b)), child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(4), child: const Icon(Icons.close, size: 14, color: Colors.white))))])).toList()),
          const SizedBox(height: 12),
          Row(children: [
            IconButton.outlined(onPressed: _pickMedia, icon: const Icon(Icons.image_outlined)),
            IconButton.outlined(onPressed: () async { final poll = await showDialog<Map<String,dynamic>>(context: context, builder: (_) => const PollCreatorDialog()); if (poll != null) { final created = await ref.read(socialRepositoryProvider).createPoll(question: poll['question'], options: (poll['options'] as List).cast<String>(), allowMultiple: poll['allowMultiple'], expiresAt: poll['expiresAt']); setState(() { _pollId = created.id; _kind = 'poll'; }); } }, icon: const Icon(Icons.poll_outlined)),
            IconButton.outlined(onPressed: () { final ctrl = TextEditingController(text: _linkUrl ?? ''); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Add link'), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://...')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { setState(() => _linkUrl = ctrl.text.trim()); Navigator.pop(ctx); }, child: const Text('Save'))])); }, icon: const Icon(Icons.link)),
            const Spacer(),
            DropdownButton<String>(value: _visibility, items: const [DropdownMenuItem(value: 'public', child: Text('Public')), DropdownMenuItem(value: 'followers', child: Text('Followers')), DropdownMenuItem(value: 'contacts', child: Text('Contacts')), DropdownMenuItem(value: 'private', child: Text('Only me'))], onChanged: (v) => setState(() => _visibility = v!)),
          ]),
          if (_pollId != null) Padding(padding: const EdgeInsets.only(top: 8), child: GlassCard(child: Row(children: [const Icon(Icons.poll, color: BubbleColors.violet), const SizedBox(width: 8), const Text('Poll attached'), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _pollId = null))]))),
          if (_linkUrl != null) Padding(padding: const EdgeInsets.only(top: 8), child: GlassCard(child: Row(children: [const Icon(Icons.link), const SizedBox(width: 8), Expanded(child: Text(_linkUrl!, maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _linkUrl = null))]))),
          const SizedBox(height: 16),
          Text('Posts support text, images, multiple images, video, poll, link preview, shared channel post. Hashtags (#tag) and mentions (@user) are extracted and indexed. Trending uses real engagement (reactions+comments).', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          GradientButton(label: 'Publish', icon: Icons.send_outlined, onPressed: _busy ? null : _submit, busy: _busy),
        ]),
      );
}
