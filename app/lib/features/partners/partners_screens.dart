import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Partner program landing. Partner status is shown from the backend (partner_dashboard).
/// Being a partner grants partner-scoped rights only; it does not make an account an admin.
class PartnersScreen extends ConsumerWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(partnerDashboardProvider);
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    return BubblePage(
      title: 'Partner program',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(partnerDashboardProvider);
          ref.invalidate(myPartnerApplicationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody<PartnerDashboard?>(
              value: dashboard,
              onRetry: () => ref.invalidate(partnerDashboardProvider),
              builder: (d) {
                if (d == null) {
                  return _NotPartner(onApply: () => _apply(context));
                }
                return _PartnerDashboardView(dashboard: d, canManage: access.can('partners.manage'));
              },
            ),
            const SectionHeader('Your applications'),
            AsyncBody<List<PartnerApplication>>(
              value: ref.watch(myPartnerApplicationsProvider),
              onRetry: () => ref.invalidate(myPartnerApplicationsProvider),
              builder: (list) => list.isEmpty
                  ? const EmptyState(message: 'No applications yet.', icon: Icons.handshake_outlined)
                  : Column(children: [
                      for (final a in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            child: Row(children: [
                              Expanded(child: Text(a.organization.isEmpty ? a.partnershipCategory : a.organization)),
                              StatusBadge(label: a.status),
                            ]),
                          ),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  void _apply(BuildContext context) => context.push('/partners/apply');
}

class _NotPartner extends StatelessWidget {
  const _NotPartner({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Become a BubbleApp partner', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('Partners work with BubbleApp on approved programs. Applications are reviewed by staff.'),
            const SizedBox(height: 12),
            GradientButton(label: 'Apply now', icon: Icons.edit_note, onPressed: onApply),
          ],
        ),
      );
}

class _PartnerDashboardView extends ConsumerWidget {
  const _PartnerDashboardView({required this.dashboard, required this.canManage});

  final PartnerDashboard dashboard;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = dashboard.status == 'active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(dashboard.displayName, style: Theme.of(context).textTheme.titleMedium)),
                StatusBadge(label: dashboard.status, color: active ? Colors.green : Colors.orange),
              ]),
              Text('Category: ${dashboard.category}'),
              if (dashboard.statusReason != null && dashboard.statusReason!.isNotEmpty)
                Text('Reason: ${dashboard.statusReason}'),
              const SizedBox(height: 8),
              Text('Partner rights: ${dashboard.permissions.isEmpty ? 'none assigned' : dashboard.permissions.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SectionHeader('Announcements'),
        AsyncBody<List<Map<String, dynamic>>>(
          value: ref.watch(_partnerAnnouncementsProvider),
          onRetry: () => ref.invalidate(_partnerAnnouncementsProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(message: 'No partner announcements yet.', icon: Icons.campaign_outlined)
              : Column(children: [
                  for (final a in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${a['body']}'),
                        ]),
                      ),
                    ),
                ]),
        ),
        if (canManage) ...[
          const SectionHeader('Publish announcement'),
          _AnnouncementForm(),
        ],
      ],
    );
  }
}

final _partnerAnnouncementsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).partnerAnnouncements();
});

class _AnnouncementForm extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends ConsumerState<_AnnouncementForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
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
      () => ref.read(repositoryProvider).publishPartnerAnnouncement(title: _title.text, body: _body.text),
      success: 'Announcement published',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _title.clear();
      _body.clear();
      ref.invalidate(_partnerAnnouncementsProvider);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        child: Column(children: [
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Enter a title' : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _body,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Message'),
            validator: (v) => (v ?? '').trim().length < 5 ? 'Enter a message' : null,
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'Publish', icon: Icons.send, onPressed: _publish, busy: _busy),
        ]),
      );
}

class PartnerApplyScreen extends ConsumerStatefulWidget {
  const PartnerApplyScreen({super.key});

  @override
  ConsumerState<PartnerApplyScreen> createState() => _PartnerApplyScreenState();
}

class _PartnerApplyScreenState extends ConsumerState<PartnerApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _organization = TextEditingController();
  final _website = TextEditingController();
  final _category = TextEditingController();
  final _proposal = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_fullName, _username, _email, _organization, _website, _category, _proposal, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final id = await runValue(
      context,
      () => ref.read(repositoryProvider).submitPartnerApplication(
            fullName: _fullName.text,
            username: _username.text,
            email: _email.text,
            organization: _organization.text,
            website: _website.text,
            partnershipCategory: _category.text,
            proposal: _proposal.text,
            description: _description.text,
          ),
      success: 'Application submitted for review',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(myPartnerApplicationsProvider);
    if (id != null) Navigator.of(context).maybePop();
  }

  String? _required(String? v, int min, String msg) =>
      (v ?? '').trim().length < min ? msg : null;

  @override
  Widget build(BuildContext context) => BubblePage(
        title: 'Partner application',
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(controller: _fullName, decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => _required(v, 2, 'Enter your name')),
              const SizedBox(height: 12),
              TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                  validator: (v) => _required(v, 3, 'Enter a username')),
              const SizedBox(height: 12),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Contact email'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email'),
              const SizedBox(height: 12),
              TextFormField(controller: _organization, decoration: const InputDecoration(labelText: 'Organization'),
                  validator: (v) => _required(v, 2, 'Enter your organization')),
              const SizedBox(height: 12),
              TextFormField(controller: _website, decoration: const InputDecoration(labelText: 'Website (optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Partnership category'),
                  validator: (v) => _required(v, 2, 'Enter a category')),
              const SizedBox(height: 12),
              TextFormField(controller: _proposal, maxLines: 5, decoration: const InputDecoration(labelText: 'Proposal'),
                  validator: (v) => _required(v, 30, 'Describe the proposal in at least 30 characters')),
              const SizedBox(height: 12),
              TextFormField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'About you (optional)')),
              const SizedBox(height: 20),
              GradientButton(label: 'Submit application', icon: Icons.send, onPressed: _submit, busy: _busy),
            ],
          ),
        ),
      );
}

/// Staff review of partner applications. Approve needs a partner category; reject needs a reason.
class PartnerQueueScreen extends ConsumerStatefulWidget {
  const PartnerQueueScreen({super.key});

  @override
  ConsumerState<PartnerQueueScreen> createState() => _PartnerQueueScreenState();
}

class _PartnerQueueScreenState extends ConsumerState<PartnerQueueScreen> {
  late Future<List<PartnerApplication>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(repositoryProvider).partnerQueue();
  }

  void _reload() => setState(() => _future = ref.read(repositoryProvider).partnerQueue());

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final canApprove = access.can('partners.approve');
    final canManage = access.can('partners.manage');
    return BubblePage(
      title: 'Partner queue',
      actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      child: FutureBuilder<List<PartnerApplication>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final list = snap.data ?? const [];
          if (list.isEmpty) return const EmptyState(message: 'No partner applications.');
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final a = list[i];
              final actions = <Widget>[];
              void add(String label, VoidCallback fn, {bool filled = false}) => actions.add(filled
                  ? FilledButton(onPressed: fn, child: Text(label))
                  : OutlinedButton(onPressed: fn, child: Text(label)));

              if (canApprove && a.status == 'pending') {
                add('Start review', () => _act(context, a, 'start_review'));
              }
              if (canApprove && (a.status == 'pending' || a.status == 'reviewing')) {
                add('Approve', () => _approve(context, a), filled: true);
                add('Reject', () => _reject(context, a));
              }
              if (canManage && a.status == 'approved') {
                add('Suspend', () => _act(context, a, 'suspend', needsNote: true));
                add('Terminate', () => _act(context, a, 'terminate', needsNote: true));
              }
              if (canManage && a.status == 'suspended') {
                add('Restore', () => _act(context, a, 'restore'), filled: true);
                add('Terminate', () => _act(context, a, 'terminate', needsNote: true));
              }

              return GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(a.organization, style: const TextStyle(fontWeight: FontWeight.w700))),
                      StatusBadge(label: a.status),
                    ]),
                    Text('${a.fullName} · ${a.partnershipCategory}'),
                    const SizedBox(height: 8),
                    actions.isEmpty
                        ? Text('No actions available for your permissions.', style: Theme.of(context).textTheme.bodySmall)
                        : Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _act(BuildContext context, PartnerApplication a, String action, {bool needsNote = false}) async {
    String? note;
    if (needsNote) {
      note = await promptText(context, title: 'Reason', label: 'Reason (required)', mandatory: true);
      if (note == null || note.isEmpty || !context.mounted) return;
    }
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).reviewPartnerApplication(applicationId: a.id, action: action, note: note),
      success: 'Updated',
    );
    if (ok) _reload();
  }

  Future<void> _approve(BuildContext context, PartnerApplication a) async {
    final category = await promptText(context, title: 'Assign partner category', label: 'Category (required)', mandatory: true);
    if (category == null || category.isEmpty || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).reviewPartnerApplication(
            applicationId: a.id,
            action: 'approve',
            category: category,
          ),
      success: 'Partner approved',
    );
    if (ok) _reload();
  }

  Future<void> _reject(BuildContext context, PartnerApplication a) async {
    final note = await promptText(context, title: 'Reason for rejection', label: 'Reason (required)', mandatory: true);
    if (note == null || note.isEmpty || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).reviewPartnerApplication(applicationId: a.id, action: 'reject', note: note),
      success: 'Application rejected',
    );
    if (ok) _reload();
  }
}
