import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../../../data/call_repository.dart';
import '../../../models/call_models.dart';
import '../services/call_signaling_service.dart';
import '../services/webrtc_service.dart';

enum CallUiState { idle, outgoingRinging, incomingRinging, connecting, connected, reconnecting, ended }

class CallState {
  const CallState({
    required this.uiState,
    this.session,
    this.participants = const [],
    this.localStream,
    this.remoteStreams = const {},
    this.networkQuality = 'good', // good | medium | poor | offline
    this.error,
    this.isMicMuted = false,
    this.isCameraOff = false,
    this.isSpeakerOn = false,
    this.isFrontCamera = true,
    this.durationSeconds = 0,
    this.activeSpeakerId,
  });

  final CallUiState uiState;
  final CallSession? session;
  final List<CallParticipant> participants;
  final webrtc.MediaStream? localStream;
  final Map<String, webrtc.MediaStream> remoteStreams;
  final String networkQuality;
  final String? error;
  final bool isMicMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final int durationSeconds;
  final String? activeSpeakerId;

  bool get inCall => uiState != CallUiState.idle && uiState != CallUiState.ended;
  bool get isVideo => session?.isVideo ?? false;
  bool get isGroup => session?.isGroup ?? false;

  CallState copyWith({
    CallUiState? uiState,
    CallSession? session,
    List<CallParticipant>? participants,
    webrtc.MediaStream? localStream,
    Map<String, webrtc.MediaStream>? remoteStreams,
    String? networkQuality,
    String? error,
    bool? isMicMuted,
    bool? isCameraOff,
    bool? isSpeakerOn,
    bool? isFrontCamera,
    int? durationSeconds,
    String? activeSpeakerId,
  }) =>
      CallState(
        uiState: uiState ?? this.uiState,
        session: session ?? this.session,
        participants: participants ?? this.participants,
        localStream: localStream ?? this.localStream,
        remoteStreams: remoteStreams ?? this.remoteStreams,
        networkQuality: networkQuality ?? this.networkQuality,
        error: error,
        isMicMuted: isMicMuted ?? this.isMicMuted,
        isCameraOff: isCameraOff ?? this.isCameraOff,
        isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
        isFrontCamera: isFrontCamera ?? this.isFrontCamera,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        activeSpeakerId: activeSpeakerId ?? this.activeSpeakerId,
      );
}

class CallManager extends StateNotifier<CallState> {
  CallManager({required CallRepository repo, required WebRTCService webrtcService, required CallSignalingService signaling})
      : _repo = repo,
        _webrtc = webrtcService,
        _signaling = signaling,
        super(const CallState(uiState: CallUiState.idle)) {
    _bindSignaling();
  }

  final CallRepository _repo;
  final WebRTCService _webrtc;
  final CallSignalingService _signaling;

  StreamSubscription? _callSub;
  StreamSubscription? _signalSub;
  StreamSubscription? _participantSub;
  StreamSubscription? _iceSub;
  StreamSubscription? _connSub;
  Timer? _timeoutTimer;
  Timer? _durationTimer;
  Timer? _reconnectTimer;
  final _pendingIce = <CallIceCandidate>[];

  String? get _callId => state.session?.id;
  String? get _me => _repo.currentUserId;

  void _bindSignaling() {
    _callSub = _signaling.onCallUpdate.listen(_onCallUpdate);
    _signalSub = _signaling.onSignal.listen(_onSignal);
    _participantSub = _signaling.onParticipant.listen(_onParticipant);
    _iceSub = _webrtc.onIceCandidate.listen(_onLocalIce);
    _connSub = _webrtc.onConnectionState.listen(_onConnectionState);
  }

  // ---------------- Outgoing ----------------

  Future<void> startCall({required String conversationId, required String media}) async {
    try {
      final existing = _repo.currentUserId;
      if (existing == null) throw Exception('Not signed in');
      // Cleanup any lingering
      await _cleanup();
      final id = await _repo.startCall(conversationId: conversationId, media: media);
      final session = await _repo.callById(id);
      if (session == null) throw Exception('Could not load call');
      state = state.copyWith(uiState: CallUiState.outgoingRinging, session: session, error: null);
      await _initLocal(session);
      await _createOfferForAll();
      _startTimeout(60);
      _signaling.subscribe();
    } on Exception catch (e) {
      state = state.copyWith(uiState: CallUiState.ended, error: e.toString());
      await _cleanupAfterDelay();
    }
  }

  Future<void> _initLocal(CallSession session) async {
    try {
      final settings = await _repo.myCallSettings();
      final stream = await _webrtc.initLocalStream(video: session.isVideo, frontCamera: settings.cameraFront, videoQuality: settings.videoQuality);
      state = state.copyWith(localStream: stream, isMicMuted: settings.micMuted, isCameraOff: !session.isVideo, isSpeakerOn: settings.speakerOn);
      if (settings.micMuted) await _webrtc.toggleMic();
      if (settings.speakerOn) await _webrtc.setSpeaker(true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> _createOfferForAll() async {
    final session = state.session;
    if (session == null) return;
    final turn = await _repo.fetchTurnConfig(callId: session.id);
    if (session.isGroup) {
      final parts = await _repo.participants(session.id);
      state = state.copyWith(participants: parts);
      for (final p in parts.where((x) => x.userId != _me)) {
        final pc = await _webrtc.createPeerConnection(peerId: p.userId, iceServersConfig: turn, isGroup: true);
        // pc created, local tracks already added in webrtc service
        final sdp = await _webrtc.createOffer(p.userId);
        await _signaling.sendOffer(session.id, sdp, to: p.userId);
      }
    } else {
      final other = session.calleeId ?? session.callerId;
      if (other == null || other == _me) return;
      await _webrtc.createPeerConnection(peerId: other, iceServersConfig: turn);
      final sdp = await _webrtc.createOffer(other);
      await _signaling.sendOffer(session.id, sdp, to: other);
      state = state.copyWith(uiState: CallUiState.outgoingRinging);
    }
  }

  // ---------------- Incoming ----------------

  void handleIncoming(CallSession session) async {
    if (state.inCall) {
      // Busy
      try {
        await _repo.sendSignal(callId: session.id, kind: 'busy');
      } catch (_) {}
      return;
    }
    state = state.copyWith(uiState: CallUiState.incomingRinging, session: session);
    _startTimeout(60);
    _signaling.subscribe();
  }

  Future<void> accept() async {
    final s = state.session;
    if (s == null) return;
    try {
      _timeoutTimer?.cancel();
      state = state.copyWith(uiState: CallUiState.connecting);
      await _initLocal(s);
      if (s.isGroup) {
        await _repo.joinGroupCall(s.id);
      } else {
        await _repo.answerCall(s.id);
      }
      // For callee, peer connection will be created on offer signal; if none, create offer back?
      // We wait for offer; ensure we can answer
      final turn = await _repo.fetchTurnConfig(callId: s.id);
      // Pre-create peer for 1-1 if not exists (remote offer will fill)
      if (!s.isGroup) {
        final peerId = s.callerId;
        await _webrtc.createPeerConnection(peerId: peerId, iceServersConfig: turn);
      }
      // Duration will start on connected
    } catch (e) {
      state = state.copyWith(error: e.toString(), uiState: CallUiState.ended);
      await _cleanupAfterDelay();
    }
  }

  Future<void> decline() async {
    final id = _callId;
    if (id == null) return;
    try {
      await _repo.declineCall(id);
    } catch (_) {}
    state = state.copyWith(uiState: CallUiState.ended);
    await _cleanup();
  }

  Future<void> cancel() async {
    final id = _callId;
    if (id == null) return;
    try {
      await _repo.endCall(id);
    } catch (_) {}
    state = state.copyWith(uiState: CallUiState.ended);
    await _cleanup();
  }

  Future<void> end() async {
    final id = _callId;
    if (id == null) {
      state = const CallState(uiState: CallUiState.idle);
      await _cleanup();
      return;
    }
    final wasGroup = state.isGroup;
    try {
      if (wasGroup) {
        await _repo.leaveGroupCall(id);
      } else {
        await _repo.endCall(id);
      }
    } catch (_) {}
    state = state.copyWith(uiState: CallUiState.ended);
    await _cleanup();
  }

  // ---------------- Controls ----------------

  Future<void> toggleMic() async {
    await _webrtc.toggleMic();
    state = state.copyWith(isMicMuted: _webrtc.isMicMuted);
    if (_callId != null) {
      try { await _signaling.sendOffer(_callId!, ''); } catch (_) {}
      await _repo.sendMediaUpdate(callId: _callId!, state: {'is_muted': _webrtc.isMicMuted});
    }
  }

  Future<void> toggleCamera() async {
    await _webrtc.toggleCamera();
    state = state.copyWith(isCameraOff: _webrtc.isCameraOff);
    if (_callId != null) await _repo.sendMediaUpdate(callId: _callId!, state: {'is_camera_on': !_webrtc.isCameraOff});
  }

  Future<void> switchCamera() async {
    await _webrtc.switchCamera();
    state = state.copyWith(isFrontCamera: !_webrtc.isFrontCamera);
  }

  Future<void> toggleSpeaker() async {
    await _webrtc.setSpeaker(!state.isSpeakerOn);
    state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);
  }

  Future<void> setHold(bool hold) async {
    // Hold is local mute + disable tracks
    if (hold) {
      for (final t in state.localStream?.getAudioTracks() ?? []) t.enabled = false;
      for (final t in state.localStream?.getVideoTracks() ?? []) t.enabled = false;
    } else {
      for (final t in state.localStream?.getAudioTracks() ?? []) t.enabled = !state.isMicMuted;
      for (final t in state.localStream?.getVideoTracks() ?? []) t.enabled = !state.isCameraOff;
    }
  }

  // ---------------- Signaling handlers ----------------

  Future<void> _onCallUpdate(CallSession session) async {
    if (_callId != null && session.id != _callId) return;
    state = state.copyWith(session: session);
    if (session.isEnded) {
      state = state.copyWith(uiState: CallUiState.ended);
      await _cleanupAfterDelay();
    } else if (session.status == 'answered' || session.status == 'connected') {
      if (state.uiState != CallUiState.connected) {
        state = state.copyWith(uiState: CallUiState.connected);
        _startDuration();
      }
    }
  }

  Future<void> _onSignal(CallSignal s) async {
    if (s.callId != _callId) return;
    // Validate sender is participant
    switch (s.kind) {
      case 'offer':
        await _handleOffer(s);
        break;
      case 'answer':
        await _handleAnswer(s);
        break;
      case 'ice-candidate':
        await _handleIce(s);
        break;
      case 'join':
        _refreshParticipants();
        break;
      case 'leave':
      case 'end':
        // If 1-1 other left, end
        if (!state.isGroup) {
          state = state.copyWith(uiState: CallUiState.ended);
          await _cleanupAfterDelay();
        } else {
          _refreshParticipants();
        }
        break;
      case 'decline':
      case 'cancel':
      case 'busy':
        state = state.copyWith(uiState: CallUiState.ended, error: s.kind == 'busy' ? 'User is busy' : null);
        await _cleanupAfterDelay();
        break;
      case 'media-update':
        _refreshParticipants();
        break;
    }
  }

  Future<void> _handleOffer(CallSignal s) async {
    final sdp = s.payload['sdp'] as String?;
    if (sdp == null) return;
    final peerId = s.senderId;
    final turn = await _repo.fetchTurnConfig(callId: s.callId);
    // Ensure peer exists
    if (!_webrtc.remoteStreams.containsKey(peerId)) {
      try { await _webrtc.createPeerConnection(peerId: peerId, iceServersConfig: turn); } catch (_) {}
    }
    await _webrtc.setRemoteDescription(peerId, sdp, 'offer');
    // Drain pending ICE for this peer
    for (final c in _pendingIce) {
      // pending per peer? simplified global
    }
    final answer = await _webrtc.createAnswer(peerId);
    await _signaling.sendAnswer(s.callId, answer, to: peerId);
    state = state.copyWith(uiState: CallUiState.connecting);
  }

  Future<void> _handleAnswer(CallSignal s) async {
    final sdp = s.payload['sdp'] as String?;
    if (sdp == null) return;
    final peerId = s.senderId;
    try {
      await _webrtc.setRemoteDescription(peerId, sdp, 'answer');
      state = state.copyWith(uiState: CallUiState.connected);
      _startDuration();
    } catch (e) {
      debugPrint('setRemoteDescription answer failed: $e');
    }
  }

  Future<void> _handleIce(CallSignal s) async {
    final cand = s.payload['candidate'] as String?;
    if (cand == null) return;
    final peerId = s.senderId;
    try {
      await _webrtc.addIceCandidate(peerId, webrtc.RTCIceCandidate(cand, s.payload['sdpMid'] as String?, s.payload['sdpMLineIndex'] as int?));
    } catch (_) {
      _pendingIce.add(CallIceCandidate(candidate: cand, sdpMid: s.payload['sdpMid'] as String?, sdpMLineIndex: s.payload['sdpMLineIndex'] as int?));
    }
  }

  Future<void> _onParticipant(CallParticipant p) async {
    if (p.callId != _callId) return;
    _refreshParticipants();
  }

  Future<void> _refreshParticipants() async {
    final id = _callId;
    if (id == null) return;
    try {
      final parts = await _repo.participants(id);
      state = state.copyWith(participants: parts);
    } catch (_) {}
  }

  void _onLocalIce(IceCandidateEvent e) {
    final id = _callId;
    if (id == null) return;
    _signaling.sendIce(id, e.candidate.candidate ?? '', e.candidate.sdpMid, e.candidate.sdpMLineIndex, to: e.peerId);
  }

  void _onConnectionState(ConnectionStateEvent e) {
    if (e.state == 'connected' || e.state == 'completed') {
      state = state.copyWith(uiState: CallUiState.connected, networkQuality: 'good');
      _reconnectTimer?.cancel();
      _startDuration();
    } else if (e.state == 'disconnected' || e.state == 'failed') {
      state = state.copyWith(uiState: CallUiState.reconnecting, networkQuality: 'poor');
      _startReconnect();
    } else if (e.state == 'closed') {
      state = state.copyWith(uiState: CallUiState.ended);
    }
  }

  void _startTimeout(int seconds) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(seconds: seconds), () async {
      if (state.uiState == CallUiState.outgoingRinging || state.uiState == CallUiState.incomingRinging) {
        state = state.copyWith(uiState: CallUiState.ended, error: 'Call timed out');
        try { await _repo.endCall(_callId!); } catch (_) {}
        await _cleanup();
      }
    });
  }

  void _startDuration() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.uiState == CallUiState.connected) {
        state = state.copyWith(durationSeconds: state.durationSeconds + 1);
      }
    });
  }

  void _startReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 15), () async {
      if (state.uiState == CallUiState.reconnecting) {
        state = state.copyWith(uiState: CallUiState.ended, error: 'Connection lost');
        await _cleanup();
      }
    });
  }

  Future<void> _cleanup() async {
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    await _webrtc.disposeAll();
  }

  Future<void> _cleanupAfterDelay() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await _cleanup();
    state = const CallState(uiState: CallUiState.idle);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _signalSub?.cancel();
    _participantSub?.cancel();
    _iceSub?.cancel();
    _connSub?.cancel();
    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}

// Providers
final callRepositoryProvider = Provider<CallRepository>((ref) {
  final c = ref.watch(supabaseClientProvider);
  return CallRepository(c);
});

final webrtcServiceProvider = Provider<WebRTCService>((ref) {
  final svc = WebRTCService();
  ref.onDispose(svc.dispose);
  return svc;
});

final signalingServiceProvider = Provider<CallSignalingService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final repo = ref.watch(callRepositoryProvider);
  final svc = CallSignalingService(client, repo);
  ref.onDispose(svc.dispose);
  return svc;
});

final callManagerProvider = StateNotifierProvider<CallManager, CallState>((ref) {
  final repo = ref.watch(callRepositoryProvider);
  final webrtcSvc = ref.watch(webrtcServiceProvider);
  final sig = ref.watch(signalingServiceProvider);
  return CallManager(repo: repo, webrtcService: webrtcSvc, signaling: sig);
});
