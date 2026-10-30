import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AsyncBody<UserProfile?>(
            value: profile,
            onRetry: () => ref.invalidate(myProfileProvider),
            builder: (p) => GlassCard(
              onTap: () => context.push('/settings/profile'),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    Text('@${p?.username ?? ''}'),
                    if (p?.bio.isNotEmpty == true) Text(p!.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const Icon(Icons.edit_outlined),
              ]),
            ),
          ),
          const SectionHeader('Notifications'),
          AsyncBody<List<Map<String, dynamic>>>(
            value: notifications,
            onRetry: () => ref.invalidate(notificationsProvider),
            builder: (list) => list.isEmpty
                ? const EmptyState(message: 'No notifications.', icon: Icons.notifications_none)
                : Column(children: [
                    for (final n in list.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          onTap: n['read_at'] == null
                              ? () async {
                                  final ok = await runAction(context,
                                      () => ref.read(repositoryProvider).markNotificationRead(n['id'] as String));
                                  if (ok) ref.invalidate(notificationsProvider);
                                }
                              : null,
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${n['title']}', style: TextStyle(fontWeight: n['read_at'] == null ? FontWeight.w700 : FontWeight.w400)),
                                Text('${n['body'] ?? ''}'),
                              ]),
                            ),
                            if (n['read_at'] == null) const Icon(Icons.fiber_manual_record, size: 10),
                          ]),
                        ),
                      ),
                  ]),
          ),
          const SectionHeader('Calls'),
          ListTile(leading: const Icon(Icons.call_outlined), title: const Text('Call history'), subtitle: const Text('Missed, incoming, outgoing'), onTap: () => context.push('/calls/history')),
          ListTile(leading: const Icon(Icons.settings_phone_outlined), title: const Text('Call settings'), subtitle: const Text('Mic, camera, quality, notifications'), onTap: () => context.push('/calls/settings')),
          const SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Verification'),
            onTap: () => context.push('/verification'),
          ),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Partner program'),
            onTap: () => context.push('/partners'),
          ),
          if (access.isOwner || access.can('analytics.read'))
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Owner dashboard'),
              onTap: () => context.push('/owner'),
            ),
          if (access.isOwner || access.isAdmin || access.can('users.read'))
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Admin console'),
              onTap: () => context.push('/admin'),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              final ok = await confirmAction(context,
                  title: 'Sign out?', body: 'You will need your email code to sign back in.', confirmLabel: 'Sign out');
              if (!ok || !context.mounted) return;
              await runAction(context, () => ref.read(repositoryProvider).signOut());
            },
          ),
        ],
      ),
    );
  }
}

/// Edit public profile fields. The database only permits updating these columns.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).updateMyProfile(
            username: _username.text,
            displayName: _displayName.text,
            bio: _bio.text,
          ),
      success: 'Profile saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(myProfileProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    return BubblePage(
      title: 'Edit profile',
      child: AsyncBody<UserProfile?>(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        builder: (p) {
          if (p == null) return const EmptyState(message: 'Profile not found.');
          if (!_loaded) {
            _username.text = p.needsProfileSetup ? '' : p.username;
            _displayName.text = p.displayName;
            _bio.text = p.bio;
            _loaded = true;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                  validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim())
                      ? null
                      : '3–32 letters, numbers or underscores',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a display name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bio,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
                const SizedBox(height: 16),
                GradientButton(label: 'Save', icon: Icons.save_outlined, onPressed: _save, busy: _busy),
              ],
            ),
          );
        },
      ),
    );
  }
}
