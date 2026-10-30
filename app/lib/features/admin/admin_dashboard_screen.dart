import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../config/theme.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final perms = access.permissions;
    final isOwner = access.isOwner;
    if (!access.isAdmin && !isOwner && perms.isEmpty) {
      return const BubblePage(title: 'Admin dashboard', child: EmptyState(message: 'No admin access.', icon: Icons.lock_outline));
    }
    return BubblePage(
      title: 'Admin dashboard',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Welcome, ${access.roles.join(', ')}', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('Interface reflects permissions granted by Owner. Hiding menu is not sufficient — backend also rejects unauthorized requests.', style: Theme.of(context).textTheme.bodySmall)])),
          const SectionHeader('Your authorized tools'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              if (access.can('users.read')) _Tool(icon: Icons.people_outline, label: 'User management', desc: 'Search, suspend, warn', onTap: () => context.push('/admin'), color: BubbleColors.blue),
              if (access.can('verification.approve')) _Tool(icon: Icons.verified_outlined, label: 'Verification', desc: 'Review applications', onTap: () => context.push('/admin/verification'), color: BubbleColors.success),
              if (access.can('partners.manage') || access.can('partners.approve')) _Tool(icon: Icons.handshake_outlined, label: 'Partners', desc: 'Applications', onTap: () => context.push('/admin/partners'), color: BubbleColors.violet),
              if (access.can('content.moderate') || access.can('reports.manage')) _Tool(icon: Icons.flag_outlined, label: 'Moderation', desc: 'Reports, actions', onTap: () => context.push('/admin/moderation'), color: BubbleColors.warning),
              if (access.can('channels.manage')) _Tool(icon: Icons.campaign_outlined, label: 'Channels', desc: 'Manage all', onTap: () => context.push('/channels'), color: BubbleColors.indigo),
              if (access.can('community.manage')) _Tool(icon: Icons.groups_outlined, label: 'Communities', desc: 'Manage', onTap: () => context.push('/communities'), color: BubbleColors.sky),
              if (access.can('analytics.read')) _Tool(icon: Icons.insights_outlined, label: 'Analytics', desc: 'Dashboard', onTap: () => context.push('/owner'), color: BubbleColors.blue),
              if (access.can('platform.announce') || access.can('announcements.manage')) _Tool(icon: Icons.campaign_outlined, label: 'Announcements', desc: 'Publish', onTap: () => context.push('/admin/announcements'), color: BubbleColors.indigo),
              if (access.can('settings.manage')) _Tool(icon: Icons.settings_outlined, label: 'Platform settings', desc: 'Config', onTap: () => context.push('/owner/settings'), color: BubbleColors.darkSurface),
              if (access.can('security.read')) _Tool(icon: Icons.security_outlined, label: 'Security', desc: 'Logins, alerts', onTap: () => context.push('/owner/security'), color: BubbleColors.danger),
              if (access.can('audit.read')) _Tool(icon: Icons.history_outlined, label: 'Audit logs', desc: 'Immutable', onTap: () => context.push('/owner/audit'), color: BubbleColors.darkSecondaryText),
            ],
          ),
          if (!access.can('settings.manage')) GlassCard(child: Row(children: [const Icon(Icons.lock_outline, size: 18), const SizedBox(width: 8), Expanded(child: Text('Platform settings hidden — backend rejects without settings.manage', style: Theme.of(context).textTheme.bodySmall))])),
          const SizedBox(height: 12),
          Text('Role hierarchy: Owner (100) > Super Admin (90) > Admin (50) > Moderator (30) > Partner (5) > Verified (1) > User (0). You cannot modify equal/higher rank. Owner protections cannot be bypassed.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.desc, required this.onTap, required this.color});
  final IconData icon; final String label; final String desc; final VoidCallback onTap; final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(onTap: onTap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color), const SizedBox(height: 6), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)), Text(desc, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall)]));
}

