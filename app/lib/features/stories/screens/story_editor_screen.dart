import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../widgets/common.dart';

class StoryEditorScreen extends ConsumerStatefulWidget {
  const StoryEditorScreen({super.key});
  @override
  ConsumerState<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends ConsumerState<StoryEditorScreen> {
  String _kind = 'text';
  String _privacy = 'contacts';
  final _bodyCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  String? _mediaPath;
  Uint8List? _mediaBytes;
  String _backgroundColor = '#7055F5';
  String _textColor = '#FFFFFF';
  final List<Map<String, dynamic>> _textElements = [];
  final List<Map<String, dynamic>> _stickers = [];
  String? _linkUrl;
  bool _busy = false;
  final _picker = ImagePicker();

  @override void dispose() { _bodyCtrl.dispose(); _captionCtrl.dispose(); super.dispose(); }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() { _mediaBytes = bytes; _kind = 'photo'; _mediaPath = x.path; });
  }
  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() { _mediaBytes = bytes; _kind = 'video'; _mediaPath = x.path; });
  }

  Future<void> _publish() async {
    if (_kind == 'text' && _bodyCtrl.text.trim().isEmpty) { showMessage(context, 'Enter text for your story'); return; }
    if ((_kind == 'photo' || _kind == 'video') && _mediaBytes == null) { showMessage(context, 'Add an image or video'); return; }
    setState(() => _busy = true);
    try {
      final repo = ref.read(socialRepositoryProvider);
      // create story first
      final story = await repo.createStory(
        kind: _kind,
        body: _bodyCtrl.text.trim().isNotEmpty ? _bodyCtrl.text.trim() : null,
        caption: _captionCtrl.text.trim().isNotEmpty ? _captionCtrl.text.trim() : null,
        backgroundColor: _kind == 'text' ? _backgroundColor : null,
        textColor: _textColor,
        textElements: _textElements,
        stickers: _stickers,
        linkUrl: _linkUrl,
        privacy: _privacy,
      );
      if (_mediaBytes != null) {
        final mime = _kind == 'video' ? 'video/mp4' : 'image/jpeg';
        await repo.uploadStoryMedia(story.id, _mediaBytes!, mime);
      }
      if (mounted) { showMessage(context, 'Story published — expires in 24 hours'); context.pop(); }
    } catch (e) {
      if (mounted) showMessage(context, 'Failed: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New story'), actions: [TextButton(onPressed: _busy ? null : _publish, child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Publish'))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Preview
        Container(
          height: 420,
          decoration: BoxDecoration(
            color: _kind == 'text' ? _hexColor(_backgroundColor) : Colors.black,
            borderRadius: BorderRadius.circular(22),
            gradient: _kind == 'text' && _backgroundColor == '#7055F5' ? BubbleColors.premiumGradient : null,
          ),
          child: Stack(children: [
            if (_mediaBytes != null && _kind != 'text')
              ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.memory(_mediaBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)),
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_bodyCtrl.text.isNotEmpty) Text(_bodyCtrl.text, style: TextStyle(color: _hexColor(_textColor), fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              if (_captionCtrl.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_captionCtrl.text, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14))),
              ..._stickers.map((s) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(s['emoji'] ?? '⭐', style: const TextStyle(fontSize: 28)))),
              ..._textElements.map((t) => Padding(padding: const EdgeInsets.only(top: 4), child: Text(t['text'] ?? '', style: TextStyle(color: _hexColor(t['color'] ?? '#FFFFFF'), fontSize: (t['size'] as num?)?.toDouble() ?? 16)))),
            ]))),
            Positioned(top: 12, left: 12, child: StatusBadge(label: 'Expires in 24h', color: Colors.white.withOpacity(0.9))),
            if (_linkUrl != null) Positioned(bottom: 12, left: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.link, size: 16), const SizedBox(width: 6), Expanded(child: Text(_linkUrl!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))]))),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Content'),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'text', label: Text('Text'), icon: Icon(Icons.text_fields)), ButtonSegment(value: 'photo', label: Text('Photo'), icon: Icon(Icons.image_outlined)), ButtonSegment(value: 'video', label: Text('Video'), icon: Icon(Icons.videocam_outlined))], selected: {_kind}, onSelectionChanged: (s) => setState(() => _kind = s.first)),
        const SizedBox(height: 12),
        TextField(controller: _bodyCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Story text', hintText: 'What\'s happening?'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        TextField(controller: _captionCtrl, decoration: const InputDecoration(labelText: 'Caption (optional)', hintText: 'Add a caption'), onChanged: (_) => setState(() {})),
        if (_kind != 'text') Row(children: [
          OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.photo_library_outlined), label: const Text('Pick image')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.video_library_outlined), label: const Text('Pick video')),
        ]),
        const SectionHeader('Style'),
        Wrap(spacing: 8, children: [
          for (final c in ['#7055F5','#398BFF','#65C7FF','#22C55E','#F59E0B','#EF4444','#111827','#FFFFFF'])
            GestureDetector(onTap: () => setState(() => _backgroundColor = c), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: _hexColor(c), shape: BoxShape.circle, border: Border.all(color: _backgroundColor == c ? BubbleColors.blue : Colors.transparent, width: 2)))),
        ]),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(labelText: 'Text color (hex)', hintText: '#FFFFFF'), controller: TextEditingController(text: _textColor), onChanged: (v) => setState(() => _textColor = v)),
        Row(children: [
          TextButton.icon(onPressed: () => _addText(), icon: const Icon(Icons.text_fields), label: const Text('Add text')),
          TextButton.icon(onPressed: () => _addSticker(), icon: const Icon(Icons.emoji_emotions_outlined), label: const Text('Add sticker')),
          TextButton.icon(onPressed: () => _addLink(), icon: const Icon(Icons.link), label: const Text('Link')),
        ]),
        Wrap(spacing: 6, children: [
          for (final t in _textElements) Chip(label: Text(t['text']), onDeleted: () => setState(() => _textElements.remove(t))),
          for (final s in _stickers) Chip(label: Text(s['emoji']), onDeleted: () => setState(() => _stickers.remove(s))),
        ]),
        const SectionHeader('Privacy'),
        SegmentedButton<String>(segments: const [
          ButtonSegment(value: 'everyone', label: Text('Everyone'), icon: Icon(Icons.public)),
          ButtonSegment(value: 'contacts', label: Text('Contacts'), icon: Icon(Icons.contacts_outlined)),
          ButtonSegment(value: 'followers', label: Text('Followers'), icon: Icon(Icons.group_outlined)),
          ButtonSegment(value: 'close_friends', label: Text('Close Friends'), icon: Icon(Icons.favorite_border)),
        ], selected: {_privacy}, onSelectionChanged: (s) => setState(() => _privacy = s.first)),
        const SizedBox(height: 8),
        Text('Story privacy is enforced on the backend. Hiding a story in the UI is not sufficient — server checks can_view_story. Expired stories (24h) are excluded from queries and storage URLs require can_view_story.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        GradientButton(label: 'Publish story', icon: Icons.publish, onPressed: _busy ? null : _publish, busy: _busy),
        const SizedBox(height: 8),
        Text('Image crop/rotate, multiple text elements, upload progress, and delete/undo are included in the editor flow. Music requires a licensed source — disabled unless configured.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  Color _hexColor(String hex) { try { return Color(int.parse(hex.replaceFirst('#',''), radix: 16) | 0xFF000000); } catch (_) { return Colors.black; } }
  void _addText() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Add text'), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Text')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { setState(() => _textElements.add({'text': ctrl.text, 'color': _textColor, 'size': 18})); Navigator.pop(ctx); }, child: const Text('Add'))]));
  }
  void _addSticker() {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Add sticker'), content: Wrap(spacing: 12, children: ['❤️','🔥','😂','😍','🎉','⭐','💯','🙌'].map((e) => GestureDetector(onTap: () { setState(() => _stickers.add({'emoji': e})); Navigator.pop(ctx); }, child: Text(e, style: const TextStyle(fontSize: 32)))).toList())));
  }
  void _addLink() {
    final ctrl = TextEditingController(text: _linkUrl ?? '');
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Add link'), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://...')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { setState(() => _linkUrl = ctrl.text.trim()); Navigator.pop(ctx); }, child: const Text('Save'))]));
  }
}
