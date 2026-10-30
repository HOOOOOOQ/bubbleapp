import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';

/// Premium iOS-inspired message bubble with delivery ticks, reply, reactions, pin/star.
///
/// Incoming: light surface with tail left. Outgoing: brand blue gradient.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showAvatar,
    required this.onLongPress,
    required this.onTapReply,
    required this.onTapReaction,
    this.avatarUrl,
    this.displayName,
    this.isVerified = false,
  });

  final MessageModel message;
  final bool isMine;
  final bool showAvatar;
  final VoidCallback onLongPress;
  final VoidCallback onTapReply;
  final VoidCallback onTapReaction;
  final String? avatarUrl;
  final String? displayName;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _SystemBubble(message: message);

    final isDeleted = message.isDeleted;
    final bubbleColor = isDeleted
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : isMine
            ? BubbleColors.blue
            : Theme.of(context).colorScheme.surfaceContainerHigh;
    final textColor = isDeleted
        ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
        : isMine
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;

    final time = message.createdAt != null ? DateFormat('h:mm a').format(message.createdAt!) : '';

    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 48 : 8,
        right: isMine ? 8 : 48,
        top: 2,
        bottom: showAvatar ? 8 : 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMine && showAvatar)
            CircleAvatar(
              radius: 14,
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null ? Text((displayName ?? '?')[0].toUpperCase(), style: const TextStyle(fontSize: 10)) : null,
            )
          else if (!isMine)
            const SizedBox(width: 28),
          const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (message.forwardedFromId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forward, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('Forwarded', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  if (message.replyToId != null && message.replyTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.white.withValues(alpha: 0.18) : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border(left: BorderSide(color: isMine ? Colors.white : BubbleColors.blue, width: 3)),
                      ),
                      child: Text(
                        message.replyTo!.displayBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.9)),
                      ),
                    ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isDeleted ? 14 : 14, vertical: isDeleted ? 10 : 10),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 18),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 1))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMine && !isDeleted && (message.forwardedFrom != null || message.replyTo != null))
                          const SizedBox.shrink(),
                        if (message.isMedia && !isDeleted) _MediaPreview(message: message),
                        if (message.body != null && message.body!.isNotEmpty)
                          Text(
                            isDeleted ? message.displayBody : message.body!,
                            style: TextStyle(color: textColor, fontSize: 15, height: 1.35, fontStyle: isDeleted ? FontStyle.italic : null),
                          ),
                        if (message.attachments.isNotEmpty && message.body == null)
                          for (final att in message.attachments)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _AttachmentChip(attachment: att),
                            ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.isEdited)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text('edited', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7), fontStyle: FontStyle.italic)),
                              ),
                            Text(time, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: isMine ? 0.85 : 0.6))),
                            if (isMine) ...[
                              const SizedBox(width: 6),
                              _DeliveryTicks(status: message.status, isOptimistic: message.isOptimistic),
                            ],
                            if (message.isStarred) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.star, size: 12, color: textColor.withValues(alpha: 0.8)),
                            ],
                            if (message.isPinned) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.push_pin, size: 12, color: textColor.withValues(alpha: 0.8)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          for (final r in message.reactions)
                            GestureDetector(
                              onTap: onTapReaction,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                ),
                                child: Text(r.emoji, style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.message});
  final MessageModel message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Text(message.body ?? '', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      );
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.message});
  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final att = message.attachments.isNotEmpty ? message.attachments.first : null;
    if (att == null) {
      // Fallback: kind-based icon when no attachment row yet.
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(_iconForKind(message.kind), size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(_labelForKind(message.kind), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
    }
    if (att.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(att.storagePath, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _FallbackMedia(kind: message.kind)),
      );
    }
    if (att.isVideo) {
      return _FallbackMedia(kind: 'video', duration: att.durationMs);
    }
    if (att.isAudio) {
      return _VoicePreview(durationMs: att.durationMs);
    }
    return _AttachmentChip(attachment: att);
  }

  IconData _iconForKind(String k) {
    switch (k) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'voice':
        return Icons.mic_outlined;
      case 'document':
        return Icons.description_outlined;
      case 'location':
        return Icons.location_on_outlined;
      case 'contact':
        return Icons.person_outline;
      default:
        return Icons.attach_file;
    }
  }

  String _labelForKind(String k) {
    switch (k) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice':
        return 'Voice message';
      case 'document':
        return 'Document';
      case 'location':
        return 'Location';
      case 'contact':
        return 'Contact';
      default:
        return k;
    }
  }
}

class _FallbackMedia extends StatelessWidget {
  const _FallbackMedia({required this.kind, this.duration});
  final String kind;
  final int? duration;

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(kind == 'video' ? Icons.play_circle_outline : Icons.image_outlined, size: 36, color: Colors.white.withValues(alpha: 0.9)),
          if (duration != null) Text(_fmt(Duration(milliseconds: duration!)), style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment});
  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(attachment.isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined, size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(child: Text(attachment.storagePath.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13))),
          const SizedBox(width: 8),
          Text(_fileSize(attachment.sizeBytes), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        ]),
      );
}

class _VoicePreview extends StatelessWidget {
  const _VoicePreview({this.durationMs});
  final int? durationMs;

  @override
  Widget build(BuildContext context) => Container(
        width: 240,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow, color: BubbleColors.blue, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(child: _WaveformPlaceholder()),
          const SizedBox(width: 8),
          Text(durationMs != null ? _fmt(Duration(milliseconds: durationMs!)) : '0:00', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _WaveformPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(18, (i) {
          final h = [8.0, 14, 6, 18, 10, 16, 8, 12, 20, 10, 14, 8, 16, 6, 12, 18, 10, 14][i];
          return Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), height: h, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(2))));
        }),
      );
}

class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.status, required this.isOptimistic});
  final MessageStatus status;
  final bool isOptimistic;

  @override
  Widget build(BuildContext context) {
    if (isOptimistic) return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white));
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 14, color: Colors.white70);
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 14, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF65C7FF));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: Color(0xFFFF6B6B));
    }
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:$m:$s';
  return '$m:$s';
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
