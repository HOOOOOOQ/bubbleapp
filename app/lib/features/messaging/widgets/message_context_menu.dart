import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../../models/messaging.dart';

/// iOS-style floating contextual menu on long press.
///
/// Appears as an overlay card with emoji reactions on top and actions below,
/// with a blurred backdrop.
class MessageContextMenu extends StatelessWidget {
  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isMine,
    required this.onReact,
    required this.onReply,
    required this.onForward,
    required this.onCopy,
    required this.onEdit,
    required this.onPin,
    required this.onStar,
    required this.onDeleteForMe,
    required this.onDeleteForEveryone,
    required this.onReport,
    required this.onSelect,
    required this.onDismiss,
  });

  final MessageModel message;
  final bool isMine;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onStar;
  final VoidCallback onDeleteForMe;
  final VoidCallback onDeleteForEveryone;
  final VoidCallback onReport;
  final VoidCallback onSelect;
  final VoidCallback onDismiss;

  static const quickEmojis = ['❤️', '😂', '😮', '😢', '🙏', '🔥'];

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.isDeleted;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: InkWell(
        onTap: onDismiss,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emoji reactions bar.
                  if (!isDeleted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20)]),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final emoji in quickEmojis)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                onReact(emoji);
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, shape: BoxShape.circle),
                                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                              ),
                            ),
                          GestureDetector(
                            onTap: () {
                              // Full emoji picker could be shown here.
                              onDismiss();
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, shape: BoxShape.circle),
                              child: const Icon(Icons.add_reaction_outlined, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Message preview (small).
                  Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMine ? BubbleColors.blue : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isDeleted ? 'This message was deleted' : (message.body ?? message.kind),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDeleted ? Theme.of(context).colorScheme.onSurfaceVariant : (isMine ? Colors.white : Theme.of(context).colorScheme.onSurface), fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Actions card.
                  Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20)]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isDeleted) ...[
                          _ActionRow(icon: Icons.reply_outlined, label: 'Reply', onTap: onReply),
                          _ActionRow(icon: Icons.forward_outlined, label: 'Forward', onTap: onForward),
                          _ActionRow(icon: Icons.copy_outlined, label: 'Copy', onTap: onCopy),
                          if (isMine && message.kind == 'text') _ActionRow(icon: Icons.edit_outlined, label: 'Edit', onTap: onEdit),
                          _ActionRow(icon: message.isPinned ? Icons.push_pin_outlined : Icons.push_pin_outlined, label: message.isPinned ? 'Unpin' : 'Pin', onTap: onPin),
                          _ActionRow(icon: message.isStarred ? Icons.star : Icons.star_border, label: message.isStarred ? 'Unstar' : 'Star', onTap: onStar),
                          _ActionRow(icon: Icons.checklist_outlined, label: 'Select', onTap: onSelect),
                          if (!isMine) _ActionRow(icon: Icons.flag_outlined, label: 'Report', onTap: onReport, destructive: false),
                          const Divider(height: 1),
                        ],
                        _ActionRow(icon: Icons.delete_outline, label: 'Delete for me', onTap: onDeleteForMe, destructive: true),
                        if (isMine && !isDeleted) _ActionRow(icon: Icons.delete_forever_outlined, label: 'Delete for everyone', onTap: onDeleteForEveryone, destructive: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cancel.
                  GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
                      child: const Center(child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Icon(icon, size: 20, color: destructive ? BubbleColors.danger : Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: destructive ? BubbleColors.danger : null))),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ]),
        ),
      );
}

/// Helper to show the menu as an overlay route.
Future<void> showMessageContextMenu(
  BuildContext context, {
  required MessageModel message,
  required bool isMine,
  required ValueChanged<String> onReact,
  required VoidCallback onReply,
  required VoidCallback onForward,
  required VoidCallback onCopy,
  required VoidCallback onEdit,
  required VoidCallback onPin,
  required VoidCallback onStar,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteForEveryone,
  required VoidCallback onReport,
  required VoidCallback onSelect,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a, b) => FadeTransition(
        opacity: a,
        child: MessageContextMenu(
          message: message,
          isMine: isMine,
          onReact: (e) {
            Navigator.pop(ctx);
            onReact(e);
          },
          onReply: () {
            Navigator.pop(ctx);
            onReply();
          },
          onForward: () {
            Navigator.pop(ctx);
            onForward();
          },
          onCopy: () {
            Navigator.pop(ctx);
            onCopy();
          },
          onEdit: () {
            Navigator.pop(ctx);
            onEdit();
          },
          onPin: () {
            Navigator.pop(ctx);
            onPin();
          },
          onStar: () {
            Navigator.pop(ctx);
            onStar();
          },
          onDeleteForMe: () {
            Navigator.pop(ctx);
            onDeleteForMe();
          },
          onDeleteForEveryone: () {
            Navigator.pop(ctx);
            onDeleteForEveryone();
          },
          onReport: () {
            Navigator.pop(ctx);
            onReport();
          },
          onSelect: () {
            Navigator.pop(ctx);
            onSelect();
          },
          onDismiss: () => Navigator.pop(ctx),
        ),
      ),
    ),
  );
}
