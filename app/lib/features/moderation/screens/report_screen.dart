import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../widgets/common.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, this.targetType, this.targetId});
  final String? targetType; final String? targetId;
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String _category = 'spam';
  final _reason = TextEditingController();
  final _details = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) { showMessage(context, 'Enter reason'); return; }
    setState(() => _busy = true);
    try {
      await ref.read(socialRepositoryProvider).report(targetType: widget.targetType ?? 'user', targetId: widget.targetId ?? 'unknown', reason: _reason.text.trim(), details: _details.text.trim().isEmpty ? null : _details.text.trim(), category: _category);
      if (mounted) { showMessage(context, 'Report submitted — moderators will review'); Navigator.pop(context); }
    } catch (e) { if (mounted) showMessage(context, friendlyError(e)); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reporting ${widget.targetType ?? 'content'}: ${widget.targetId ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Reports are audited (moderation_actions). Moderators can review, add notes, remove content, warn/suspend per permissions. Owners cannot be modified by moderators.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          const SectionHeader('Category'),
          Wrap(spacing: 8, children: ['spam','harassment','impersonation','inappropriate','fraud','copyright','other'].map((c) => ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c))).toList()),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason *', hintText: 'Brief reason (3-80 chars)'), maxLength: 80),
          TextField(controller: _details, decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Additional context'), maxLines: 3, maxLength: 2000),
          const SizedBox(height: 16),
          GradientButton(label: 'Submit report', icon: Icons.flag_outlined, onPressed: _submit, busy: _busy),
          const SizedBox(height: 8),
          Text('Blocked users are hidden from feed/search. False reports may be dismissed.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}
