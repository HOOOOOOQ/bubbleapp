import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';
import '../../../widgets/common.dart';

/// Chat list row — iOS-style: avatar, name, verified, partner badge, preview, time, unread, pinned/muted.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
    this.presenceOnline = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool presenceOnline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = conversation.otherParticipant;
    final name = conversation.displayName(p?.username ?? 'Unknown');
    final isVerified = p?.isVerified ?? false;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: conversation.isPinned ? scheme.surfaceContainerHigh.withValues(alpha: 0.6) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.surfaceContainerHighest,
                  backgroundImage: (conversation.avatarUrl ?? p?.avatarUrl) != null ? NetworkImage((conversation.avatarUrl ?? p!.avatarUrl)!) : null,
                  child: (conversation.avatarUrl ?? p?.avatarUrl) == null
                      ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))
                      : null,
                ),
                if (presenceOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(color: BubbleColors.success, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (isVerified) ...[const SizedBox(width: 4), const VerifiedMark(size: 14)],
                      if (conversation.isPinned) ...[const SizedBox(width: 4), Icon(Icons.push_pin, size: 12, color: scheme.onSurfaceVariant)],
                      if (conversation.isMuted) ...[const SizedBox(width: 4), Icon(Icons.volume_off, size: 12, color: scheme.onSurfaceVariant)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (conversation.isMuted) Icon(Icons.volume_off, size: 12, color: scheme.onSurfaceVariant),
                      if (conversation.lastMessageKind == 'image') Icon(Icons.image_outlined, size: 13, color: scheme.onSurfaceVariant),
                      if (conversation.lastMessageKind == 'video') Icon(Icons.videocam_outlined, size: 13, color: scheme.onSurfaceVariant),
                      if (conversation.lastMessageKind == 'voice') Icon(Icons.mic_outlined, size: 13, color: scheme.onSurfaceVariant),
                      if (conversation.lastMessageKind != null && conversation.lastMessageKind != 'text') const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _previewText(conversation),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: conversation.unreadCount > 0 ? scheme.onSurface : scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_timeLabel(conversation.lastMessageAt), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                if (conversation.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: BubbleColors.blue, borderRadius: BorderRadius.circular(12)),
                    child: Text('${conversation.unreadCount > 99 ? '99+' : conversation.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  )
                else if (conversation.isPinned)
                  Icon(Icons.push_pin, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _previewText(ConversationSummary c) {
    if (c.lastMessagePreview == null || c.lastMessagePreview!.isEmpty) {
      if (c.isDirect) return 'Tap to start chatting';
      return c.kind == 'group' ? 'Group conversation' : 'No messages yet';
    }
    final kind = c.lastMessageKind;
    if (kind == 'image') return '📷 Photo';
    if (kind == 'video') return '🎥 Video';
    if (kind == 'voice') return '🎙️ Voice message';
    if (kind == 'document') return '📄 Document';
    if (kind == 'location') return '📍 Location';
    if (kind == 'contact') return '👤 Contact';
    if (kind == 'system') return c.lastMessagePreview!;
    return c.lastMessagePreview!;
  }

  String _timeLabel(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return DateFormat('h:mm a').format(t);
    if (diff.inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('M/d/yy').format(t);
  }
}

class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = _label(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  String _label(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(d);
    return DateFormat('MMMM d, y').format(d);
  }
}

class UnreadSeparator extends StatelessWidget {
  const UnreadSeparator({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(children: [
          Expanded(child: Divider(color: BubbleColors.blue.withValues(alpha: 0.4))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: BubbleColors.blue, borderRadius: BorderRadius.circular(12)),
            child: Text('$count unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Divider(color: BubbleColors.blue.withValues(alpha: 0.4))),
        ]),
      );
}

class TypingIndicatorView extends StatelessWidget {
  const TypingIndicatorView({super.key, required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final label = names.length == 1 ? '${names.first} is typing…' : '${names.join(', ')} are typing…';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const _TypingDots(),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(children: List.generate(3, (i) {
          final phase = (_c.value + i * 0.3) % 1.0;
          final scale = 0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
          return Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 6 * scale, height: 6 * scale, decoration: BoxDecoration(color: BubbleColors.blue.withValues(alpha: 0.7 + 0.3 * scale), shape: BoxShape.circle));
        })),
      );
}
