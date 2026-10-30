import 'package:bubbleapp/models/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallSession', () {
    test('parses basic 1-1 ringing', () {
      final c = CallSession.fromJson({
        'id': 'call1',
        'conversation_id': 'conv1',
        'caller_id': 'u1',
        'callee_id': 'u2',
        'media': 'voice',
        'status': 'ringing',
        'is_group': false,
        'started_at': '2024-01-01T10:00:00Z',
      });
      expect(c.isGroup, isFalse);
      expect(c.isVideo, isFalse);
      expect(c.isRinging, isTrue);
      expect(c.isEnded, isFalse);
      expect(c.otherParticipantId('u1'), 'u2');
      expect(c.otherParticipantId('u2'), 'u1');
    });

    test('group host logic', () {
      final c = CallSession.fromJson({
        'id': 'c2',
        'conversation_id': 'conv2',
        'caller_id': 'u1',
        'media': 'video',
        'status': 'answered',
        'is_group': true,
        'group_host_id': 'u1',
        'started_at': '2024-01-02T12:00:00Z',
        'answered_at': '2024-01-02T12:00:05Z',
      });
      expect(c.isGroup, isTrue);
      expect(c.isVideo, isTrue);
      expect(c.isConnected, isTrue);
    });

    test('duration computed from seconds', () {
      final c = CallSession.fromJson({
        'id': 'c3',
        'conversation_id': 'conv1',
        'caller_id': 'u1',
        'callee_id': 'u2',
        'media': 'voice',
        'status': 'ended',
        'duration_seconds': 65,
        'started_at': '2024-01-01T10:00:00Z',
        'ended_at': '2024-01-01T10:01:05Z',
      });
      expect(c.duration, const Duration(seconds: 65));
      expect(c.isEnded, isTrue);
      expect(c.isMissed, isFalse);
    });

    test('all end states are ended', () {
      for (final s in ['ended', 'missed', 'declined', 'cancelled', 'failed', 'busy', 'timeout']) {
        final c = CallSession.fromJson({
          'id': 'c',
          'conversation_id': 'conv1',
          'caller_id': 'u1',
          'callee_id': 'u2',
          'media': 'voice',
          'status': s,
        });
        expect(c.isEnded, isTrue, reason: s);
      }
      expect(CallSession.fromJson({'id': 'c', 'conversation_id': 'conv1', 'caller_id': 'u1', 'media': 'voice', 'status': 'ringing'}).isEnded, isFalse);
    });

    test('copyWith preserves fields', () {
      final c = CallSession.fromJson({
        'id': 'c1',
        'conversation_id': 'conv1',
        'caller_id': 'u1',
        'callee_id': 'u2',
        'media': 'voice',
        'status': 'ringing',
      });
      final ended = c.copyWith(status: 'ended', endedReason: 'completed');
      expect(ended.status, 'ended');
      expect(ended.endedReason, 'completed');
      expect(ended.id, 'c1');
    });
  });

  group('CallParticipant', () {
    test('joined/host flags', () {
      final p = CallParticipant.fromJson({
        'call_id': 'c1',
        'user_id': 'u1',
        'role': 'host',
        'status': 'joined',
        'is_muted': false,
        'is_camera_on': true,
      });
      expect(p.isHost, isTrue);
      expect(p.isJoined, isTrue);
      expect(p.isMuted, isFalse);
      expect(p.isCameraOn, isTrue);
    });
  });

  group('CallSignal', () {
    test('kind helpers', () {
      final offer = CallSignal.fromJson({'id': 's1', 'call_id': 'c1', 'sender_id': 'u1', 'kind': 'offer', 'payload': {'sdp': 'v=0'}});
      expect(offer.isOffer, isTrue);
      expect(offer.isAnswer, isFalse);
      expect(offer.payload['sdp'], 'v=0');

      final ice = CallSignal.fromJson({'id': 's2', 'call_id': 'c1', 'sender_id': 'u1', 'kind': 'ice-candidate', 'payload': {'candidate': 'candidate:...'}});
      expect(ice.isIce, isTrue);
    });
  });

  group('CallSettings', () {
    test('defaults and copyWith', () {
      final d = CallSettings.defaults();
      expect(d.cameraFront, isTrue);
      expect(d.videoQuality, 'auto');
      final muted = d.copyWith(micMuted: true, videoQuality: 'high');
      expect(muted.micMuted, isTrue);
      expect(muted.videoQuality, 'high');
      expect(d.micMuted, isFalse); // original unchanged
    });

    test('fromJson tolerant', () {
      final s = CallSettings.fromJson({'mic_muted': true, 'video_quality': 'low'});
      expect(s.micMuted, isTrue);
      expect(s.videoQuality, 'low');
      expect(s.noiseSuppression, isTrue); // default true
    });
  });

  group('CallHistoryEntry', () {
    test('flags', () {
      final call = CallSession.fromJson({
        'id': 'c1',
        'conversation_id': 'conv1',
        'caller_id': 'u1',
        'callee_id': 'u2',
        'media': 'video',
        'status': 'missed',
        'is_group': false,
      });
      final e = CallHistoryEntry(call: call, direction: 'missed', otherUser: null);
      expect(e.isMissed, isTrue);
      expect(e.isVideo, isTrue);
      expect(e.isGroup, isFalse);
    });
  });
}
