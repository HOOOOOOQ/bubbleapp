import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

final _ownerStatsProvider = FutureProvider.autoDispose<OwnerStats>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerStats();
});

final _ownerTimeseriesProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerTimeseries(days: days);
});

final _ownerHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerSystemHealth();
});

final _ownerAuditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerAuditLog();
});

final _adminAuditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).adminAuditLog();
});

/// Premium Owner Dashboard — real Supabase metrics, charts, filters, alerts.
class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});
  @override
  ConsumerState<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  int _days = 30;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.invalidate(_ownerStatsProvider);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!(access.isOwner || access.can('analytics.read'))) {
      return const BubblePage(title: 'Owner dashboard', child: EmptyState(message: 'You do not have access to this page.', icon: Icons.lock_outline));
    }
    final stats = ref.watch(_ownerStatsProvider);
    final timeseries = ref.watch(_ownerTimeseriesProvider(_days));
    final health = ref.watch(_ownerHealthProvider);
    final isOwner = access.isOwner;

    return BubblePage(
      title: 'Owner dashboard',
      actions: [
        IconButton(tooltip: 'Owner Controls', icon: const Icon(Icons.shield_outlined), onPressed: () => context.push('/owner/control')),
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () {
          ref.invalidate(_ownerStatsProvider);
          ref.invalidate(_ownerTimeseriesProvider(_days));
          ref.invalidate(_ownerHealthProvider);
        }),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_ownerStatsProvider);
          ref.invalidate(_ownerTimeseriesProvider(_days));
          ref.invalidate(_ownerHealthProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Health banner
            AsyncBody<Map<String, dynamic>>(
              value: health,
              builder: (h) {
                final maint = h['maintenance_mode']?.toString() == 'true' || h['maintenance_mode'] == true;
                if (!maint) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: BubbleColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: BubbleColors.warning)),
                  child: Row(children: [const Icon(Icons.warning_amber, color: BubbleColors.warning), const SizedBox(width: 8), const Expanded(child: Text('Maintenance mode is enabled — new registrations may be restricted.', style: TextStyle(fontWeight: FontWeight.w600))), TextButton(onPressed: () => context.push('/owner/settings'), child: const Text('Settings'))]),
                );
              },
            ),
            // Service health card
            AsyncBody<Map<String, dynamic>>(
              value: health,
              builder: (h) => GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Platform health', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _HealthChip(label: 'DB', ok: h['database_connected'] == true),
                    _HealthChip(label: 'Realtime', ok: h['realtime_enabled'] == true),
                    _HealthChip(label: 'Edge', ok: h['edge_functions_healthy'] == true),
                    _HealthChip(label: 'Registration', ok: h['registration_enabled']?.toString() != 'false'),
                    _HealthChip(label: 'Stories', ok: h['stories_enabled']?.toString() != 'false'),
                    _HealthChip(label: 'Discovery', ok: h['discovery_enabled']?.toString() != 'false'),
                  ]),
                  const SizedBox(height: 6),
                  Text('Live values update every 60s. Aggregated values are counts from PostgreSQL. No estimates are fabricated.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
            const SectionHeader('Platform metrics'),
            AsyncBody<OwnerStats>(
              value: stats,
              onRetry: () => ref.invalidate(_ownerStatsProvider),
              builder: (s) => Column(children: [
                _MetricsGrid(stats: s),
                const SizedBox(height: 12),
                // Quick alerts
                _AlertsCard(stats: s),
              ]),
            ),
            const SectionHeader('Date range', trailing: null),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 30, label: Text('30d')), ButtonSegment(value: 90, label: Text('90d'))],
              selected: {_days},
              onSelectionChanged: (v) => setState(() => _days = v.first),
            ),
            const SizedBox(height: 12),
            AsyncBody<Map<String, dynamic>>(
              value: timeseries,
              builder: (ts) {
                final users = (ts['user_registrations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                final msgs = (ts['messages_per_day'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                final reports = (ts['reports_per_day'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                return Column(children: [
                  GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('User growth', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), _BarChart(data: users, color: BubbleColors.blue), const SizedBox(height: 4), Text('New registrations — daily counts from profiles.created_at', style: Theme.of(context).textTheme.labelSmall)])),
                  const SizedBox(height: 12),
                  GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Engagement — messages per day', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), _BarChart(data: msgs, color: BubbleColors.violet), Text('Live messages count, not estimates', style: Theme.of(context).textTheme.labelSmall)])),
                  const SizedBox(height: 12),
                  GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Reports per day', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), _BarChart(data: reports, color: BubbleColors.warning)])),
                ]);
              },
            ),
            const SectionHeader('Quick management'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                _QuickAction(icon: Icons.people_outline, label: 'User management', subtitle: 'Search, suspend, warn', onTap: () => context.push('/admin'), color: BubbleColors.blue),
                _QuickAction(icon: Icons.verified_outlined, label: 'Verification', subtitle: 'Pending: live count', onTap: () => context.push('/admin/verification'), color: BubbleColors.success),
                _QuickAction(icon: Icons.handshake_outlined, label: 'Partners', subtitle: 'Applications', onTap: () => context.push('/admin/partners'), color: BubbleColors.violet),
                _QuickAction(icon: Icons.flag_outlined, label: 'Moderation', subtitle: 'Open reports', onTap: () => context.push('/admin/moderation'), color: BubbleColors.warning),
                _QuickAction(icon: Icons.campaign_outlined, label: 'Announcements', subtitle: 'Official channel', onTap: () => context.push('/admin/announcements'), color: BubbleColors.indigo),
                _QuickAction(icon: Icons.settings_outlined, label: 'Platform settings', subtitle: 'Registration, security', onTap: () => context.push('/owner/settings'), color: BubbleColors.sky),
                _QuickAction(icon: Icons.security_outlined, label: 'Security center', subtitle: 'Logins, alerts', onTap: () => context.push('/owner/security'), color: BubbleColors.danger),
                _QuickAction(icon: Icons.history_outlined, label: 'Audit logs', subtitle: 'Immutable trail', onTap: () => context.push('/owner/audit'), color: BubbleColors.darkSurface),
              ],
            ),
            if (isOwner) ...[
              const SectionHeader('Owner controls'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.8,
                children: [
                  _QuickAction(icon: Icons.admin_panel_settings_outlined, label: 'Admin management', subtitle: 'Invite, permissions', onTap: () => context.push('/owner/admins'), color: BubbleColors.indigo),
                  _QuickAction(icon: Icons.shield_outlined, label: 'Control Center', subtitle: 'Emergency, maintenance', onTap: () => context.push('/owner/control'), color: BubbleColors.danger),
                ],
              ),
            ],
            const SectionHeader('Recent administrative activity'),
            _AuditList(provider: _adminAuditProvider, title: 'Admin audit'),
            if (access.can('owner.manage')) ...[
              const SizedBox(height: 12),
              _AuditList(provider: _ownerAuditProvider, title: 'Owner audit'),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.stats});
  final OwnerStats stats;
  @override
  Widget build(BuildContext context) {
    const labels = {
      'total_users': 'Total registered',
      'new_registrations_7d': 'New (7d)',
      'new_registrations_30d': 'New (30d)',
      'online_users': 'Online (5m) *live',
      'active_users_30d': 'Active (30d)',
      'total_conversations': 'Conversations',
      'total_groups': 'Groups',
      'total_messages': 'Messages sent',
      'total_channels': 'Channels',
      'total_communities': 'Communities',
      'total_stories': 'Stories (live)',
      'total_posts': 'Posts',
      'total_channel_posts': 'Channel posts',
      'total_calls': 'Calls',
      'pending_verifications': 'Pending verifications',
      'pending_partner_applications': 'Pending partners',
      'open_reports': 'Open reports',
      'total_administrators': 'Active admins',
      'premium_active': 'Premium active',
      'total_subscribers': 'Subscriptions',
    };
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        for (final e in labels.entries)
          GlassCard(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${stats.get(e.key)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(e.value, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.stats});
  final OwnerStats stats;
  @override
  Widget build(BuildContext context) {
    final alerts = <String>[];
    if (stats.get('pending_verifications') > 0) alerts.add('${stats.get('pending_verifications')} pending verifications');
    if (stats.get('pending_partner_applications') > 0) alerts.add('${stats.get('pending_partner_applications')} pending partner apps');
    if (stats.get('open_reports') > 0) alerts.add('${stats.get('open_reports')} open reports');
    if (stats.get('maintenance_mode').toString() == 'true') alerts.add('Maintenance mode active');
    if (alerts.isEmpty) {
      return GlassCard(child: Row(children: [const Icon(Icons.check_circle, color: BubbleColors.success), const SizedBox(width: 8), const Text('No urgent alerts'), const Spacer(), Text('All systems nominal', style: Theme.of(context).textTheme.bodySmall)]));
    }
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('System alerts', style: TextStyle(fontWeight: FontWeight.w700, color: BubbleColors.warning)),
        const SizedBox(height: 6),
        for (final a in alerts) Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [const Icon(Icons.warning_amber, size: 16, color: BubbleColors.warning), const SizedBox(width: 6), Expanded(child: Text(a))])),
      ]),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.label, required this.ok});
  final String label; final bool ok;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: (ok ? BubbleColors.success : BubbleColors.danger).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: ok ? BubbleColors.success : BubbleColors.danger)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(ok ? Icons.check_circle : Icons.error_outline, size: 14, color: ok ? BubbleColors.success : BubbleColors.danger), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ok ? BubbleColors.success : BubbleColors.danger))]),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.subtitle, required this.onTap, required this.color});
  final IconData icon; final String label; final String subtitle; final VoidCallback onTap; final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: onTap,
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), Text(subtitle, style: Theme.of(context).textTheme.labelSmall)])),
          const Icon(Icons.chevron_right, size: 18),
        ]),
      );
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.data, required this.color});
  final List<Map<String, dynamic>> data; final Color color;
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 60, child: Center(child: Text('No data for this period', style: TextStyle(fontSize: 12))));
    final maxVal = data.map((e) => (e['count'] as int)).fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 80,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in data.take(30))
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(children: [
                Expanded(child: Align(alignment: Alignment.bottomCenter, child: Container(height: (e['count'] as int) / maxVal * 60, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))))),
                const SizedBox(height: 4),
                Text((e['date'] as String).substring(5), style: const TextStyle(fontSize: 7)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _AuditList extends ConsumerWidget {
  const _AuditList({required this.provider, required this.title});
  final FutureProvider<List<Map<String, dynamic>>> provider; final String title;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(provider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: rows,
      onRetry: () => ref.invalidate(provider),
      builder: (list) => list.isEmpty
          ? const EmptyState(message: 'No entries yet.', icon: Icons.history)
          : Column(children: [
              for (final r in list.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Expanded(child: Text('${r['action']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))), StatusBadge(label: r['target_type'] ?? '')]),
                      if (r['target_id'] != null) Text('Target: ${r['target_id']}', style: Theme.of(context).textTheme.bodySmall),
                      Text(DateFormat.yMMMd().add_Hm().format(DateTime.parse(r['created_at'] as String).toLocal()), style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                ),
              if (list.length > 8) TextButton(onPressed: () => ref.invalidate(provider), child: const Text('View more in Audit Log')),
            ]),
    );
  }
}

