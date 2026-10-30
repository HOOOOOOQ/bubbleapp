import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _tabs = ['/home', '/channels', '/business', '/settings'];

/// Bottom navigation shell for the four primary destinations.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final found = _tabs.indexWhere(location.startsWith);
    final index = found < 0 ? 0 : found;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Channels'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Business'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Tappable tile used in the home hub grid.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) => GlassCard(
        onTap: () => context.push(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  /// Keeps the mandatory subscriptions in place and records presence. Failures are shown once.
  Future<void> _sync() async {
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    final ok = await runAction(context, () async {
      await repo.ensureMandatorySubscriptions();
      await repo.touchPresence();
    });
    if (ok && mounted) ref.invalidate(mySubscriptionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final channels = ref.watch(channelsProvider);
    final subs = ref.watch(mySubscriptionsProvider);
    final official = channels.valueOrNull?.where((c) => c.isOfficial).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProfileProvider);
          ref.invalidate(channelsProvider);
          ref.invalidate(mySubscriptionsProvider);
          ref.invalidate(accessProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody<UserProfile?>(
              value: profile,
              onRetry: () => ref.invalidate(myProfileProvider),
              builder: (p) {
                if (p == null) return const SizedBox.shrink();
                return GlassCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        child: Text(p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(child: Text(p.displayName.isEmpty ? p.username : p.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                                  overflow: TextOverflow.ellipsis)),
                              if (p.isVerified) ...[const SizedBox(width: 4), const VerifiedMark()],
                            ]),
                            Text('@${p.username}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            profile.valueOrNull?.needsProfileSetup == true
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Choose your username', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text('You are using a temporary username. Pick one so people can find you.'),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: () => context.push('/settings/profile'), child: const Text('Set username')),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            const SectionHeader('Official channel'),
            if (official == null)
              channels.when(
                data: (_) => const GlassCard(child: Text('The official channel is not available yet.')),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(channelsProvider)),
              )
            else
              GlassCard(
                onTap: () => context.push('/official'),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('@${official.username}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            const VerifiedMark(),
                          ]),
                          const Text('Required for every account. Open to read and manage updates.'),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            const SectionHeader('Your account'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                const ActionTile(icon: Icons.verified_outlined, label: 'Verification', route: '/verification'),
                const ActionTile(icon: Icons.handshake_outlined, label: 'Partner program', route: '/partners'),
                const ActionTile(icon: Icons.storefront_outlined, label: 'Business', route: '/business'),
                const ActionTile(icon: Icons.add_circle_outline, label: 'New channel', route: '/channels/new'),
              ],
            ),
            if (_hasStaffPanels(access)) ...[
              const SectionHeader('Staff'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  if (access.isOwner || access.can('analytics.read'))
                    const ActionTile(icon: Icons.insights_outlined, label: 'Owner dashboard', route: '/owner'),
                  if (access.isOwner || access.isAdmin || access.can('users.read'))
                    const ActionTile(icon: Icons.admin_panel_settings_outlined, label: 'Admin console', route: '/admin'),
                  if (access.can('users.verify') || access.can('channels.verify') || access.can('verification.approve'))
                    const ActionTile(icon: Icons.fact_check_outlined, label: 'Verification queue', route: '/verification/queue'),
                  if (access.can('partners.approve') || access.can('partners.manage'))
                    const ActionTile(icon: Icons.groups_outlined, label: 'Partner queue', route: '/partners/queue'),
                ],
              ),
            ],
            const SectionHeader('Your channels'),
            AsyncBody<List<ChannelModel>>(
              value: subs,
              onRetry: () => ref.invalidate(mySubscriptionsProvider),
              builder: (list) => list.isEmpty
                  ? const EmptyState(message: 'You are not subscribed to any channels yet.', icon: Icons.campaign_outlined)
                  : Column(
                      children: [
                        for (final c in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              onTap: () => context.push(c.isOfficial ? '/official' : '/channels/${c.id}'),
                              child: Row(children: [
                                Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                if (c.isMandatory) const StatusBadge(label: 'Required'),
                              ]),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  bool _hasStaffPanels(AccessSnapshot a) =>
      a.isOwner ||
      a.isAdmin ||
      a.can('analytics.read') ||
      a.can('users.read') ||
      a.can('users.verify') ||
      a.can('channels.verify') ||
      a.can('verification.approve') ||
      a.can('partners.approve') ||
      a.can('partners.manage');
}
