import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Staff console. Tabs are shown only for permissions the signed-in account holds.
/// Each action calls a database function that re-checks permission and rank.
class AdminConsoleScreen extends ConsumerWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final tabs = <_Tab>[
      if (access.can('users.read')) const _Tab('Users', _UsersTab()),
      if (access.can('reports.manage') || access.can('content.moderate'))
        const _Tab('Reports', _ReportsTab()),
      if (access.can('announcements.manage')) const _Tab('Announcements', _AnnouncementsTab()),
      if (access.can('audit.read')) const _Tab('Audit', _AuditTab()),
    ];

    if (tabs.isEmpty) {
      return const BubblePage(
        title: 'Admin console',
        child: EmptyState(message: 'No console sections are available for your permissions.', icon: Icons.lock_outline),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          bottom: TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.label)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.view]),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.view);

  final String label;
  final Widget view;
}

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final _query = TextEditingController();
  String? _status;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() => ref.read(repositoryProvider).adminListUsers(
        query: _query.text,
        status: _status,
      );

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Search username, name or email'),
                onSubmitted: (_) => _reload(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: _status,
              items: const [
                DropdownMenuItem(value: null, child: Text('Any status')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                DropdownMenuItem(value: 'banned', child: Text('Banned')),
              ],
              onChanged: (v) {
                _status = v;
                _reload();
              },
            ),
            IconButton(onPressed: _reload, icon: const Icon(Icons.search)),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              final list = snap.data ?? const [];
              if (list.isEmpty) return const EmptyState(message: 'No users match.');
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final u = list[i];
                  final id = u['id'] as String;
                  final status = (u['account_status'] ?? 'active') as String;
                  final roles = ((u['roles'] as List?) ?? const []).join(', ');
                  return GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${u['display_name'] ?? ''} · @${u['username'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        StatusBadge(label: status, color: status == 'active' ? Colors.green : Colors.red),
                      ]),
                      Text('${u['email'] ?? ''}'),
                      if (roles.isNotEmpty) Text('Roles: $roles', style: Theme.of(context).textTheme.bodySmall),
                      if (access.can('users.manage')) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          if (status != 'suspended')
                            OutlinedButton(
                                onPressed: () => _setStatus(context, id, 'suspended'), child: const Text('Suspend')),
                          if (status != 'banned')
                            OutlinedButton(
                                onPressed: () => _setStatus(context, id, 'banned'), child: const Text('Ban')),
                          if (status != 'active')
                            FilledButton(
                                onPressed: () => _setStatus(context, id, 'active'), child: const Text('Restore')),
                        ]),
                      ],
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _setStatus(BuildContext context, String userId, String status) async {
    String? reason;
    if (status != 'active') {
      reason = await promptText(context, title: 'Reason', label: 'Reason (required)', mandatory: true);
      if (reason == null || reason.isEmpty || !context.mounted) return;
    }
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).adminSetAccountStatus(userId: userId, status: status, reason: reason),
      success: 'Account status updated',
    );
    if (ok) _reload();
  }
}

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(repositoryProvider).reports(status: 'open');
  }

  void _reload() => setState(() => _future = ref.read(repositoryProvider).reports(status: 'open'));

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final canAct = access.can('reports.manage') || access.can('content.moderate');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        final list = snap.data ?? const [];
        if (list.isEmpty) return const EmptyState(message: 'No open reports.', icon: Icons.flag_outlined);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = list[i];
            final id = r['id'] as String;
            return GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['target_type']} · ${r['reason']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((r['details'] as String?)?.isNotEmpty == true) Text('${r['details']}'),
                Text('Status: ${r['status']}', style: Theme.of(context).textTheme.bodySmall),
                if (canAct) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(onPressed: () => _resolve(context, id, 'dismiss'), child: const Text('Dismiss')),
                    OutlinedButton(onPressed: () => _resolve(context, id, 'escalate'), child: const Text('Escalate')),
                    OutlinedButton(onPressed: () => _resolve(context, id, 'warn', needsNote: true), child: const Text('Warn')),
                    OutlinedButton(onPressed: () => _resolve(context, id, 'hide_content', needsNote: true), child: const Text('Hide content')),
                    if (access.can('users.manage'))
                      OutlinedButton(onPressed: () => _resolve(context, id, 'suspend', needsNote: true), child: const Text('Suspend user')),
                  ]),
                ],
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _resolve(BuildContext context, String id, String action, {bool needsNote = false}) async {
    String? note;
    if (needsNote) {
      note = await promptText(context, title: 'Note', label: 'Explain the decision', mandatory: true);
      if (note == null || note.isEmpty || !context.mounted) return;
    }
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).resolveReport(reportId: id, action: action, note: note),
      success: 'Report updated',
    );
    if (ok) _reload();
  }
}

class _AnnouncementsTab extends ConsumerStatefulWidget {
  const _AnnouncementsTab();

  @override
  ConsumerState<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends ConsumerState<_AnnouncementsTab> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'all';
  bool _postToOfficial = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).publishPlatformAnnouncement(
            title: _title.text,
            body: _body.text,
            audience: _audience,
            postToOfficial: _postToOfficial,
          ),
      success: 'Announcement published',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _title.clear();
      _body.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Enter a title' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _body, maxLines: 4, decoration: const InputDecoration(labelText: 'Message'),
                validator: (v) => (v ?? '').trim().length < 5 ? 'Enter a message' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _audience,
              decoration: const InputDecoration(labelText: 'Audience'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Everyone')),
                DropdownMenuItem(value: 'partners', child: Text('Partners')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
              ],
              onChanged: (v) => setState(() => _audience = v ?? 'all'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also post to the official channel'),
              value: _postToOfficial,
              onChanged: (v) => setState(() => _postToOfficial = v),
            ),
            const SizedBox(height: 12),
            GradientButton(label: 'Publish', icon: Icons.campaign_outlined, onPressed: _publish, busy: _busy),
          ],
        ),
      );
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_auditProvider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: rows,
      onRetry: () => ref.invalidate(_auditProvider),
      builder: (list) => list.isEmpty
          ? const EmptyState(message: 'No audit entries yet.', icon: Icons.history)
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final r = list[i];
                return GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['action']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${r['target_type'] ?? ''} ${r['target_id'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                );
              },
            ),
    );
  }
}

final _auditProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).adminAuditLog();
});
