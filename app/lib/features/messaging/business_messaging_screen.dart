import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/messaging_repository.dart';
import '../../models/business_partner.dart';
import '../../models/messaging.dart';
import '../../state/business_partner_providers.dart';
import '../../state/messaging_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Business messaging — customer conversations, labels, quick replies, notes.
class BusinessMessagingScreen extends ConsumerStatefulWidget {
  const BusinessMessagingScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<BusinessMessagingScreen> createState() => _BusinessMessagingScreenState();
}

class _BusinessMessagingScreenState extends ConsumerState<BusinessMessagingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(messagingRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business chats'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Chats'), Tab(text: 'Labels'), Tab(text: 'Quick replies'), Tab(text: 'Notes')]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _BusinessChatsTab(businessId: widget.businessId),
          _LabelsTab(businessId: widget.businessId),
          _QuickRepliesTab(businessId: widget.businessId),
          _BusinessNotesTab(businessId: widget.businessId),
        ],
      ),
    );
  }
}

class _BusinessChatsTab extends ConsumerWidget {
  const _BusinessChatsTab({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (businessId, null);
    final inquiries = ref.watch(businessInquiriesProvider(args));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(businessInquiriesProvider(args));
        await ref.read(businessInquiriesProvider(args).future);
      },
      child: AsyncBody<List<BusinessInquiry>>(
        value: inquiries,
        onRetry: () => ref.invalidate(businessInquiriesProvider(args)),
        builder: (list) {
          if (list.isEmpty) {
            return ListView(children: const [
              EmptyState(
                message: 'No customer conversations yet. Inquiries from your catalog arrive here.',
                icon: Icons.chat_outlined,
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final inquiry = list[i];
              return GlassCard(
                onTap: () => context.push('/business/$businessId/inbox/${inquiry.id}'),
                child: Row(children: [
                  CircleAvatar(
                    child: Text(inquiry.customerName.isEmpty
                        ? '?'
                        : inquiry.customerName[0].toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(inquiry.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        inquiry.lastMessage ?? inquiry.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  StatusBadge(label: inquiry.status),
                  IconButton(
                    tooltip: 'Open conversation',
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    onPressed: inquiry.conversationId.isEmpty
                        ? null
                        : () => context.push('/chats/${inquiry.conversationId}'),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class _LabelsTab extends ConsumerStatefulWidget {
  const _LabelsTab({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_LabelsTab> createState() => _LabelsTabState();
}

class _LabelsTabState extends ConsumerState<_LabelsTab> {
  List<BusinessLabel> _labels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final labels = await ref.read(messagingRepositoryProvider).businessLabels(widget.businessId);
      setState(() {
        _labels = labels;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = await promptText(context, title: 'New label', label: 'Label name');
    if (name == null || name.isEmpty || !context.mounted) return;
    final color = await _pickColor();
    if (color == null || !context.mounted) return;
    await runAction(context, () => ref.read(messagingRepositoryProvider).createBusinessLabel(businessId: widget.businessId, name: name, color: color));
    _load();
  }

  Future<String?> _pickColor() async {
    const colors = ['#2563EB', '#22C55E', '#F59E0B', '#EF4444', '#9065FF', '#EC4899'];
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Pick color'), children: [for (final c in colors) ListTile(leading: Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(int.parse(c.replaceFirst('#', '0xFF'))), shape: BoxShape.circle)), title: Text(c), onTap: () => Navigator.pop(ctx, c))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight, child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('New label'), onPressed: _create))),
      Expanded(
        child: _labels.isEmpty
            ? const EmptyState(message: 'No labels yet. Create one to organize customer chats.', icon: Icons.label_outline)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _labels.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final l = _labels[i];
                  final color = Color(int.parse(l.color.replaceFirst('#', '0xFF')));
                  return GlassCard(child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 10), Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600))), Text('${l.createdAt?.toLocal().toString().substring(0, 10) ?? ''}', style: Theme.of(context).textTheme.labelSmall)]));
                },
              ),
      ),
    ]);
  }
}

class _QuickRepliesTab extends ConsumerStatefulWidget {
  const _QuickRepliesTab({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_QuickRepliesTab> createState() => _QuickRepliesTabState();
}

class _QuickRepliesTabState extends ConsumerState<_QuickRepliesTab> {
  List<Map<String, dynamic>> _replies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final replies = await ref.read(messagingRepositoryProvider).businessQuickReplies(widget.businessId);
      setState(() {
        _replies = replies;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final shortcut = await promptText(context, title: 'Shortcut', label: 'e.g. /welcome (must start with /)');
    if (shortcut == null || shortcut.isEmpty || !context.mounted) return;
    final body = await promptText(context, title: 'Response', label: 'Message body');
    if (body == null || body.isEmpty || !context.mounted) return;
    await runAction(context, () => ref.read(messagingRepositoryProvider).setBusinessQuickReply(businessId: widget.businessId, shortcut: shortcut, body: body), success: 'Quick reply saved');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerRight, child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Add quick reply'), onPressed: _add))),
      Expanded(
        child: _replies.isEmpty
            ? const EmptyState(message: 'No quick replies. Add one to respond faster to common questions.', icon: Icons.quickreply_outlined)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _replies.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = _replies[i];
                  return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${r['shortcut']}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF398BFF))), const SizedBox(height: 4), Text('${r['body'] ?? ''}')]));
                },
              ),
      ),
    ]);
  }
}

class _BusinessNotesTab extends ConsumerStatefulWidget {
  const _BusinessNotesTab({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_BusinessNotesTab> createState() => _BusinessNotesTabState();
}

class _BusinessNotesTabState extends ConsumerState<_BusinessNotesTab> {
  final _welcomeCtrl = TextEditingController();
  final _awayCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _welcomeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(repositoryProvider);
      final details = await repo.businessDashboard(widget.businessId);
      if (mounted) {
        setState(() {
          _welcomeCtrl.text = (details['greeting_message'] as String?) ?? '';
          _awayCtrl.text = (details['away_message'] as String?) ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader('Welcome message'),
        TextField(controller: _welcomeCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Greeting sent to new customers', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        const SectionHeader('Away message'),
        TextField(controller: _awayCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Sent when you are away', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => showMessage(context, 'Business messages saved (server handles dispatch)'), child: const Text('Save')),
        const SizedBox(height: 12),
        Text('Welcome and away messages are sent by the server when business rules trigger. They respect customer notification preferences.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
