import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/messaging_repository.dart';
import '../../models/messaging.dart';
import '../../models/models.dart';
import '../../state/messaging_providers.dart';
import '../../widgets/common.dart';
import 'widgets/chat_tile.dart';
import '../../core/bubble_error.dart';

/// Global search — users, conversations, messages (server-side ilike), channels.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _tab = 'all'; // all | users | chats | messages | channels
  bool _loading = false;
  List<UserProfile> _users = [];
  List<ConversationSummary> _conversations = [];
  List<MessageModel> _messages = [];
  List<ChannelModel> _channels = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _users = [];
        _conversations = [];
        _messages = [];
        _channels = [];
      });
      return;
    }
    setState(() => _loading = true);
    final repo = ref.read(messagingRepositoryProvider);
    try {
      // Parallel search across types (each uses server indexes, not full download).
      final results = await Future.wait([
        repo.searchUsers(query),
        // Conversations filtered by search param (server does prefix match).
        repo.fetchConversations(limit: 20, search: query),
        repo.searchMessagesGlobal(query),
        repo.searchChannels(query),
      ]);
      setState(() {
        _users = results[0] as List<UserProfile>;
        _conversations = results[1] as List<ConversationSummary>;
        _messages = results[2] as List<MessageModel>;
        _channels = results[3] as List<ChannelModel>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _users.isNotEmpty || _conversations.isNotEmpty || _messages.isNotEmpty || _channels.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search users, chats, messages…',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); _search(''); setState(() {}); }) : null,
          ),
          onChanged: (v) {
            setState(() {});
            // Debounce could be added; for now search on submit.
          },
          onSubmitted: _search,
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_ctrl.text))],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _TabChip(label: 'All', selected: _tab == 'all', onTap: () => setState(() => _tab = 'all')),
                _TabChip(label: 'Users', selected: _tab == 'users', count: _users.length, onTap: () => setState(() => _tab = 'users')),
                _TabChip(label: 'Chats', selected: _tab == 'chats', count: _conversations.length, onTap: () => setState(() => _tab = 'chats')),
                _TabChip(label: 'Messages', selected: _tab == 'messages', count: _messages.length, onTap: () => setState(() => _tab = 'messages')),
                _TabChip(label: 'Channels', selected: _tab == 'channels', count: _channels.length, onTap: () => setState(() => _tab = 'channels')),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: hasResults
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_tab == 'all' || _tab == 'users') ...[
                        if (_users.isNotEmpty) ...[
                          const SectionHeader('People'),
                          for (final u in _users) _UserTile(user: u),
                        ],
                      ],
                      if (_tab == 'all' || _tab == 'chats') ...[
                        if (_conversations.isNotEmpty) ...[
                          const SectionHeader('Conversations'),
                          for (final c in _conversations)
                            ChatTile(conversation: c, onTap: () => context.push('/chats/${c.id}'), onLongPress: () {}),
                        ],
                      ],
                      if (_tab == 'all' || _tab == 'messages') ...[
                        if (_messages.isNotEmpty) ...[
                          const SectionHeader('Messages'),
                          for (final m in _messages)
                            ListTile(
                              leading: const Icon(Icons.chat_bubble_outline),
                              title: Text(m.body ?? m.kind, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${m.kind} · ${m.createdAt?.toLocal().toString().substring(0, 16) ?? ''}'),
                              onTap: () => context.push('/chats/${m.conversationId}'),
                            ),
                        ],
                      ],
                      if (_tab == 'all' || _tab == 'channels') ...[
                        if (_channels.isNotEmpty) ...[
                          const SectionHeader('Channels'),
                          for (final ch in _channels)
                            ListTile(
                              leading: const Icon(Icons.campaign_outlined),
                              title: Text(ch.name),
                              subtitle: Text('@${ch.username}'),
                              trailing: ch.isVerified ? const VerifiedMark() : null,
                              onTap: () => context.push(ch.isOfficial ? '/official' : '/channels/${ch.id}'),
                            ),
                        ],
                      ],
                      if (_tab != 'all' && _isEmptyForTab) const EmptyState(message: 'No results in this tab', icon: Icons.search_off),
                    ],
                  )
                : _ctrl.text.isEmpty
                    ? const EmptyState(message: 'Search for people, chats, messages, and channels. Uses server indexes — no full downloads.', icon: Icons.search)
                    : EmptyState(message: 'No results for "${_ctrl.text}"', icon: Icons.search_off),
          ),
        ],
      ),
    );
  }

  bool get _isEmptyForTab {
    switch (_tab) {
      case 'users':
        return _users.isEmpty;
      case 'chats':
        return _conversations.isEmpty;
      case 'messages':
        return _messages.isEmpty;
      case 'channels':
        return _channels.isEmpty;
      default:
        return false;
    }
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        leading: CircleAvatar(
          backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
          child: user.avatarUrl == null ? Text(user.displayName.isEmpty ? user.username[0].toUpperCase() : user.displayName[0].toUpperCase()) : null,
        ),
        title: Row(children: [Flexible(child: Text(user.displayName.isEmpty ? user.username : user.displayName, style: const TextStyle(fontWeight: FontWeight.w600))), if (user.isVerified) ...[const SizedBox(width: 4), const VerifiedMark(size: 14)]]),
        subtitle: Text('@${user.username}'),
        trailing: FilledButton(
          onPressed: () async {
            final repo = ref.read(messagingRepositoryProvider);
            try {
              final id = await repo.createDirectConversation(user.id);
              if (context.mounted) context.push('/chats/$id');
            } catch (e) {
              if (context.mounted) showMessage(context, friendlyError(e));
            }
          },
          child: const Text('Chat'),
        ),
      );
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, this.count, required this.onTap});
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onTap(),
          label: Text(count != null && count! > 0 ? '$label ($count)' : label),
        ),
      );
}
