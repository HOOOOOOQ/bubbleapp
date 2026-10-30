import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../core/bubble_error.dart';
import '../../config/theme.dart';

class ModerationCenterScreen extends ConsumerStatefulWidget {
  const ModerationCenterScreen({super.key});
  @override
  ConsumerState<ModerationCenterScreen> createState() => _ModerationCenterScreenState();
}

class _ModerationCenterScreenState extends ConsumerState<ModerationCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  @override
  void initState() { super.initState(); _tabs = TabController(length: 4, vsync: this); }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!access.can('reports.manage') && !access.can('content.moderate')) {
      return const BubblePage(title: 'Moderation center', child: EmptyState(message: 'Moderation access required.', icon: Icons.lock_outline));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation center'), bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: 'Open'), Tab(text: 'Reviewing'), Tab(text: 'Escalated'), Tab(text: 'Metrics')])),
      body: TabBarView(controller: _tabs, children: [
        _ReportsList(status: 'open'),
        _ReportsList(status: 'reviewing'),
        _ReportsList(status: 'escalated'),
        _ModeratorMetricsTab(),
      ]),
    );
  }
}

class _ReportsList extends ConsumerStatefulWidget {
  const _ReportsList({required this.status});
  final String status;
  @override
  ConsumerState<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends ConsumerState<_ReportsList> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, dynamic>>> _load() => ref.read(repositoryProvider).reports(status: widget.status);
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorView(error: snap.error!);
        final list = snap.data ?? [];
        if (list.isEmpty) return EmptyState(message: 'No ${widget.status} reports.', icon: Icons.flag_outlined);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = list[i];
            return GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text('${r['target_type']} • ${r['reason'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))), StatusBadge(label: r['priority'] ?? 'normal', color: r['priority'] == 'urgent' ? BubbleColors.danger : (r['priority'] == 'high' ? BubbleColors.warning : null))]),
                if (r['details'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['details']}', style: Theme.of(context).textTheme.bodySmall)),
                Text('Status: ${r['status']} • Assigned: ${r['assigned_to'] ?? 'unassigned'}', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(onPressed: () => _assign(r['id'] as String), child: const Text('Assign')),
                  OutlinedButton(onPressed: () => _addNote(r['id'] as String), child: const Text('Add note')),
                  OutlinedButton(onPressed: () => _setPriority(r['id'] as String), child: const Text('Priority')),
                  OutlinedButton(onPressed: () => _resolve(r['id'] as String, 'warn'), child: const Text('Warn')),
                  OutlinedButton(onPressed: () => _resolve(r['id'] as String, 'hide_content'), child: const Text('Hide')),
                  OutlinedButton(onPressed: () => _resolve(r['id'] as String, 'suspend'), child: const Text('Suspend')),
                  OutlinedButton(onPressed: () => _escalate(r['id'] as String), child: const Text('Escalate')),
                  OutlinedButton(onPressed: () => _resolve(r['id'] as String, 'dismiss'), child: const Text('Dismiss')),
                ]),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _assign(String id) async {
    final uid = await promptText(context, title: 'Assign to', label: 'Assignee user ID');
    if (uid == null || uid.isEmpty) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).moderationAssign(reportId: id, assigneeId: uid), success: 'Assigned');
    if (ok) _reload();
  }

  Future<void> _addNote(String id) async {
    final note = await promptText(context, title: 'Internal note', label: 'Note', mandatory: true);
    if (note == null || note.isEmpty) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).moderationAddNote(reportId: id, note: note), success: 'Note added');
    if (ok) _reload();
  }

  Future<void> _setPriority(String id) async {
    final p = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(title: const Text('Set priority'), children: [for (final v in ['low','normal','high','urgent']) SimpleDialogOption(child: Text(v), onPressed: () => Navigator.pop(ctx, v))]));
    if (p == null) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).moderationSetPriority(reportId: id, priority: p), success: 'Priority set');
    if (ok) _reload();
  }

  Future<void> _resolve(String id, String action) async {
    String? note;
    if (action != 'dismiss') note = await promptText(context, title: 'Reason', label: 'Explain decision', mandatory: true);
    if (action != 'dismiss' && (note == null || note.isEmpty)) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).resolveReport(reportId: id, action: action, note: note), success: 'Report updated');
    if (ok) _reload();
  }

  Future<void> _escalate(String id) async {
    final note = await promptText(context, title: 'Escalate to Owner', label: 'Reason');
    final ok = await runAction(context, () => ref.read(repositoryProvider).moderationEscalate(reportId: id, note: note), success: 'Escalated');
    if (ok) _reload();
  }
}

class _ModeratorMetricsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(_metricsProvider);
    return AsyncBody<Map<String, dynamic>>(
      value: metrics,
      builder: (m) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(child: Column(children: [Text('Your performance', style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_Metric(label: 'Assigned', value: '${m['assigned'] ?? 0}'), _Metric(label: 'Resolved', value: '${m['resolved'] ?? 0}'), _Metric(label: 'Open', value: '${m['open'] ?? 0}')])])),
          const SizedBox(height: 12),
          Text('Metrics are based on actual reports and moderation_actions records — no fake numbers.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

final _metricsProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).moderatorMetrics());

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) => Column(children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(label, style: Theme.of(context).textTheme.bodySmall)]);
}



