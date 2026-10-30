import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class SecurityCenterScreen extends ConsumerWidget {
  const SecurityCenterScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!access.can('security.read') && !access.isOwner) {
      return const BubblePage(title: 'Security center', child: EmptyState(message: 'Security access required.', icon: Icons.lock_outline));
    }
    final overviewAsync = ref.watch(_securityOverviewProvider);
    final healthAsync = ref.watch(_healthProvider);
    return BubblePage(
      title: 'Security center',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Security Center', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Displays recent login activity, failed attempts, suspicious alerts, admin actions, permission changes, session revocations, security config, Edge Function health, DB connectivity — where safely observable. No passwords, tokens, or service-role keys are exposed.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          const SectionHeader('Security overview'),
          AsyncBody<Map<String, dynamic>>(
            value: overviewAsync,
            builder: (o) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _StatTile(label: 'Logins (24h)', value: '${o['recent_logins'] ?? 0}', icon: Icons.login_outlined),
                _StatTile(label: 'Failed (24h)', value: '${o['failed_logins_24h'] ?? 0}', icon: Icons.error_outline, color: (o['failed_logins_24h'] as int? ?? 0) > 5 ? BubbleColors.danger : null),
                _StatTile(label: 'Suspicious (24h)', value: '${o['suspicious_24h'] ?? 0}', icon: Icons.warning_amber_outlined, color: (o['suspicious_24h'] as int? ?? 0) > 0 ? BubbleColors.warning : null),
                _StatTile(label: 'Permission changes (7d)', value: '${o['permission_changes_7d'] ?? 0}', icon: Icons.admin_panel_settings_outlined),
                _StatTile(label: 'Session revocations (7d)', value: '${o['session_revocations_7d'] ?? 0}', icon: Icons.phonelink_erase_outlined),
                _StatTile(label: 'Open reports', value: '${o['open_reports'] ?? 0}', icon: Icons.flag_outlined),
              ],
            ),
          ),
          const SectionHeader('System configuration'),
          AsyncBody<Map<String, dynamic>>(
            value: healthAsync,
            builder: (h) => GlassCard(
              child: Column(children: [
                _HealthRow(label: 'Maintenance', value: h['maintenance_mode']?.toString() ?? 'false'),
                _HealthRow(label: 'Registration', value: h['registration_enabled']?.toString() ?? 'true'),
                _HealthRow(label: 'Stories', value: h['stories_enabled']?.toString() ?? 'true'),
                _HealthRow(label: 'DB connected', value: h['database_connected'] == true ? 'true' : 'false'),
                _HealthRow(label: 'Realtime', value: h['realtime_enabled'] == true ? 'enabled' : 'disabled'),
                _HealthRow(label: 'Edge healthy', value: h['edge_functions_healthy'] == true ? 'true' : 'false'),
              ]),
            ),
          ),
          const SectionHeader('Recent admin actions'),
          Consumer(builder: (context, ref, _) {
            final audit = ref.watch(_adminAuditProvider);
            return AsyncBody<List<Map<String, dynamic>>>(
              value: audit,
              builder: (list) => Column(children: [for (final r in list.take(10)) GlassCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['action'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)), Text('${r['target_type']} ${r['target_id'] ?? ''}', style: Theme.of(context).textTheme.bodySmall), Text(r['created_at'] != null ? DateFormat.yMMMd().add_Hm().format(DateTime.parse(r['created_at'] as String).toLocal()) : '', style: Theme.of(context).textTheme.labelSmall)]))]),
            );
          }),
          const SectionHeader('Emergency actions (Owner only)'),
          GlassCard(
            child: Column(children: [
              ListTile(leading: const Icon(Icons.block_outlined, color: BubbleColors.danger), title: const Text('Emergency suspend admin'), subtitle: const Text('Owner-only, rank protected, audited'), onTap: () => _emergencySuspend(context, ref)),
              ListTile(leading: const Icon(Icons.phonelink_erase_outlined), title: const Text('Revoke admin sessions'), subtitle: const Text('Records revocation, not service key'), onTap: () => _revokeSessions(context, ref)),
              ListTile(leading: const Icon(Icons.security_outlined), title: const Text('Security incident record'), subtitle: const Text('Manual incident via audit log'), onTap: () => showMessage(context, 'Incident logged via audit trail')),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _emergencySuspend(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Emergency suspend'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Target user ID')), const SizedBox(height: 8), const Text('Requires security.manage (Owner). Explain consequences, confirm, validate server-side, audit.', style: TextStyle(fontSize: 12))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Suspend'))]));
    if (reason == null || reason.isEmpty) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).adminEmergencySuspend(userId: reason.trim(), reason: 'Emergency by Owner'));
    if (ok) showMessage(context, 'Emergency suspend recorded');
  }

  Future<void> _revokeSessions(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Revoke sessions'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'User ID')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Revoke'))]));
    if (id == null || id.isEmpty) return;
    await runAction(context, () => ref.read(repositoryProvider).adminRevokeSessions(userId: id.trim(), reason: 'Security center revocation'));
  }
}

final _securityOverviewProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).securityOverview());
final _healthProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).ownerSystemHealth());
final _adminAuditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) => ref.watch(repositoryProvider).adminAuditLog(limit: 20));

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon, this.color});
  final String label; final String value; final IconData icon; final Color? color;
  @override
  Widget build(BuildContext context) => GlassCard(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color ?? Theme.of(context).colorScheme.primary), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)]));
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), Text(value, style: TextStyle(fontSize: 13, color: value == 'true' ? BubbleColors.success : (value == 'false' ? BubbleColors.danger : null)))]));
}

