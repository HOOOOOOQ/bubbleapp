import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _statLabels = <String, String>{
  'total_users': 'Total users',
  'active_users_30d': 'Active (30 days)',
  'online_users': 'Online (5 min)',
  'personal_accounts': 'Personal accounts',
  'business_accounts': 'Business accounts',
  'verified_users': 'Verified users',
  'verified_businesses': 'Verified businesses',
  'verified_channels': 'Verified channels',
  'total_partners': 'Partners',
  'active_partners': 'Active partners',
  'total_administrators': 'Administrators',
  'total_channels': 'Channels',
  'total_subscribers': 'Subscriptions',
  'total_messages': 'Messages',
  'total_communities': 'Communities',
  'total_reports': 'Reports',
  'open_reports': 'Open reports',
  'pending_verifications': 'Pending verifications',
  'pending_partner_applications': 'Pending partner applications',
  'premium_active': 'Active premium',
};

final _ownerStatsProvider = FutureProvider.autoDispose<OwnerStats>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerStats();
});

final _ownerAuditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).ownerAuditLog();
});

final _adminAuditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).adminAuditLog();
});

/// Platform metrics for the Owner (and analytics readers). Owner accounts are provisioned only
/// through a trusted server-side process; this screen can neither create nor transfer ownership.
class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!(access.isOwner || access.can('analytics.read'))) {
      return const BubblePage(title: 'Owner dashboard', child: EmptyState(message: 'You do not have access to this page.', icon: Icons.lock_outline));
    }
    final stats = ref.watch(_ownerStatsProvider);
    return BubblePage(
      title: 'Owner dashboard',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(_ownerStatsProvider),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_ownerStatsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody<OwnerStats>(
              value: stats,
              onRetry: () => ref.invalidate(_ownerStatsProvider),
              builder: (s) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.9,
                children: [
                  for (final e in _statLabels.entries)
                    GlassCard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${s.get(e.key)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          Text(e.value, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (access.can('owner.manage')) ...[
              const SectionHeader('Owner audit log'),
              _AuditList(provider: _ownerAuditProvider),
            ],
            if (access.can('audit.read')) ...[
              const SectionHeader('Administrator audit log'),
              _AuditList(provider: _adminAuditProvider),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuditList extends ConsumerWidget {
  const _AuditList({required this.provider});

  final FutureProvider<List<Map<String, dynamic>>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(provider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: rows,
      onRetry: () => ref.invalidate(provider),
      builder: (list) => list.isEmpty
          ? const EmptyState(message: 'No entries yet.', icon: Icons.history)
          : Column(children: [
              for (final r in list.take(50))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['action']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${r['target_type'] ?? ''} ${r['target_id'] ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (r['created_at'] is String)
                        Text(DateFormat.yMMMd().add_Hm().format(DateTime.parse(r['created_at'] as String).toLocal()),
                            style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
