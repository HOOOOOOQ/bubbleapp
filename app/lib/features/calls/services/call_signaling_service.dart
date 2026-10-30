import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/call_repository.dart';
import '../../../models/call_models.dart';

/// Secure signaling via Supabase Realtime + RPC.
/// Validates membership server-side; client never trusts role flags.
class CallSignalingService {
  CallSignalingService(this._client, this._repo);
  final SupabaseClient _client;
  final CallRepository _repo;

  RealtimeChannel? _callChannel;
  RealtimeChannel? _signalChannel;
  final _callUpdateCtrl = StreamController<CallSession>.broadcast();
  final _signalCtrl = StreamController<CallSignal>.broadcast();
  final _participantCtrl = StreamController<CallParticipant>.broadcast();
  final _seenSignalIds = <String>{};

  Stream<CallSession> get onCallUpdate => _callUpdateCtrl.stream;
  Stream<CallSignal> get onSignal => _signalCtrl.stream;
  Stream<CallParticipant> get onParticipant => _participantCtrl.stream;

  void subscribe() {
    if (_callChannel != null) return;

    _callChannel = _client.channel('bubbleapp:calls').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          callback: (payload) {
            try {
              final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
              if (row.isEmpty) return;
              _callUpdateCtrl.add(CallSession.fromJson(row));
            } catch (_) {}
          },
        ).onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'call_participants',
          callback: (payload) {
            try {
              final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
              if (row.isEmpty) return;
              _participantCtrl.add(CallParticipant.fromJson(row));
            } catch (_) {}
          },
        ).subscribe();

    _signalChannel = _client.channel('bubbleapp:call_signals').onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          callback: (payload) {
            try {
              final row = payload.newRecord;
              final id = row['id'] as String?;
              if (id == null || _seenSignalIds.contains(id)) return;
              _seenSignalIds.add(id);
              if (_seenSignalIds.length > 5000) _seenSignalIds.remove(_seenSignalIds.first);
              final signal = CallSignal.fromJson(row);
              // Only deliver if directed to me or broadcast (receiver null)
              final me = _client.auth.currentUser?.id;
              if (signal.receiverId == null || signal.receiverId == me) {
                _signalCtrl.add(signal);
              }
            } catch (_) {}
          },
        ).subscribe();
  }

  void unsubscribe() {
    if (_callChannel != null) {
      _client.removeChannel(_callChannel!);
      _callChannel = null;
    }
    if (_signalChannel != null) {
      _client.removeChannel(_signalChannel!);
      _signalChannel = null;
    }
  }

  Future<void> sendOffer(String callId, String sdp, {String? to}) => _repo.sendOffer(callId: callId, sdp: sdp, receiverId: to);
  Future<void> sendAnswer(String callId, String sdp, {String? to}) => _repo.sendAnswer(callId: callId, sdp: sdp, receiverId: to);
  Future<void> sendIce(String callId, String candidate, String? sdpMid, int? sdpMLineIndex, {String? to}) =>
      _repo.sendIceCandidate(callId: callId, candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, receiverId: to);

  void dispose() {
    unsubscribe();
    _callUpdateCtrl.close();
    _signalCtrl.close();
    _participantCtrl.close();
  }
}
