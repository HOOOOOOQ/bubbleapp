import 'package:bubbleapp/features/calls/state/call_manager.dart';
import 'package:bubbleapp/models/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallUiState transitions', () {
    test('idle -> outgoingRinging -> connecting -> connected -> ended', () {
      const idle = CallState(uiState: CallUiState.idle);
      expect(idle.inCall, isFalse);

      final ringing = idle.copyWith(uiState: CallUiState.outgoingRinging, session: CallSession.fromJson({
        'id': 'c1', 'conversation_id': 'conv1', 'caller_id': 'u1', 'callee_id': 'u2', 'media': 'voice', 'status': 'ringing',
      }));
      expect(ringing.inCall, isTrue);
      expect(ringing.isVideo, isFalse);

      final connected = ringing.copyWith(uiState: CallUiState.connected, durationSeconds: 5);
      expect(connected.durationSeconds, 5);

      const ended = CallState(uiState: CallUiState.ended);
      expect(ended.inCall, isFalse);
    });

    test('reconnecting preserves session', () {
      final connected = CallState(
        uiState: CallUiState.connected,
        session: CallSession.fromJson({'id': 'c1', 'conversation_id': 'conv1', 'caller_id': 'u1', 'media': 'voice', 'status': 'connected'}),
        networkQuality: 'good',
      );
      final reconnecting = connected.copyWith(uiState: CallUiState.reconnecting, networkQuality: 'poor');
      expect(reconnecting.networkQuality, 'poor');
      expect(reconnecting.session?.id, 'c1');
    });

    test('group vs 1-1 flags', () {
      final group = CallState(
        uiState: CallUiState.connected,
        session: CallSession.fromJson({'id': 'c1', 'conversation_id': 'conv1', 'caller_id': 'u1', 'media': 'video', 'status': 'connected', 'is_group': true}),
      );
      expect(group.isGroup, isTrue);
      expect(group.isVideo, isTrue);

      final direct = CallState(
        uiState: CallUiState.connected,
        session: CallSession.fromJson({'id': 'c2', 'conversation_id': 'conv1', 'caller_id': 'u1', 'callee_id': 'u2', 'media': 'voice', 'status': 'connected'}),
      );
      expect(direct.isGroup, isFalse);
    });
  });

  group('CallSettings in user_settings', () {
    test('copyWith for toggles', () {
      final s = CallSettings.defaults();
      final toggled = s.copyWith(micMuted: true, speakerOn: true, dataSaver: true);
      expect(toggled.micMuted, isTrue);
      expect(toggled.speakerOn, isTrue);
      expect(toggled.dataSaver, isTrue);
      expect(s.micMuted, isFalse);
    });
  });

  group('Network quality', () {
    test('reconnecting is poor', () {
      const poor = CallState(uiState: CallUiState.reconnecting, networkQuality: 'poor');
      expect(poor.networkQuality, 'poor');
    });
  });
}
