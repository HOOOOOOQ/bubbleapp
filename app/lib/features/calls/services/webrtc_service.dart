import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:permission_handler/permission_handler.dart';

/// Dedicated WebRTC engine — owns peer connections, local/remote streams,
/// and media controls. No UI logic here.
class WebRTCService {
  // Local media
  webrtc.MediaStream? _localStream;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _isFrontCamera = true;

  // Connections: for 1-1 one peer; for group SFU/mesh one per participant
  final Map<String, webrtc.RTCPeerConnection> _peers = {};
  final Map<String, webrtc.MediaStream> _remoteStreams = {};

  final _onIceCandidateCtrl = StreamController<IceCandidateEvent>.broadcast();
  final _onConnectionStateCtrl = StreamController<ConnectionStateEvent>.broadcast();
  final _onTrackCtrl = StreamController<TrackEvent>.broadcast();
  final _onRemoteStreamCtrl = StreamController<RemoteStreamEvent>.broadcast();

  Stream<IceCandidateEvent> get onIceCandidate => _onIceCandidateCtrl.stream;
  Stream<ConnectionStateEvent> get onConnectionState => _onConnectionStateCtrl.stream;
  Stream<TrackEvent> get onTrack => _onTrackCtrl.stream;
  Stream<RemoteStreamEvent> get onRemoteStream => _onRemoteStreamCtrl.stream;

  webrtc.MediaStream? get localStream => _localStream;
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  Map<String, webrtc.MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreams);

  /// Request permissions with meaningful errors
  Future<void> ensurePermissions({required bool video}) async {
    if (video) {
      final cam = await Permission.camera.request();
      if (cam.isDenied || cam.isPermanentlyDenied) {
        throw CallException('Camera permission denied. Enable it in Settings to make video calls.', code: 'camera_denied');
      }
    }
    final mic = await Permission.microphone.request();
    if (mic.isDenied || mic.isPermanentlyDenied) {
      throw CallException('Microphone permission denied. Enable it in Settings to make calls.', code: 'mic_denied');
    }
  }

  Future<webrtc.MediaStream> initLocalStream({required bool video, bool frontCamera = true, String videoQuality = 'auto'}) async {
    await ensurePermissions(video: video);
    try {
      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'facingMode': frontCamera ? 'user' : 'environment',
                'width': _widthForQuality(videoQuality),
                'height': _heightForQuality(videoQuality),
                'frameRate': 30,
              }
            : false,
      };
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia(constraints);
      _isFrontCamera = frontCamera;
      _isCameraOff = !video;
      _isMicMuted = false;
      // Apply initial tracks enabled state
      _applyLocalTracks();
      return _localStream!;
    } catch (e) {
      if (e.toString().contains('NotFound') || e.toString().contains('Overconstrained')) {
        throw CallException('Camera or microphone not available on this device.', code: 'device_unavailable');
      }
      if (e.toString().contains('NotAllowed') || e.toString().contains('Permission')) {
        throw CallException('Media permission was denied.', code: 'permission_denied');
      }
      throw CallException('Could not access camera/microphone: $e', code: 'media_failure');
    }
  }

  void _applyLocalTracks() {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMicMuted;
    }
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = !_isCameraOff;
    }
  }

  Future<void> toggleMic() async {
    _isMicMuted = !_isMicMuted;
    for (final t in _localStream?.getAudioTracks() ?? []) {
      t.enabled = !_isMicMuted;
    }
  }

  Future<void> toggleCamera() async {
    if (_localStream == null) return;
    _isCameraOff = !_isCameraOff;
    for (final t in _localStream!.getVideoTracks()) {
      t.enabled = !_isCameraOff;
    }
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;
    try {
      await webrtc.Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
    } catch (e) {
      debugPrint('switchCamera failed: $e');
      throw CallException('Could not switch camera.', code: 'camera_switch_failed');
    }
  }

  Future<void> setSpeaker(bool on) async {
    _isSpeakerOn = on;
    try {
      await webrtc.Helper.setSpeakerphoneOn(on);
    } catch (e) {
      debugPrint('setSpeakerphoneOn failed: $e');
      // Not all platforms support — soft fail
    }
  }

  // ---------------- Peer Connection ----------------

  Future<webrtc.RTCPeerConnection> createPeerConnection({
    required String peerId,
    required Map<String, dynamic> iceServersConfig,
    bool isGroup = false,
  }) async {
    final config = <String, dynamic>{
      'iceServers': iceServersConfig['iceServers'] ?? [
        {'urls': 'stun:stun.l.google.com:19302'}
      ],
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    };
    final pc = await webrtc.createPeerConnection(config);

    // Add local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _onIceCandidateCtrl.add(IceCandidateEvent(peerId: peerId, candidate: candidate));
      }
    };

    pc.onConnectionState = (state) {
      _onConnectionStateCtrl.add(ConnectionStateEvent(peerId: peerId, state: state.name, raw: state));
      if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handlePeerFailed(peerId);
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('ICE $peerId: $state');
      if (state == webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed) {
        pc.restartIce();
      }
    };

    pc.onTrack = (event) {
      final stream = event.streams.isNotEmpty ? event.streams.first : null;
      if (stream != null) {
        _remoteStreams[peerId] = stream;
        _onRemoteStreamCtrl.add(RemoteStreamEvent(peerId: peerId, stream: stream));
      }
      _onTrackCtrl.add(TrackEvent(peerId: peerId, track: event.track, streams: event.streams));
    };

    pc.onRemoveTrack = (stream, track) {
      debugPrint('Removed track $peerId');
    };

    _peers[peerId] = pc;
    return pc;
  }

  Future<String> createOffer(String peerId) async {
    final pc = _peers[peerId];
    if (pc == null) throw CallException('Peer not found', code: 'peer_not_found');
    final offer = await pc.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  Future<String> createAnswer(String peerId) async {
    final pc = _peers[peerId];
    if (pc == null) throw CallException('Peer not found', code: 'peer_not_found');
    final answer = await pc.createAnswer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await pc.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  Future<void> setRemoteDescription(String peerId, String sdp, String type) async {
    final pc = _peers[peerId];
    if (pc == null) throw CallException('Peer not found', code: 'peer_not_found');
    await pc.setRemoteDescription(webrtc.RTCSessionDescription(sdp, type));
  }

  Future<void> addIceCandidate(String peerId, webrtc.RTCIceCandidate candidate) async {
    final pc = _peers[peerId];
    if (pc == null) return; // peer may have left
    await pc.addCandidate(candidate);
  }

  void _handlePeerFailed(String peerId) {
    _onConnectionStateCtrl.add(ConnectionStateEvent(peerId: peerId, state: 'failed', raw: webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed));
  }

  Future<void> closePeer(String peerId) async {
    final pc = _peers.remove(peerId);
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    final stream = _remoteStreams.remove(peerId);
    try {
      await stream?.dispose();
    } catch (_) {}
  }

  Future<void> disposeAll() async {
    for (final id in _peers.keys.toList()) {
      await closePeer(id);
    }
    _peers.clear();
    _remoteStreams.clear();
    if (_localStream != null) {
      for (final t in _localStream!.getTracks()) {
        try { await t.stop(); } catch (_) {}
      }
      try { await _localStream!.dispose(); } catch (_) {}
      _localStream = null;
    }
    _isMicMuted = false;
    _isCameraOff = false;
  }

  void dispose() {
    disposeAll();
    _onIceCandidateCtrl.close();
    _onConnectionStateCtrl.close();
    _onTrackCtrl.close();
    _onRemoteStreamCtrl.close();
  }

  int _widthForQuality(String q) {
    switch (q) {
      case 'low': return 320;
      case 'medium': return 640;
      case 'high': return 1280;
      default: return 640; // auto
    }
  }

  int _heightForQuality(String q) {
    switch (q) {
      case 'low': return 240;
      case 'medium': return 480;
      case 'high': return 720;
      default: return 480;
    }
  }
}

// ---- Events ----

class IceCandidateEvent {
  IceCandidateEvent({required this.peerId, required this.candidate});
  final String peerId;
  final webrtc.RTCIceCandidate candidate;
}

class ConnectionStateEvent {
  ConnectionStateEvent({required this.peerId, required this.state, required this.raw});
  final String peerId;
  final String state;
  final webrtc.RTCPeerConnectionState raw;
}

class TrackEvent {
  TrackEvent({required this.peerId, required this.track, required this.streams});
  final String peerId;
  final webrtc.MediaStreamTrack track;
  final List<webrtc.MediaStream> streams;
}

class RemoteStreamEvent {
  RemoteStreamEvent({required this.peerId, required this.stream});
  final String peerId;
  final webrtc.MediaStream stream;
}

class CallException implements Exception {
  CallException(this.message, {required this.code});
  final String message;
  final String code;
  @override
  String toString() => message;
}
