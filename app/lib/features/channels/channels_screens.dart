import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

final channelDetailProvider =
    FutureProvider.autoDispose.family<ChannelModel?, String>((ref, id) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).channel(id);
});

final channelPostsProvider =
    FutureProvider.autoDispose.family<List<ChannelPost>, String>((ref, id) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).channelPosts(id);
});

final channelSubscribedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, id) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).isSubscribed(id);
});

final channelStatsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).channelStats(id);
});

void _refreshChannelLists(WidgetRef ref) {
  ref.invalidate(channelsProvider);
  ref.invalidate(mySubscriptionsProvider);
}

/// Browse channels, subscribe, unsubscribe, or join with an invite code.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final subs = ref.watch(mySubscriptionsProvider).valueOrNull ?? const <ChannelModel>[];
    final subscribedIds = subs.map((c) => c.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channels'),
        actions: [
          IconButton(
            tooltip: 'Join with invite code',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => _joinByInvite(context, ref),
          ),
          IconButton(
            tooltip: 'Create channel',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/channels/new'),
          ),
        ],
      ),
      body: AsyncBody<List<ChannelModel>>(
        value: channels,
        onRetry: () => ref.invalidate(channelsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(message: 'No channels yet. Create one to get started.', icon: Icons.campaign_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = list[i];
              final subscribed = subscribedIds.contains(c.id);
              return GlassCard(
                onTap: () => context.push(c.isOfficial ? '/official' : '/channels/${c.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                            if (c.isVerified) ...[const SizedBox(width: 4), const VerifiedMark()],
                          ]),
                          Text('@${c.username} · ${c.subscriberCount} subscribers'),
                          if (c.isMandatory)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: StatusBadge(label: 'Required for all accounts'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (c.isMandatory)
                      const SizedBox.shrink()
                    else if (subscribed)
                      OutlinedButton(onPressed: () => _unsubscribe(context, ref, c), child: const Text('Leave'))
                    else
                      FilledButton(onPressed: () => _subscribe(context, ref, c), child: const Text('Join')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref, ChannelModel c) async {
    final ok = await runAction(context, () => ref.read(repositoryProvider).subscribe(c.id),
        success: 'Subscribed to ${c.name}');
    if (ok) _refreshChannelLists(ref);
  }

  Future<void> _unsubscribe(BuildContext context, WidgetRef ref, ChannelModel c) async {
    final confirmed = await confirmAction(context,
        title: 'Leave ${c.name}?', body: 'You will stop receiving posts from this channel.', confirmLabel: 'Leave');
    if (!confirmed || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).unsubscribe(c.id),
        success: 'You left ${c.name}');
    if (ok) _refreshChannelLists(ref);
  }

  Future<void> _joinByInvite(BuildContext context, WidgetRef ref) async {
    final code = await promptText(context, title: 'Join with invite code', label: 'Invite code', mandatory: true);
    if (code == null || code.isEmpty || !context.mounted) return;
    final id = await runValue(context, () => ref.read(repositoryProvider).joinChannelByInvite(code),
        success: 'Joined channel');
    _refreshChannelLists(ref);
    if (id != null && context.mounted) context.push('/channels/$id');
  }
}

/// The official @BubbleApp channel. Resolved from the database, never hardcoded by id.
class OfficialChannelScreen extends ConsumerWidget {
  const OfficialChannelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    return AsyncBody<List<ChannelModel>>(
      value: channels,
      onRetry: () => ref.invalidate(channelsProvider),
      builder: (list) {
        final official = list.where((c) => c.isOfficial).firstOrNull;
        if (official == null) {
          return Scaffold(
            appBar: AppBar(title: Text('@${AppConfig.officialChannelUsername}')),
            body: const EmptyState(message: 'The official channel has not been provisioned yet.'),
          );
        }
        return ChannelDetailScreen(channelId: official.id);
      },
    );
  }
}

class ChannelDetailScreen extends ConsumerStatefulWidget {
  const ChannelDetailScreen({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen> {
  final _composer = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _composer.text.trim();
    if (text.isEmpty) {
      showMessage(context, 'Write something before publishing.');
      return;
    }
    setState(() => _posting = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).publishChannelPost(channelId: widget.channelId, body: text),
      success: 'Published',
    );
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) {
      _composer.clear();
      ref.invalidate(channelPostsProvider(widget.channelId));
      ref.invalidate(channelStatsProvider(widget.channelId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.channelId;
    final channel = ref.watch(channelDetailProvider(id));
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(channel.valueOrNull?.name ?? 'Channel'),
        actions: [
          if (channel.valueOrNull != null &&
              !channel.valueOrNull!.isMandatory &&
              (channel.valueOrNull!.ownerId == uid || access.can('channels.manage')))
            IconButton(
              tooltip: 'Delete channel',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(channel.valueOrNull!),
            ),
        ],
      ),
      body: AsyncBody<ChannelModel?>(
        value: channel,
        onRetry: () => ref.invalidate(channelDetailProvider(id)),
        builder: (c) {
          if (c == null) return const EmptyState(message: 'This channel is not available to you.');
          final canManage = c.ownerId == uid || access.can('channels.manage');
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(channelDetailProvider(id));
              ref.invalidate(channelPostsProvider(id));
              ref.invalidate(channelSubscribedProvider(id));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(c.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                        if (c.isVerified) ...[const SizedBox(width: 6), const VerifiedMark(size: 20)],
                      ]),
                      Text('@${c.username} · ${c.subscriberCount} subscribers'),
                      if (c.description.isNotEmpty) ...[const SizedBox(height: 8), Text(c.description)],
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, children: [
                        if (c.isOfficial) const StatusBadge(label: 'Official'),
                        if (c.isMandatory) const StatusBadge(label: 'Required for all accounts'),
                        if (!c.isPublic) const StatusBadge(label: 'Private', color: Colors.orange),
                      ]),
                      const SizedBox(height: 12),
                      _SubscribeControl(channel: c),
                    ],
                  ),
                ),
                if (canManage) ...[
                  const SectionHeader('Publish'),
                  _StatsCard(channelId: id),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _composer,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'New post'),
                  ),
                  const SizedBox(height: 8),
                  GradientButton(label: 'Publish post', icon: Icons.send, onPressed: _publish, busy: _posting),
                ],
                const SectionHeader('Posts'),
                AsyncBody<List<ChannelPost>>(
                  value: ref.watch(channelPostsProvider(id)),
                  onRetry: () => ref.invalidate(channelPostsProvider(id)),
                  builder: (posts) {
                    if (posts.isEmpty) return const EmptyState(message: 'No posts yet.', icon: Icons.article_outlined);
                    return Column(
                      children: [
                        for (final p in posts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PostTile(
                              post: p,
                              canManage: canManage,
                              onChanged: () => ref.invalidate(channelPostsProvider(id)),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(ChannelModel c) async {
    final confirmed = await confirmAction(context,
        title: 'Delete ${c.name}?',
        body: 'Subscribers will lose access and posts will be removed. This cannot be undone.',
        confirmLabel: 'Delete');
    if (!confirmed || !mounted) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).deleteChannel(c.id),
        success: 'Channel deleted');
    if (!ok || !mounted) return;
    _refreshChannelLists(ref);
    context.go('/channels');
  }
}

class _SubscribeControl extends ConsumerWidget {
  const _SubscribeControl({required this.channel});

  final ChannelModel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channel.isMandatory) {
      return const Text('Every account is subscribed to this channel. It cannot be removed.',
          style: TextStyle(fontStyle: FontStyle.italic));
    }
    final subscribed = ref.watch(channelSubscribedProvider(channel.id));
    return AsyncBody<bool>(
      value: subscribed,
      onRetry: () => ref.invalidate(channelSubscribedProvider(channel.id)),
      builder: (isSub) => isSub
          ? OutlinedButton.icon(
              icon: const Icon(Icons.notifications_off_outlined),
              label: const Text('Leave channel'),
              onPressed: () async {
                final ok = await confirmAction(context,
                    title: 'Leave ${channel.name}?', body: 'You will stop receiving posts.', confirmLabel: 'Leave');
                if (!ok || !context.mounted) return;
                final done = await runAction(context, () => ref.read(repositoryProvider).unsubscribe(channel.id),
                    success: 'You left the channel');
                if (done) {
                  _refreshChannelLists(ref);
                  ref.invalidate(channelSubscribedProvider(channel.id));
                }
              },
            )
          : GradientButton(
              label: 'Join channel',
              icon: Icons.notifications_active_outlined,
              onPressed: () async {
                final done = await runAction(context, () => ref.read(repositoryProvider).subscribe(channel.id),
                    success: 'Joined channel');
                if (done) {
                  _refreshChannelLists(ref);
                  ref.invalidate(channelSubscribedProvider(channel.id));
                }
              },
            ),
    );
  }
}

class _StatsCard extends ConsumerWidget {
  const _StatsCard({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(channelStatsProvider(channelId));
    return AsyncBody<Map<String, dynamic>>(
      value: stats,
      onRetry: () => ref.invalidate(channelStatsProvider(channelId)),
      builder: (s) => GlassCard(
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final k in const ['subscribers', 'posts', 'views', 'reactions', 'scheduled'])
              Column(children: [
                Text('${s[k] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(k),
              ]),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends ConsumerStatefulWidget {
  const _PostTile({required this.post, required this.canManage, required this.onChanged});

  final ChannelPost post;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends ConsumerState<_PostTile> {
  @override
  void initState() {
    super.initState();
    // Count one view per visible post; the database de-duplicates per user.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(repositoryProvider).recordPostView(widget.post.id);
      } catch (_) {
        // Views are best-effort analytics; a failure must not interrupt reading.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (p.isPinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 16)),
            Expanded(child: Text(p.publishAt == null ? '' : _formatDate(p.publishAt!),
                style: Theme.of(context).textTheme.labelSmall)),
            Text('${p.viewsCount} views', style: Theme.of(context).textTheme.labelSmall),
            if (widget.canManage)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: p.isPinned ? 'Unpin' : 'Pin',
                icon: Icon(p.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                onPressed: () async {
                  final ok = await runAction(context,
                      () => ref.read(repositoryProvider).setPostPinned(p.id, !p.isPinned));
                  if (ok) widget.onChanged();
                },
              ),
          ]),
          const SizedBox(height: 6),
          Text(p.body ?? ''),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  ConsumerState<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _description = TextEditingController();
  bool _public = true;
  bool _comments = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final id = await runValue(
      context,
      () => ref.read(repositoryProvider).createChannel(
            name: _name.text,
            username: _username.text,
            description: _description.text,
            isPublic: _public,
            commentsEnabled: _comments,
          ),
      success: 'Channel created',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      _refreshChannelLists(ref);
      context.go('/channels/$id');
    }
  }

  @override
  Widget build(BuildContext context) => BubblePage(
        title: 'New channel',
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Channel name'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Use at least 2 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim())
                    ? null
                    : '3–32 letters, numbers or underscores',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public channel'),
                subtitle: const Text('Anyone can find and join. Off means invite-only.'),
                value: _public,
                onChanged: (v) => setState(() => _public = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow comments'),
                value: _comments,
                onChanged: (v) => setState(() => _comments = v),
              ),
              const SizedBox(height: 16),
              GradientButton(label: 'Create channel', icon: Icons.add, onPressed: _create, busy: _busy),
            ],
          ),
        ),
      );
}
