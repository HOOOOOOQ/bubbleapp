import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _docTypes = {
  'identity': 'Government ID',
  'business_registration': 'Business registration',
  'authorization': 'Authorization letter',
  'website_proof': 'Website proof',
  'other': 'Other',
};

const _applicationTypes = {
  'user': 'Personal account',
  'organization': 'Organization',
  'business': 'Business',
  'channel': 'Channel',
};

final verificationDocsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, appId) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).verificationDocuments(appId);
});

String _statusLabel(String s) => s.replaceAll('_', ' ');

Color _statusColor(String s) {
  switch (s) {
    case 'approved':
      return Colors.green;
    case 'rejected':
    case 'revoked':
      return Colors.red;
    case 'suspended':
    case 'info_requested':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

String _mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  return 'image/jpeg';
}

Future<void> _openDocument(BuildContext context, WidgetRef ref, String path) async {
  final url = await runValue(context, () => ref.read(repositoryProvider).signedDocumentUrl(path));
  if (url == null || !context.mounted) return;
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, 'Could not open the document.');
}

/// Lists documents for an application. Access is decided by storage policy and signed links.
class _DocumentList extends ConsumerWidget {
  const _DocumentList({required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(verificationDocsProvider(applicationId));
    return AsyncBody<List<Map<String, dynamic>>>(
      value: docs,
      onRetry: () => ref.invalidate(verificationDocsProvider(applicationId)),
      builder: (list) {
        if (list.isEmpty) return const Text('No documents uploaded yet.');
        return Column(
          children: [
            for (final d in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(_docTypes[d['doc_type']] ?? '${d['doc_type']}'),
                subtitle: Text('${d['mime_type']} · ${((d['size_bytes'] as num?)?.toInt() ?? 0) ~/ 1024} KB'),
                trailing: TextButton(
                  onPressed: () => _openDocument(context, ref, d['storage_path'] as String),
                  child: const Text('Open'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Applicant home: choose what to verify, track applications, add documents.
class VerificationHomeScreen extends ConsumerWidget {
  const VerificationHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(myVerificationProvider);
    return BubblePage(
      title: 'Verification',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myVerificationProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const GlassCard(
              child: Text(
                'Verification is decided by BubbleApp reviewers after they check your documents. '
                'You cannot grant it to yourself. Documents are stored privately and are only '
                'visible to you and authorised reviewers.',
              ),
            ),
            const SectionHeader('Apply'),
            for (final entry in _applicationTypes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  onTap: () => context.push('/verification/apply/${entry.key}'),
                  child: Row(children: [
                    Expanded(child: Text('Verify: ${entry.value}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            const SectionHeader('Your applications'),
            AsyncBody<List<VerificationApplication>>(
              value: apps,
              onRetry: () => ref.invalidate(myVerificationProvider),
              builder: (list) {
                if (list.isEmpty) return const EmptyState(message: 'You have not applied for verification yet.', icon: Icons.verified_outlined);
                return Column(
                  children: [
                    for (final a in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          onTap: () => _showDetails(context, ref, a),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(_applicationTypes[a.applicationType] ?? a.applicationType,
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                                StatusBadge(label: _statusLabel(a.status), color: _statusColor(a.status)),
                              ]),
                              const SizedBox(height: 4),
                              Text(a.fullName),
                              if (a.decisionNote != null && a.decisionNote!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Reviewer note: ${a.decisionNote}', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, WidgetRef ref, VerificationApplication a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_applicationTypes[a.applicationType] ?? a.applicationType,
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                StatusBadge(label: _statusLabel(a.status), color: _statusColor(a.status)),
                const SizedBox(height: 12),
                Text('Name: ${a.fullName}'),
                Text('Category: ${a.category}'),
                Text('Reason: ${a.reason}'),
                if (a.submittedAt != null) Text('Submitted: ${DateFormat.yMMMd().format(a.submittedAt!)}'),
                const SectionHeader('Documents'),
                _DocumentList(applicationId: a.id),
                if (a.isOpen) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Add document (JPEG or PNG)'),
                    onPressed: () => _uploadDocument(ctx, ref, a),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadDocument(BuildContext context, WidgetRef ref, VerificationApplication a) async {
    final docType = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Document type'),
        children: [
          for (final e in _docTypes.entries)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
        ],
      ),
    );
    if (docType == null || !context.mounted) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).uploadVerificationDocument(
            applicationId: a.id,
            docType: docType,
            fileName: picked.name,
            mimeType: picked.mimeType ?? _mimeFor(picked.name),
            bytes: bytes,
          ),
      success: 'Document uploaded privately',
    );
    if (ok) ref.invalidate(verificationDocsProvider(a.id));
  }
}

/// Applicant form for one verification type.
class ApplyVerificationScreen extends ConsumerStatefulWidget {
  const ApplyVerificationScreen({super.key, required this.applicationType, this.preselectedId});

  final String applicationType;
  final String? preselectedId;

  @override
  ConsumerState<ApplyVerificationScreen> createState() => _ApplyVerificationScreenState();
}

class _ApplyVerificationScreenState extends ConsumerState<ApplyVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _reason = TextEditingController();
  String? _selectedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.preselectedId;
  }

  @override
  void dispose() {
    for (final c in [_fullName, _username, _category, _description, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    final id = await runValue(
      context,
      () => repo.submitVerification(
        applicationType: widget.applicationType,
        fullName: _fullName.text,
        username: _username.text,
        category: _category.text,
        description: _description.text,
        reason: _reason.text,
        businessId: widget.applicationType == 'business' ? _selectedId : null,
        channelId: widget.applicationType == 'channel' ? _selectedId : null,
      ),
      success: 'Application submitted. Add your documents from the verification page.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(myVerificationProvider);
    if (id != null) context.go('/verification');
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.applicationType;
    if (!_applicationTypes.containsKey(type)) {
      return const BubblePage(title: 'Verification', child: EmptyState(message: 'Unknown verification type.'));
    }
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final businesses = ref.watch(myBusinessesProvider);
    final channels = ref.watch(channelsProvider);

    Widget? target;
    if (type == 'business') {
      target = AsyncBody<List<BusinessSummary>>(
        value: businesses,
        onRetry: () => ref.invalidate(myBusinessesProvider),
        builder: (list) => list.isEmpty
            ? const Text('Create a business first, then apply to verify it.')
            : DropdownButtonFormField<String>(
                value: list.any((b) => b.id == _selectedId) ? _selectedId : null,
                decoration: const InputDecoration(labelText: 'Business'),
                items: [for (final b in list) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => setState(() => _selectedId = v),
                validator: (v) => v == null ? 'Choose a business' : null,
              ),
      );
    } else if (type == 'channel') {
      target = AsyncBody<List<ChannelModel>>(
        value: channels,
        onRetry: () => ref.invalidate(channelsProvider),
        builder: (list) {
          final mine = list.where((c) => c.ownerId == uid && !c.isOfficial).toList();
          return mine.isEmpty
              ? const Text('Create a channel first, then apply to verify it.')
              : DropdownButtonFormField<String>(
                  value: mine.any((c) => c.id == _selectedId) ? _selectedId : null,
                  decoration: const InputDecoration(labelText: 'Channel'),
                  items: [for (final c in mine) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _selectedId = v),
                  validator: (v) => v == null ? 'Choose a channel' : null,
                );
        },
      );
    }

    return BubblePage(
      title: 'Verify: ${_applicationTypes[type]}',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (target != null) ...[target, const SizedBox(height: 12)],
            TextFormField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: 'Full legal or organization name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter at least 2 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Public username', prefixText: '@'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the username to verify' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category (for example: Media, Brand, Creator)'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a category' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Why should this be verified?'),
              validator: (v) => (v ?? '').trim().length < 10 ? 'Explain in at least 10 characters' : null,
            ),
            const SizedBox(height: 20),
            GradientButton(label: 'Submit application', icon: Icons.send, onPressed: _submit, busy: _busy),
          ],
        ),
      ),
    );
  }
}

/// Staff queue. Every button is shown only when the status allows the action and the
/// signed-in account holds the permission; the database re-checks each call.
class VerificationQueueScreen extends ConsumerStatefulWidget {
  const VerificationQueueScreen({super.key});

  @override
  ConsumerState<VerificationQueueScreen> createState() => _VerificationQueueScreenState();
}

class _VerificationQueueScreenState extends ConsumerState<VerificationQueueScreen> {
  String? _type;
  late Future<List<VerificationApplication>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<VerificationApplication>> _load() =>
      ref.read(repositoryProvider).verificationQueue(type: _type);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    final canReviewUsers = access.can('users.verify');
    final canReviewChannels = access.can('channels.verify');

    return BubblePage(
      title: 'Verification queue',
      actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String?>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All types')),
                for (final e in _applicationTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                _type = v;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VerificationApplication>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
                final list = snap.data ?? const [];
                if (list.isEmpty) return const EmptyState(message: 'Nothing in the queue.');
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = list[i];
                    final canReview = a.applicationType == 'channel' ? canReviewChannels : canReviewUsers;
                    final isOwnApp = a.applicantId == uid;
                    return GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text('${_applicationTypes[a.applicationType] ?? a.applicationType} · ${a.fullName}',
                                style: const TextStyle(fontWeight: FontWeight.w700))),
                            StatusBadge(label: _statusLabel(a.status), color: _statusColor(a.status)),
                          ]),
                          Text('Category: ${a.category}'),
                          if (a.username != null) Text('@${a.username}'),
                          Text('Reason: ${a.reason}'),
                          if (a.recommendation != null) Text('Recommendation: ${a.recommendation}'),
                          const SizedBox(height: 8),
                          _DocumentList(applicationId: a.id),
                          const SizedBox(height: 8),
                          if (isOwnApp)
                            const Text('You cannot review your own application.', style: TextStyle(fontStyle: FontStyle.italic))
                          else
                            _ActionBar(
                              app: a,
                              canReview: canReview,
                              canDecide: access.can('verification.approve'),
                              onDone: _reload,
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.app, required this.canReview, required this.canDecide, required this.onDone});

  final VerificationApplication app;
  final bool canReview;
  final bool canDecide;
  final VoidCallback onDone;

  Future<void> _run(BuildContext context, WidgetRef ref, String action,
      {String? note, String? success}) async {
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).reviewVerification(applicationId: app.id, action: action, note: note),
      success: success ?? 'Done',
    );
    if (ok) onDone();
  }

  Future<void> _withNote(BuildContext context, WidgetRef ref, String action, String title,
      {required bool needsNote, String? success}) async {
    final note = await promptText(context, title: title, label: 'Note', mandatory: needsNote);
    if (note == null || !context.mounted) return;
    if (needsNote && note.isEmpty) return;
    await _run(context, ref, action, note: note.isEmpty ? null : note, success: success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = const {'pending', 'under_review', 'info_requested'}.contains(app.status);
    final buttons = <Widget>[];

    if (canReview && app.status == 'pending') {
      buttons.add(OutlinedButton(
          onPressed: () => _run(context, ref, 'start_review', success: 'Review started'),
          child: const Text('Start review')));
    }
    if (canReview && (app.status == 'pending' || app.status == 'under_review')) {
      buttons.add(OutlinedButton(
          onPressed: () => _withNote(context, ref, 'request_info', 'Request more information',
              needsNote: true, success: 'Information requested'),
          child: const Text('Request info')));
    }
    if (canReview && open) {
      buttons.add(OutlinedButton(
          onPressed: () => _run(context, ref, 'recommend_approve', success: 'Recommendation saved'),
          child: const Text('Recommend approve')));
      buttons.add(OutlinedButton(
          onPressed: () => _run(context, ref, 'recommend_reject', success: 'Recommendation saved'),
          child: const Text('Recommend reject')));
    }
    if (canReview && canDecide && open) {
      buttons.add(FilledButton(
          onPressed: () => _run(context, ref, 'approve', success: 'Verification approved'),
          child: const Text('Approve')));
      buttons.add(FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => _withNote(context, ref, 'reject', 'Reason for rejection', needsNote: true,
              success: 'Application rejected'),
          child: const Text('Reject')));
    }
    if (canReview && canDecide && app.status == 'approved') {
      buttons.add(OutlinedButton(
          onPressed: () => _withNote(context, ref, 'suspend', 'Reason for suspension', needsNote: true,
              success: 'Verification suspended'),
          child: const Text('Suspend')));
    }
    if (canReview && canDecide && (app.status == 'approved' || app.status == 'suspended')) {
      buttons.add(OutlinedButton(
          onPressed: () => _withNote(context, ref, 'revoke', 'Reason for revocation', needsNote: true,
              success: 'Verification revoked'),
          child: const Text('Revoke')));
    }
    if (canReview && canDecide && app.status == 'suspended') {
      buttons.add(FilledButton(
          onPressed: () => _run(context, ref, 'restore', success: 'Verification restored'),
          child: const Text('Restore')));
    }

    if (buttons.isEmpty) {
      return Text('No actions available for your permissions at this stage.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}
