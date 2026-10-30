import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/messaging_repository.dart';
import '../../models/models.dart';
import '../../state/messaging_providers.dart';
import '../../widgets/common.dart';
import '../../core/bubble_error.dart';

/// New chat — search users then create direct conversation.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchCtrl = TextEditingController();
  List<UserProfile> _results = [];
  bool _loading = false;
  bool _creating = false;
  String? _selectedUserId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final users = await ref.read(messagingRepositoryProvider).searchUsers(query);
      setState(() {
        _results = users;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _createDirect(String userId) async {
    setState(() {
      _creating = true;
      _selectedUserId = userId;
    });
    try {
      final id = await ref.read(messagingRepositoryProvider).createDirectConversation(userId);
      ref.invalidate(chatListProvider);
      if (mounted) context.go('/chats/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New chat')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by username or name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
                onSubmitted: _search,
                onChanged: (v) {
                  if (v.trim().length >= 2) _search(v);
                },
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? EmptyState(message: _searchCtrl.text.isEmpty ? 'Search for people to start chatting' : 'No users found for "${_searchCtrl.text}"', icon: Icons.person_search_outlined)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final u = _results[i];
                        final isBusy = _creating && _selectedUserId == u.id;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
                            child: u.avatarUrl == null ? Text((u.displayName.isEmpty ? u.username : u.displayName)[0].toUpperCase()) : null,
                          ),
                          title: Row(children: [Flexible(child: Text(u.displayName.isEmpty ? u.username : u.displayName, style: const TextStyle(fontWeight: FontWeight.w600))), if (u.isVerified) ...[const SizedBox(width: 4), const VerifiedMark(size: 14)]]),
                          subtitle: Text('@${u.username}'),
                          trailing: isBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chat_bubble_outline),
                          onTap: isBusy ? null : () => _createDirect(u.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
}

/// New group — pick title + members then create.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<UserProfile> _results = [];
  final _selected = <UserProfile>[];
  bool _loading = false;
  bool _creating = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final users = await ref.read(messagingRepositoryProvider).searchUsers(q.trim());
      setState(() {
        _results = users.where((u) => !_selected.any((s) => s.id == u.id)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Enter a group name');
      return;
    }
    if (_selected.isEmpty) {
      showMessage(context, 'Add at least one member');
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await ref.read(messagingRepositoryProvider).createGroupConversation(title: title, memberIds: _selected.map((u) => u.id).toList());
      ref.invalidate(chatListProvider);
      if (mounted) context.go('/chats/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New group')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Weekend Trip')),
            const SizedBox(height: 12),
            if (_selected.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in _selected)
                  Chip(
                    label: Text(u.displayName.isEmpty ? u.username : u.displayName),
                    avatar: CircleAvatar(backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null, child: u.avatarUrl == null ? Text((u.displayName.isEmpty ? u.username : u.displayName)[0].toUpperCase()) : null),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _selected.remove(u)),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(labelText: 'Add members', hintText: 'Search users', suffixIcon: _loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_searchCtrl.text))),
              onSubmitted: _search,
            ),
            const SizedBox(height: 8),
            for (final u in _results)
              ListTile(
                leading: CircleAvatar(backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null, child: u.avatarUrl == null ? Text((u.displayName.isEmpty ? u.username : u.displayName)[0].toUpperCase()) : null),
                title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                subtitle: Text('@${u.username}'),
                trailing: const Icon(Icons.add),
                onTap: () => setState(() {
                  _selected.add(u);
                  _results.remove(u);
                  _searchCtrl.clear();
                }),
              ),
            const SizedBox(height: 16),
            GradientButton(label: 'Create group', icon: Icons.group_add_outlined, onPressed: _creating ? null : _create, busy: _creating),
          ],
        ),
      );
}
