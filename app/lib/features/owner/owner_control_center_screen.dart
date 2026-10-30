import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../core/bubble_error.dart';

class OwnerControlCenterScreen extends ConsumerWidget {
  const OwnerControlCenterScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!access.isOwner) {
      return const BubblePage(title: 'Owner Control Center', child: EmptyState(message: 'Owner-only access. No hidden backdoor — bootstrap via trusted context only.', icon: Icons.shield_outlined));
    }
    return BubblePage(
      title: 'Owner Control Center',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: BubbleColors.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.shield, color: BubbleColors.danger)), const SizedBox(width: 10), const Text('Owner-only', style: TextStyle(fontWeight: FontWeight.w800))]),
              const SizedBox(height: 8),
              Text('Global platform configuration, admin/role/permission management, security center, audit logs, emergency controls, official channel, verification/partner policy, maintenance, critical service settings. All actions require confirmation + server-side validation + audit.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          const SectionHeader('Global configuration'),
          _OwnerTile(icon: Icons.settings_outlined, title: 'Platform settings', subtitle: 'All keys, protected require owner.manage', onTap: () => context.push('/owner/settings')),
          _OwnerTile(icon: Icons.campaign_outlined, title: 'Official channel control', subtitle: 'Publish to @BubbleApp, enforce mandatory follow', onTap: () => context.push('/channels/official')),
          _OwnerTile(icon: Icons.verified_outlined, title: 'Verification policy', subtitle: 'Requirements, reviewer config', onTap: () => context.push('/owner/verification_policy')),
          _OwnerTile(icon: Icons.handshake_outlined, title: 'Partner program control', subtitle: 'Requirements, benefits', onTap: () => context.push('/owner/partner_config')),
          const SectionHeader('Admin & roles'),
          _OwnerTile(icon: Icons.admin_panel_settings_outlined, title: 'Admin management', subtitle: 'Invite, role, granular perms', onTap: () => context.push('/owner/admins')),
          _OwnerTile(icon: Icons.security_outlined, title: 'Role management', subtitle: 'Owner → Super Admin → Admin → Moderator hierarchy', onTap: () => showMessage(context, 'Roles are seeded in platform_roles; Owner rank 100 is immutable.')),
          _OwnerTile(icon: Icons.key_outlined, title: 'Permission management', subtitle: 'Centralized definitions, inheritance only explicit', onTap: () => context.push('/owner/admins')),
          const SectionHeader('Security & audit'),
          _OwnerTile(icon: Icons.shield_outlined, title: 'Security center', subtitle: 'Logins, failed, suspicious, alerts', onTap: () => context.push('/owner/security')),
          _OwnerTile(icon: Icons.history_outlined, title: 'Audit logs', subtitle: 'Immutable, trigger-protected', onTap: () => context.push('/owner/audit')),
          _OwnerTile(icon: Icons.emergency_outlined, title: 'Emergency controls', subtitle: 'Suspend admins, revoke sessions, maintenance', onTap: () => _emergencyDialog(context, ref)),
          const SectionHeader('Critical service settings'),
          _OwnerTile(icon: Icons.build_outlined, title: 'Maintenance mode', subtitle: 'Enable/disable, announcement', onTap: () => _maintenanceDialog(context, ref)),
          _OwnerTile(icon: Icons.notifications_outlined, title: 'Platform announcements', subtitle: 'Create/publish/schedule', onTap: () => context.push('/admin/announcements')),
          const SizedBox(height: 12),
          Text('No undocumented way to become Owner. Owner role is guarded by guard_owner_role() trigger — only is_trusted_context() (direct DB session) can insert Owner. Client cannot grant Owner via has_permission.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _maintenanceDialog(BuildContext context, WidgetRef ref) async {
    bool enabled = false;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
          title: const Text('Maintenance mode'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(title: const Text('Enable maintenance'), value: enabled, onChanged: (v) => setS(() => enabled = v)),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Announcement (optional)'), maxLines: 2),
            const SizedBox(height: 8),
            const Text('Consequences: new registrations and non-essential features will be restricted. Requires explicit confirmation, server validates owner.manage, audit logged.', style: TextStyle(fontSize: 12, color: BubbleColors.danger)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm'))],
        )));
    if (ok != true) return;
    final success = await runAction(context, () => ref.read(repositoryProvider).ownerSetMaintenance(enabled: enabled, announcement: ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), success: 'Maintenance updated');
    if (success && context.mounted) showMessage(context, 'Maintenance ${enabled ? 'enabled' : 'disabled'}');
  }

  Future<void> _emergencyDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Emergency suspend'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Target user ID (admin)')),
            const SizedBox(height: 8),
            const Text('Explain consequences, confirm, validate Owner, audit. No bypass of Owner protections.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: BubbleColors.danger), child: const Text('Suspend'))],
        ));
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final success = await runAction(context, () => ref.read(repositoryProvider).adminEmergencySuspend(userId: ctrl.text.trim(), reason: 'Emergency by Owner'), success: 'Emergency suspend executed');
    if (success && context.mounted) showMessage(context, 'Admin suspended');
  }
}

class _OwnerTile extends StatelessWidget {
  const _OwnerTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          onTap: onTap,
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: BubbleColors.indigo.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: BubbleColors.indigo)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)])),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}

