import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../widgets/common.dart';
import '../state/call_manager.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key, required this.callId});
  final String callId;
  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> with SingleTickerProviderStateMixin {
  final _localRenderer = webrtc.RTCVideoRenderer();
  final _remoteRenderer = webrtc.RTCVideoRenderer();
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
    // Wakelock is handled by wakelock_plus if configured
  }

  Future<void> _attach() async {
    final s = ref.read(callManagerProvider);
    if (s.localStream != null) _localRenderer.srcObject = s.localStream;
    // Watch for remote streams
    ref.listen(callManagerProvider, (prev, next) {
      if (next.localStream != prev?.localStream) _localRenderer.srcObject = next.localStream;
      if (next.remoteStreams.isNotEmpty) {
        final first = next.remoteStreams.values.first;
        _remoteRenderer.srcObject = first;
      }
      if (next.uiState == CallUiState.ended && mounted) {
        Future.delayed(const Duration(milliseconds: 600), () { if (mounted) context.pop(); });
      }
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callManagerProvider);
    final s = state.session;
    final mgr = ref.read(callManagerProvider.notifier);
    final isVideo = state.isVideo;
    final other = s?.calleeProfile ?? s?.callerProfile;
    final name = other?.displayName.isNotEmpty == true ? other!.displayName : (other?.username ?? (s?.isGroup == true ? 'Group' : 'Call'));

    if (isVideo) return _videoLayout(state, mgr, name, other);
    return _voiceLayout(state, mgr, name, other);
  }

  Widget _voiceLayout(CallState state, CallManager mgr, String name, dynamic other) {
    final s = state.session;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F172A), Color(0xFF312E81)])),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              if (state.networkQuality == 'poor') Container(margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.signal_wifi_bad, size: 16, color: Colors.amber), SizedBox(width: 6), Text(state.uiState == CallUiState.reconnecting ? 'Reconnecting…' : 'Poor connection', style: TextStyle(color: Colors.amber))]) ),
              const Spacer(),
              AnimatedBuilder(animation: _pulse, builder: (c, child) => Container(padding: EdgeInsets.all(6 + 8 * _pulse.value), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: BubbleColors.blue.withOpacity(0.3), width: 2)), child: child), child: CircleAvatar(radius: 56, backgroundColor: Colors.white.withOpacity(0.1), backgroundImage: other?.avatarUrl != null ? NetworkImage(other!.avatarUrl!) : null, child: other?.avatarUrl == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.w800)) : null)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)), if (other?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 8), child: VerifiedMark(size: 18))]),
              Text(_fmt(state.durationSeconds), style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
              if (state.isMicMuted) Padding(padding: const EdgeInsets.only(top: 8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mic_off, size: 14, color: Colors.white), SizedBox(width: 4), Text('Muted', style: TextStyle(color: Colors.white))]) )),
              const Spacer(),
              // Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _Control(icon: state.isMicMuted ? Icons.mic_off : Icons.mic, active: state.isMicMuted, onTap: mgr.toggleMic),
                  _Control(icon: Icons.volume_up, active: state.isSpeakerOn, onTap: mgr.toggleSpeaker),
                  _Control(icon: Icons.pause, label: 'Hold', onTap: () => mgr.setHold(true)),
                  if (state.isGroup) _Control(icon: Icons.person_add, onTap: () {}),
                ]),
              ),
              GestureDetector(onTap: () async { await mgr.end(); if (mounted) context.pop(); }, child: Container(width: 72, height: 72, decoration: BoxDecoration(color: BubbleColors.danger, shape: BoxShape.circle), child: const Icon(Icons.call_end, color: Colors.white, size: 30))),
              const SizedBox(height: 16),
              Text('End', style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoLayout(CallState state, CallManager mgr, String name, dynamic other) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Remote full screen
        Positioned.fill(child: webrtc.RTCVideoView(_remoteRenderer, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: false)),
        // Placeholder when no remote yet
        if (state.remoteStreams.isEmpty) Positioned.fill(child: Container(color: const Color(0xFF0F172A), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 48, backgroundImage: other?.avatarUrl != null ? NetworkImage(other!.avatarUrl!) : null, child: other?.avatarUrl == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 36, color: Colors.white)) : null), const SizedBox(height: 12), Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)), Text(state.uiState == CallUiState.connecting ? 'Connecting…' : _fmt(state.durationSeconds), style: TextStyle(color: Colors.white.withOpacity(0.7)))])))),
        // Local PIP
        Positioned(top: 48, right: 16, child: Container(width: 110, height: 150, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.2))), clipBehavior: Clip.hardEdge, child: state.isCameraOff ? Container(color: Colors.black87, child: Center(child: Icon(Icons.videocam_off, color: Colors.white.withOpacity(0.7)))) : webrtc.RTCVideoView(_localRenderer, mirror: state.isFrontCamera, objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
        // Top bar
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.6), Colors.transparent])), child: Row(children: [Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(12)), child: Text(_fmt(state.durationSeconds), style: const TextStyle(color: Colors.white, fontSize: 12)))])))),
        // Network
        if (state.networkQuality == 'poor') Positioned(top: 80, left: 16, right: 16, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.9), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.signal_wifi_bad, size: 16), SizedBox(width: 6), Text(state.uiState == CallUiState.reconnecting ? 'Reconnecting…' : 'Poor connection')]) )),
        // Bottom controls
        Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _VideoControl(icon: state.isMicMuted ? Icons.mic_off : Icons.mic, active: state.isMicMuted, onTap: mgr.toggleMic),
          _VideoControl(icon: state.isCameraOff ? Icons.videocam_off : Icons.videocam, active: state.isCameraOff, onTap: mgr.toggleCamera),
          _VideoControl(icon: Icons.cameraswitch, onTap: mgr.switchCamera),
          _VideoControl(icon: Icons.volume_up, active: state.isSpeakerOn, onTap: mgr.toggleSpeaker),
          GestureDetector(onTap: () async { await mgr.end(); if (mounted) context.pop(); }, child: Container(width: 64, height: 64, decoration: BoxDecoration(color: BubbleColors.danger, shape: BoxShape.circle), child: const Icon(Icons.call_end, color: Colors.white, size: 28))),
        ]))),
        // Group grid overlay when group
        if (state.isGroup && state.participants.length > 1) Positioned(top: 100, left: 8, right: 8, child: _GroupGrid(participants: state.participants)),
      ]),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, this.active = false, this.label, required this.onTap});
  final IconData icon;
  final bool active;
  final String? label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(onTap: onTap, child: Container(width: 56, height: 56, decoration: BoxDecoration(color: active ? Colors.white : Colors.white.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: active ? Colors.black : Colors.white))),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(label!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11))),
      ]);
}

class _VideoControl extends StatelessWidget {
  const _VideoControl({required this.icon, this.active = false, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 48, height: 48, decoration: BoxDecoration(color: active ? Colors.white : Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22)));
}

class _GroupGrid extends StatelessWidget {
  const _GroupGrid({required this.participants});
  final List<dynamic> participants;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in participants.take(6))
            Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(p.isMuted == true ? Icons.mic_off : Icons.mic, size: 16, color: Colors.white), Text((p.profile?.displayName ?? p.userId).toString().substring(0, 2), style: const TextStyle(color: Colors.white, fontSize: 10))])),
        ]),
      );
}
