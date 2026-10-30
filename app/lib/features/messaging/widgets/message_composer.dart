import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';

/// Premium message composer: text field, emoji, attachments, camera, voice.
///
/// - Expands with content (up to 5 lines) then scrolls.
/// - Voice button morphs to send when text is present.
/// - Shows reply preview when replying.
/// - Shows upload progress when present.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSendText,
    required this.onSendMedia,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickDocument,
    required this.onPickLocation,
    required this.onPickContact,
    required this.onStartVoice,
    this.replyTo,
    this.onCancelReply,
    this.onSchedule,
    this.enabled = true,
  });

  final ValueChanged<String> onSendText;
  final void Function({required String kind, String? body, required String fileName, required String mimeType, required List<int> bytes}) onSendMedia;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickDocument;
  final VoidCallback onPickLocation;
  final VoidCallback onPickContact;
  final VoidCallback onStartVoice;
  final MessageModel? replyTo;
  final VoidCallback? onCancelReply;
  final ValueChanged<DateTime>? onSchedule;
  final bool enabled;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _showAttach = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // Quick-reply shortcut: /shortcuts handled server-side; we pass text as-is.
    widget.onSendText(text);
    _controller.clear();
    setState(() => _showAttach = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyTo != null) _ReplyPreview(message: widget.replyTo!, onCancel: widget.onCancelReply ?? () {}),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)))),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attach button
                IconButton(
                  icon: Icon(_showAttach ? Icons.close : Icons.add, color: scheme.primary),
                  onPressed: widget.enabled ? () => setState(() => _showAttach = !_showAttach) : null,
                  style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                ),
                const SizedBox(width: 6),
                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            enabled: widget.enabled,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: widget.enabled ? 'Message…' : 'You cannot message this chat',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        // Emoji (stub — opens system emoji via keyboard; full picker is an upgrade path)
                        IconButton(
                          icon: Icon(Icons.emoji_emotions_outlined, color: scheme.onSurfaceVariant, size: 22),
                          onPressed: widget.enabled
                              ? () {
                                  // Focus text field to show system emoji keyboard on mobile.
                                  _focus.requestFocus();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send / Voice morph
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _canSend
                      ? _SendButton(onTap: _send)
                      : _VoiceButton(onTap: widget.onStartVoice, enabled: widget.enabled),
                ),
              ],
            ),
          ),
        ),
        if (_showAttach) _AttachSheet(
          onImage: () { setState(() => _showAttach = false); widget.onPickImage(); },
          onVideo: () { setState(() => _showAttach = false); widget.onPickVideo(); },
          onDocument: () { setState(() => _showAttach = false); widget.onPickDocument(); },
          onLocation: () { setState(() => _showAttach = false); widget.onPickLocation(); },
          onContact: () { setState(() => _showAttach = false); widget.onPickContact(); },
          onSchedule: widget.onSchedule == null ? null : () => _pickSchedule(context),
        ),
      ],
    );
  }

  Future<void> _pickSchedule(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !context.mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (dt.isBefore(DateTime.now().add(const Duration(seconds: 30)))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule at least 30 seconds in the future')));
      return;
    }
    setState(() => _showAttach = false);
    widget.onSchedule?.call(dt);
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(gradient: BubbleColors.brandGradient, shape: BoxShape.circle),
          child: const Icon(Icons.send, color: Colors.white, size: 18),
        ),
      );
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: enabled ? BubbleColors.blue : Theme.of(context).colorScheme.surfaceContainerHigh, shape: BoxShape.circle),
          child: Icon(Icons.mic, color: enabled ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
        ),
      );
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.onCancel});
  final MessageModel message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        child: Row(children: [
          Container(width: 3, height: 36, decoration: BoxDecoration(color: BubbleColors.blue, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message.sender?.displayName ?? 'Message', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BubbleColors.blue)),
            Text(message.displayBody, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ])),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onCancel),
        ]),
      );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.onImage, required this.onVideo, required this.onDocument, required this.onLocation, required this.onContact, this.onSchedule});
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onDocument;
  final VoidCallback onLocation;
  final VoidCallback onContact;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _AttachItem(icon: Icons.photo_outlined, label: 'Gallery', color: const Color(0xFF9065FF), onTap: onImage),
              _AttachItem(icon: Icons.videocam_outlined, label: 'Video', color: const Color(0xFF398BFF), onTap: onVideo),
              _AttachItem(icon: Icons.description_outlined, label: 'Document', color: const Color(0xFFF59E0B), onTap: onDocument),
              _AttachItem(icon: Icons.location_on_outlined, label: 'Location', color: BubbleColors.success, onTap: onLocation),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _AttachItem(icon: Icons.person_outline, label: 'Contact', color: const Color(0xFF65C7FF), onTap: onContact),
              if (onSchedule != null) _AttachItem(icon: Icons.schedule_outlined, label: 'Schedule', color: BubbleColors.indigo, onTap: onSchedule!),
              const SizedBox(width: 56),
              const SizedBox(width: 56),
            ]),
          ],
        ),
      );
}

class _AttachItem extends StatelessWidget {
  const _AttachItem({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Column(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 26)),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ]),
      );
}
