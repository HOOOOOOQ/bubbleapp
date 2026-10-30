import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../core/bubble_error.dart';

final _adminsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).adminListAdmins();
});

class AdminManagementScreen extends ConsumerStatefulWidget {
  const AdminManagementScreen({super.key});
  @override
  ConsumerState<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends ConsumerState<AdminManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!access.isOwner && !access.can('admins.manage')) {
      return const BubblePage(title: 'Admin management', child: EmptyState(message: 'Only Owner can manage administrators.', icon: Icons.lock_outline));
    }
    final admins = ref.watch(_adminsProvider);
    return BubblePage(
      title: 'Admin management',
      actions: [IconButton(icon: const Icon(Icons.person_add_outlined), tooltip: 'Invite admin', onPressed: () => _inviteDialog())],
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_adminsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Admin management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Invite, assign roles, edit granular permissions, suspend or remove. Owner always retains ultimate authority. Admins cannot promote above own rank and cannot modify Owner.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const SectionHeader('Active administrators'),
            AsyncBody<List<Map<String, dynamic>>>(
              value: admins,
              builder: (list) => list.isEmpty
                  ? const EmptyState(message: 'No administrators yet. Invite from existing users.', icon: Icons.admin_panel_settings_outlined)
                  : Column(children: [for (final a in list) _AdminCard(data: a, onRefresh: () => ref.invalidate(_adminsProvider))]),
            ),
            const SectionHeader('Permission categories'),
            const GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Granular categories: User mgmt, Verification, Partner, Content moderation, Channel, Community, Reports, Analytics, Notification, Platform settings, Security logs.', style: TextStyle(fontSize: 13)),
                SizedBox(height: 8),
                Text('Modes: read-only (view), limited (act within category), full (all in category). Owner always retains Owner-only controls.', style: TextStyle(fontSize: 12, color: BubbleColors.darkSecondaryText)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteDialog() async {
    final ctrl = TextEditingController();
    String role = 'admin';
    final perms = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
            title: const Text('Invite administrator'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'User ID (uuid) or email — existing account', hintText: 'paste uuid')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(value: role, items: const [DropdownMenuItem(value: 'super_admin', child: Text('Super Admin (90)')), DropdownMenuItem(value: 'admin', child: Text('Admin (50)')), DropdownMenuItem(value: 'moderator', child: Text('Moderator (30)'))], onChanged: (v) => setS(() => role = v!), decoration: const InputDecoration(labelText: 'Role')),
                const SizedBox(height: 12),
                const Text('Granular permissions (optional overrides):', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                for (final p in ['users.read','users.manage','verification.approve','partners.manage','content.moderate','channels.manage','community.manage','reports.manage','analytics.read','notifications.manage','settings.manage','security.read'])
                  CheckboxListTile(title: Text(p, style: const TextStyle(fontSize: 12)), value: perms.contains(p), onChanged: (v) => setS(() => v! ? perms.add(p) : perms.remove(p)), dense: true, controlAffinity: ListTileControlAffinity.leading),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Invite'))],
          )),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final success = await runAction(context, () => ref.read(repositoryProvider).adminCreateAdmin(userId: ctrl.text.trim(), roleKey: role, permissions: perms.toList()), success: 'Admin invited');
    if (success) ref.invalidate(_adminsProvider);
  }
}

class _AdminCard extends ConsumerStatefulWidget {
  const _AdminCard({required this.data, required this.onRefresh});
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;
  @override
  ConsumerState<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends ConsumerState<_AdminCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final status = d['status'] as String? ?? 'active';
    final perms = (d['permissions'] as List?)?.cast<String>() ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(child: Text((d['display_name'] as String? ?? '?')[0])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d['display_name'] ?? d['username'] ?? d['user_id'], style: const TextStyle(fontWeight: FontWeight.w700)), Text('@${d['username'] ?? ''} • ${d['email'] ?? ''}', style: Theme.of(context).textTheme.bodySmall)])),
            StatusBadge(label: d['role_key'] ?? 'admin', color: status == 'active' ? BubbleColors.success : BubbleColors.danger),
            IconButton(icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more), onPressed: () => setState(() => _expanded = !_expanded)),
          ]),
          if (_expanded) ...[
            const Divider(height: 16),
            Text('Permissions: ${perms.isEmpty ? 'role defaults' : perms.join(', ')}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => _editPerms(d), child: const Text('Edit permissions')),
              OutlinedButton(onPressed: () => _changeStatus(d, 'suspended'), child: const Text('Suspend')),
              OutlinedButton(onPressed: () => _changeStatus(d, 'active'), child: const Text('Reactivate')),
              OutlinedButton(onPressed: () => _viewActivity(d['user_id'] as String), child: const Text('Activity')),
              OutlinedButton(onPressed: () => _confirmRemove(d), style: OutlinedButton.styleFrom(foregroundColor: BubbleColors.danger), child: const Text('Remove')),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _editPerms(Map<String, dynamic> d) async {
    final userId = d['user_id'] as String;
    final allPerms = ['users.read','users.manage','users.warn','verification.approve','partners.manage','content.moderate','channels.manage','community.manage','reports.manage','analytics.read','notifications.manage','settings.manage','security.read','audit.read'];
    final current = Set<String>.from((d['permissions'] as List?)?.cast<String>() ?? []);
    final selected = Set<String>.from(current);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit granular permissions'),
          content: SingleChildScrollView(child: Column(children: [for (final p in allPerms) CheckboxListTile(title: Text(p, style: const TextStyle(fontSize: 12)), value: selected.contains(p), onChanged: (v) => setS(() => v! ? selected.add(p) : selected.remove(p)), dense: true)])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
        )));
    if (ok != true) return;
    // Diff: grant added, deny removed, inherit unchanged — we do grant/deny per diff
    for (final p in allPerms) {
      final was = current.contains(p);
      final now = selected.contains(p);
      if (was == now) continue;
      final mode = now ? 'grant' : 'inherit';
      final success = await runAction(context, () => ref.read(repositoryProvider).adminSetPermission(userId: userId, permission: p, mode: mode));
      if (!success) break;
    }
    widget.onRefresh();
  }

  Future<void> _changeStatus(Map<String, dynamic> d, String status) async {
    final reason = await promptText(context, title: status == 'suspended' ? 'Suspend admin' : 'Reactivate admin', label: 'Reason', mandatory: true);
    if (reason == null) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).adminSetAdminStatus(userId: d['user_id'] as String, status: status, reason: reason), success: 'Status updated');
    if (ok) widget.onRefresh();
  }

  Future<void> _viewActivity(String userId) async {
    final rows = await ref.read(repositoryProvider).adminGetAudit(userId);
    if (!mounted) return;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => DraggableScrollableSheet(expand: false, initialChildSize: 0.7, builder: (ctx, ctrl) => ListView(padding: const EdgeInsets.all(16), controller: ctrl, children: [const Text('Administrator activity', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), if (rows.isEmpty) const Text('No activity yet') else for (final r in rows.take(20)) ListTile(title: Text(r['action'] as String? ?? ''), subtitle: Text('${r['target_type']} ${r['target_id'] ?? ''}'), trailing: Text((r['created_at'] as String?)?.substring(0,10) ?? ''))] ))));
  }

  Future<void> _confirmRemove(Map<String, dynamic> d) async {
    final confirm = await _confirmAction(context, title: 'Remove administrator?', body: 'This revokes all staff roles and permissions. Audit logged. Cannot be undone without re-inviting.', confirmLabel: 'Remove');
    if (!confirm) return;
    final ok = await runAction(context, () => ref.read(repositoryProvider).adminSetAdminStatus(userId: d['user_id'] as String, status: 'revoked', reason: 'Removed by Owner'), success: 'Admin removed');
    if (ok) widget.onRefresh();
  }
}

class BubblePage extends StatelessWidget {
  const BubblePage({super.key, required this.title, required this.child, this.actions});
  final String title; final Widget child; final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title), actions: actions), body: child);
}

Future<bool> _confirmAction(BuildContext context, {required String title, required String body, required String confirmLabel}) async {
  final v = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel))]));
  return v == true;
}
