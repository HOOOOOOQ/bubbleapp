import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../models/messaging.dart';
import '../../state/messaging_providers.dart';
import '../../widgets/common.dart';
import 'widgets/chat_profile_preview.dart';
import 'widgets/chat_tile.dart';
import '../../core/bubble_error.dart';

/// Full chat list — real conversations from Supabase, with search, filters,
/// folders (archived), unread, pinned, muted, and business label folders.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _segment = 'all'; // all | personal | business | unread
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final text = _searchCtrl.text;
    final notifier = ref.read(chatListProvider.notifier);
    notifier.setFilter(notifier.state.filter.copyWith(search: text));
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(chatListProvider.notifier).loadMore();
    }
  }

  void _setSegment(String s) {
    setState(() => _segment = s);
    final notifier = ref.read(chatListProvider.notifier);
    if (s == 'unread') {
      notifier.setFilter(notifier.state.filter.copyWith(unreadOnly: true, kind: null));
    } else if (s == 'personal') {
      notifier.setFilter(notifier.state.filter.copyWith(unreadOnly: false, kind: 'direct'));
    } else if (s == 'business') {
      notifier.setFilter(notifier.state.filter.copyWith(unreadOnly: false, kind: 'group'));
    } else {
      notifier.setFilter(notifier.state.filter.copyWith(unreadOnly: false, kind: null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatListProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/chats/search'), tooltip: 'Search'),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'new_chat') context.push('/chats/new');
              if (v == 'new_group') context.push('/chats/new-group');
              if (v == 'archived') {
                setState(() => _showArchived = !_showArchived);
                ref.read(chatListProvider.notifier).setFilter(state.filter.copyWith(archived: _showArchived));
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'new_chat', child: Row(children: [Icon(Icons.person_add_outlined, size: 18), SizedBox(width: 10), Text('New chat')])),
              const PopupMenuItem(value: 'new_group', child: Row(children: [Icon(Icons.group_add_outlined, size: 18), SizedBox(width: 10), Text('New group')])),
              PopupMenuItem(value: 'archived', child: Row(children: [Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18), SizedBox(width: 10), Text(_showArchived ? 'Show active' : 'Archived')])),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search conversations, messages, users…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchCtrl.clear()) : null,
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          // Filter chips
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(label: 'All', selected: _segment == 'all', onTap: () => _setSegment('all')),
                _FilterChip(label: 'Unread', selected: _segment == 'unread', count: state.totalUnread, onTap: () => _setSegment('unread')),
                _FilterChip(label: 'Personal', selected: _segment == 'personal', onTap: () => _setSegment('personal')),
                _FilterChip(label: 'Groups', selected: _segment == 'business', onTap: () => _setSegment('business')),
                _FilterChip(label: _showArchived ? 'Active' : 'Archived', selected: _showArchived, icon: Icons.archive_outlined, onTap: () {
                  setState(() => _showArchived = !_showArchived);
                  ref.read(chatListProvider.notifier).setFilter(state.filter.copyWith(archived: _showArchived));
                }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(chatListProvider.notifier).refresh(),
              child: _buildList(context, state),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/chats/new'),
        backgroundColor: BubbleColors.blue,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildList(BuildContext context, ChatListState state) {
    if (state.isLoading && state.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.conversations.isEmpty) {
      return ErrorView(error: state.error!, onRetry: () => ref.read(chatListProvider.notifier).refresh());
    }
    if (state.conversations.isEmpty) {
      return ListView(
        controller: _scrollCtrl,
        children: [
          const SizedBox(height: 60),
          EmptyState(
            message: state.filter.search.isNotEmpty ? 'No results for "${state.filter.search}"' : (_showArchived ? 'No archived chats' : (state.filter.unreadOnly ? 'No unread chats' : 'No conversations yet. Start a new chat!')),
            icon: Icons.chat_bubble_outline,
          ),
          if (state.filter.search.isEmpty && !_showArchived)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: FilledButton.icon(icon: const Icon(Icons.person_add_outlined), label: const Text('Start a chat'), onPressed: () => context.push('/chats/new')),
            ),
        ],
      );
    }

    final pinned = state.pinned;
    final regular = state.regular;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
      itemCount: regular.length + pinned.length + (pinned.isNotEmpty ? 2 : 0) + 1,
      itemBuilder: (ctx, i) {
        // Pinned section
        if (pinned.isNotEmpty) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(children: [
                Icon(Icons.push_pin, size: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Pinned', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ]),
            );
          }
          if (i <= pinned.length) {
            final c = pinned[i - 1];
            return _ChatRow(conversation: c);
          }
          if (i == pinned.length + 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text('Messages', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            );
          }
          final c = regular[i - pinned.length - 2];
          return _ChatRow(conversation: c);
        }

        if (i >= regular.length) {
          // Loading more indicator
          if (state.hasMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          return const SizedBox(height: 16);
        }
        final c = regular[i];
        return _ChatRow(conversation: c);
      },
    );
  }
}

class _ChatRow extends ConsumerWidget {
  const _ChatRow({required this.conversation});
  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(conversation.id),
      background: Container(
        decoration: BoxDecoration(color: BubbleColors.success, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.push_pin, color: Colors.white),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(color: BubbleColors.danger, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          // Pin/unpin
          final repo = ref.read(messagingRepositoryProvider);
          await repo.updateMemberState(conversation.id, pinned: !conversation.isPinned);
          ref.invalidate(chatListProvider);
          return false;
        } else {
          // Archive
          final ok = await confirmAction(context, title: 'Archive chat?', body: 'You can find it in Archived later.', confirmLabel: 'Archive');
          if (ok) {
            await ref.read(messagingRepositoryProvider).updateMemberState(conversation.id, archived: true);
            ref.invalidate(chatListProvider);
          }
          return false;
        }
      },
      child: ChatTile(
        conversation: conversation,
        onTap: () => context.push('/chats/${conversation.id}'),
        onLongPress: () => ChatProfilePreview.show(
          context,
          conversation: conversation,
          isOnline: false, // Resolved via presence provider in detail; list uses cached.
          onMessage: () => context.push('/chats/${conversation.id}'),
          onVoiceCall: () async {
            final repo = ref.read(messagingRepositoryProvider);
            try {
              await repo.startCall(conversationId: conversation.id, media: 'voice');
              if (context.mounted) showMessage(context, 'Calling…');
            } catch (e) {
              if (context.mounted) showMessage(context, friendlyError(e));
            }
          },
          onVideoCall: () async {
            final repo = ref.read(messagingRepositoryProvider);
            try {
              await repo.startCall(conversationId: conversation.id, media: 'video');
              if (context.mounted) showMessage(context, 'Video calling…');
            } catch (e) {
              if (context.mounted) showMessage(context, friendlyError(e));
            }
          },
          onViewProfile: () => context.push('/chats/${conversation.id}'),
          onMute: () async {
            await ref.read(messagingRepositoryProvider).updateMemberState(conversation.id, muted: !conversation.isMuted);
            ref.invalidate(chatListProvider);
          },
          onArchive: () async {
            await ref.read(messagingRepositoryProvider).updateMemberState(conversation.id, archived: !conversation.isArchived);
            ref.invalidate(chatListProvider);
          },
          onPin: () async {
            await ref.read(messagingRepositoryProvider).updateMemberState(conversation.id, pinned: !conversation.isPinned);
            ref.invalidate(chatListProvider);
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, this.count, this.icon, required this.onTap});
  final String label;
  final bool selected;
  final int? count;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onTap(),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
            Text(label),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: selected ? Colors.white : BubbleColors.blue, borderRadius: BorderRadius.circular(10)), child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? BubbleColors.blue : Colors.white))),
            ],
          ]),
          selectedColor: BubbleColors.blue,
          labelStyle: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      );
}
