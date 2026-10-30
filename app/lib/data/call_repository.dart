import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/call_models.dart';
import '../models/models.dart';

/// Repository for call sessions, participants, signals, and history.
/// All names match migrations 0009 + 0012; RLS enforces membership.
class CallRepository {
  CallRepository(this._client);
  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ------------ Sessions ------------

  Future<String> startCall({required String conversationId, required String media}) async {
    final id = await _client.rpc('start_call', params: {'p_conversation_id': conversationId, 'p_media': media});
    return id.toString();
  }

  Future<void> answerCall(String callId) => _client.rpc('answer_call', params: {'p_call_id': callId});
  Future<void> declineCall(String callId) => _client.rpc('decline_call', params: {'p_call_id': callId});
  Future<void> endCall(String callId) => _client.rpc('end_call', params: {'p_call_id': callId});
  Future<void> joinGroupCall(String callId) => _client.rpc('join_group_call', params: {'p_call_id': callId});
  Future<void> leaveGroupCall(String callId) => _client.rpc('leave_group_call', params: {'p_call_id': callId});

  Future<List<CallSession>> myCalls({int limit = 50, int offset = 0}) async {
    final rows = await _client.from('calls').select().order('started_at', ascending: false).range(offset, offset + limit - 1);
    final hidden = await _hiddenCallIds();
    final filtered = rows.where((r) => !hidden.contains(r['id'] as String)).map(CallSession.fromJson).toList();
    return filtered;
  }

  Future<CallSession?> callById(String callId) async {
    final row = await _client.from('calls').select().eq('id', callId).maybeSingle();
    return row == null ? null : CallSession.fromJson(row);
  }

  Future<List<CallHistoryEntry>> myCallHistory({int limit = 50}) async {
    final uid = currentUserId;
    if (uid == null) return [];
    final calls = await myCalls(limit: limit);
    final hidden = await _hiddenCallIds();
    final visible = calls.where((c) => !hidden.contains(c.id)).toList();

    final otherIds = visible.where((c) => !c.isGroup).map((c) => c.callerId == uid ? c.calleeId : c.callerId).whereType<String>().toSet().toList();
    Map<String, dynamic> profiles = {};
    if (otherIds.isNotEmpty) {
      final rows = await _client.from('profiles').select('id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at').inFilter('id', otherIds);
      for (final r in rows) profiles[r['id'] as String] = r;
    }

    return visible.map((call) {
      String direction;
      String? otherId;
      if (call.callerId == uid) {
        direction = call.isMissed ? 'missed' : 'outgoing';
        otherId = call.calleeId;
      } else {
        direction = call.isMissed ? 'missed' : 'incoming';
        otherId = call.callerId;
      }
      if (call.status == 'missed') direction = 'missed';
      final otherProfile = otherId != null && profiles[otherId] != null ? UserProfile.fromJson(profiles[otherId] as Map<String, dynamic>) : null;
      return CallHistoryEntry(call: call, direction: direction, otherUser: otherProfile);
    }).toList();
  }

  Future<Set<String>> _hiddenCallIds() async {
    final uid = currentUserId;
    if (uid == null) return {};
    try {
      final rows = await _client.from('call_history_visibility').select('call_id').eq('user_id', uid);
      return rows.map((r) => r['call_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> hideCallHistory(String callId) => _client.rpc('hide_call_history', params: {'p_call_id': callId});
  Future<void> clearCallHistory() => _client.rpc('clear_call_history');

  // ------------ Participants ------------

  Future<List<CallParticipant>> participants(String callId) async {
    final rows = await _client.from('call_participants').select('call_id, user_id, role, status, joined_at, left_at, is_muted, is_camera_on, is_deafened, created_at').eq('call_id', callId);
    final ids = rows.map((r) => r['user_id'] as String).toList();
    Map<String, dynamic> profiles = {};
    if (ids.isNotEmpty) {
      final pr = await _client.from('profiles').select('id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at').inFilter('id', ids);
      for (final p in pr) profiles[p['id'] as String] = p;
    }
    return rows.map((r) {
      final uid = r['user_id'] as String;
      final profile = profiles[uid];
      return CallParticipant.fromJson({...r, if (profile != null) 'profile': profile});
    }).toList();
  }

  // ------------ Signaling ------------

  Future<String> sendSignal({required String callId, required String kind, String? receiverId, Map<String, dynamic>? payload}) async {
    final id = await _client.rpc('send_call_signal', params: {
      'p_call_id': callId,
      'p_kind': kind,
      'p_receiver': receiverId,
      'p_payload': payload ?? {},
    });
    return id.toString();
  }

  Future<void> sendOffer({required String callId, required String sdp, String? receiverId}) => sendSignal(callId: callId, kind: 'offer', receiverId: receiverId, payload: {'sdp': sdp, 'type': 'offer'});
  Future<void> sendAnswer({required String callId, required String sdp, String? receiverId}) => sendSignal(callId: callId, kind: 'answer', receiverId: receiverId, payload: {'sdp': sdp, 'type': 'answer'});
  Future<void> sendIceCandidate({required String callId, required String candidate, String? sdpMid, int? sdpMLineIndex, String? receiverId}) =>
      sendSignal(callId: callId, kind: 'ice-candidate', receiverId: receiverId, payload: {'candidate': candidate, 'sdpMid': sdpMid, 'sdpMLineIndex': sdpMLineIndex});
  Future<void> sendMediaUpdate({required String callId, required Map<String, dynamic> state}) => sendSignal(callId: callId, kind: 'media-update', payload: state);

  Future<List<CallSignal>> fetchSignals(String callId) async {
    final rows = await _client.from('call_signals').select().eq('call_id', callId).order('created_at', ascending: true);
    return rows.map(CallSignal.fromJson).toList();
  }

  // ------------ Settings ------------

  Future<CallSettings> myCallSettings() async {
    final uid = currentUserId;
    if (uid == null) return CallSettings.defaults();
    final row = await _client.from('user_settings').select('call_settings').eq('user_id', uid).maybeSingle();
    final j = row?['call_settings'] as Map<String, dynamic>?;
    return j == null ? CallSettings.defaults() : CallSettings.fromJson(j);
  }

  Future<void> updateCallSettings(CallSettings s) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client.from('user_settings').update({'call_settings': s.toJson()}).eq('user_id', uid);
  }

  // ------------ TURN ------------

  Future<Map<String, dynamic>> fetchTurnConfig({String? callId}) async {
    try {
      final res = await _client.functions.invoke('turn-credentials', body: callId == null ? {} : {'call_id': callId});
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      return {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
    } catch (_) {
      return {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
    }
  }
}
