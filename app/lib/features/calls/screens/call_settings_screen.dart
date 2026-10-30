import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/call_repository.dart';
import '../../../models/call_models.dart';
import '../../../widgets/common.dart';

class CallSettingsScreen extends ConsumerStatefulWidget {
  const CallSettingsScreen({super.key});
  @override
  ConsumerState<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends ConsumerState<CallSettingsScreen> {
  CallSettings? _settings;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await ref.read(callRepositoryProvider).myCallSettings();
    setState(() { _settings = s; _loading = false; });
  }

  Future<void> _save(CallSettings s) async {
    setState(() => _settings = s);
    await ref.read(callRepositoryProvider).updateCallSettings(s);
    if (mounted) showMessage(context, 'Call settings saved');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) return Scaffold(appBar: AppBar(title: const Text('Call settings')), body: const Center(child: CircularProgressIndicator()));
    final s = _settings!;
    return Scaffold(
      appBar: AppBar(title: const Text('Call settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionHeader('Audio'),
        SwitchListTile(title: const Text('Mute microphone by default'), value: s.micMuted, onChanged: (v) => _save(s.copyWith(micMuted: v))),
        SwitchListTile(title: const Text('Speakerphone by default'), value: s.speakerOn, onChanged: (v) => _save(s.copyWith(speakerOn: v))),
        SwitchListTile(title: const Text('Noise suppression'), subtitle: const Text('Reduce background noise'), value: s.noiseSuppression, onChanged: (v) => _save(s.copyWith(noiseSuppression: v))),
        SwitchListTile(title: const Text('Echo cancellation'), value: s.echoCancellation, onChanged: (v) => _save(s.copyWith(echoCancellation: v))),
        const SectionHeader('Video'),
        SwitchListTile(title: const Text('Front camera by default'), value: s.cameraFront, onChanged: (v) => _save(s.copyWith(cameraFront: v))),
        ListTile(title: const Text('Video quality'), subtitle: Text(s.videoQuality), trailing: DropdownButton<String>(value: s.videoQuality, items: const [DropdownMenuItem(value: 'auto', child: Text('Auto')), DropdownMenuItem(value: 'low', child: Text('Low (data saver)')), DropdownMenuItem(value: 'medium', child: Text('Medium')), DropdownMenuItem(value: 'high', child: Text('High'))], onChanged: (v) { if (v != null) _save(s.copyWith(videoQuality: v)); })),
        SwitchListTile(title: const Text('Data saver'), subtitle: const Text('Lower video quality on mobile data'), value: s.dataSaver, onChanged: (v) => _save(s.copyWith(dataSaver: v))),
        const SectionHeader('Notifications'),
        SwitchListTile(title: const Text('Incoming call notifications'), value: s.incomingNotifications, onChanged: (v) => _save(s.copyWith(incomingNotifications: v))),
        const SizedBox(height: 12),
        Text('Settings are stored in user_settings.call_settings and respected by the call manager. Actual noise suppression/echo cancellation depends on device WebRTC implementation.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
