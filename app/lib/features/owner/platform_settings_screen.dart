import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../core/bubble_error.dart';

class PlatformSettingsScreen extends ConsumerStatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  ConsumerState<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends ConsumerState<PlatformSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessProvider).valueOrNull ?? AccessSnapshot.empty;
    if (!access.can('settings.manage') && !access.isOwner) {
      return const BubblePage(title: 'Platform settings', child: EmptyState(message: 'You do not have access to platform settings.', icon: Icons.lock_outline));
    }
    final settingsAsync = ref.watch(_settingsProvider);
    return BubblePage(
      title: 'Platform settings',
      child: AsyncBody<List<Map<String, dynamic>>>(
        value: settingsAsync,
        builder: (settings) {
          // Group by category prefix
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final s in settings) {
            final key = s['setting_key'] as String;
            final cat = key.split('_').first;
            final group = {
              'registration': 'Registration',
              'maintenance': 'Maintenance',
              'stories': 'Social Features',
              'channels': 'Social Features',
              'communities': 'Social Features',
              'discovery': 'Social Features',
              'public': 'Social Features',
              'verification': 'Verification',
              'partner': 'Partner Program',
              'premium': 'Partner Program',
              'max': 'Messaging',
              'allowed': 'Messaging',
              'supported': 'Messaging',
              'message': 'Messaging',
              'session': 'Security',
              'login': 'Security',
              'rate': 'Security',
              'account': 'Security',
              'platform': 'General',
              'mandatory': 'General',
              'business': 'General',
            }[cat] ?? 'Other';
            groups.putIfAbsent(group, () => []).add(s);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Platform settings', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Every change is validated and persisted securely via set_platform_setting(). Protected keys (maintenance_mode, registration_enabled etc.) require owner.manage. Backend enforces them.', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              for (final entry in groups.entries) ...[
                SectionHeader(entry.key),
                ...entry.value.map((s) => _SettingTile(setting: s, onChanged: () => ref.invalidate(_settingsProvider))),
              ],
            ],
          );
        },
      ),
    );
  }
}

final _settingsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).platformSettings();
});

class _SettingTile extends ConsumerStatefulWidget {
  const _SettingTile({required this.setting, required this.onChanged});
  final Map<String, dynamic> setting;
  final VoidCallback onChanged;
  @override
  ConsumerState<_SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends ConsumerState<_SettingTile> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final key = s['setting_key'] as String;
    final value = s['setting_value'];
    final isProtected = s['is_protected'] == true;
    final displayValue = value.toString();
    final isBool = value is bool || displayValue == 'true' || displayValue == 'false';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            if (isProtected) const StatusBadge(label: 'Owner only', color: BubbleColors.danger),
            if (isBool) Switch(value: displayValue == 'true' || value == true, onChanged: _busy ? null : (v) async { setState(() => _busy = true); final ok = await runAction(context, () => ref.read(repositoryProvider).setPlatformSetting(key, v)); setState(() => _busy = false); if (ok) widget.onChanged(); }),
          ]),
          const SizedBox(height: 4),
          Text(displayValue, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          if (s['description'] != null) Text(s['description'] as String, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(onPressed: _busy ? null : () => _editString(key, value), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
            const SizedBox(width: 8),
            if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _editString(String key, dynamic value) async {
    final ctrl = TextEditingController(text: value.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $key'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'JSON value (e.g. true, "text", 123)'), maxLines: 4),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok != true) return;
    String raw = ctrl.text.trim();
    dynamic parsed;
    try {
      if (raw == 'true' || raw == 'false') parsed = raw == 'true';
      else if (int.tryParse(raw) != null) parsed = int.parse(raw);
      else if (raw.startsWith('"') || raw.startsWith('{') || raw.startsWith('[')) parsed = raw; // will be sent as jsonb string; backend validates type
      else parsed = raw;
    } catch (_) { parsed = raw; }
    setState(() => _busy = true);
    final success = await runAction(context, () => ref.read(repositoryProvider).setPlatformSetting(key, parsed));
    setState(() => _busy = false);
    if (success) widget.onChanged();
  }
}

