import '../models/models.dart';

String _s(Object? v, [String f = '']) => v is String ? v : f;
bool _b(Object? v) => v == true;
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Call session — mirrors public.calls row (extended 0012)
class CallSession {
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.media,
    required this.status,
    required this.isGroup,
    required this.startedAt,
    this.groupHostId,
    this.answeredAt,
    this.endedAt,
    this.endedReason,
    this.durationSeconds,
    this.sfuRoomId,
    this.maxParticipants,
    this.updatedAt,
    this.callerProfile,
    this.calleeProfile,
  });

  final String id;
  final String conversationId;
  final String callerId;
  final String? calleeId;
  final String media; // voice | video
  final String status; // ringing | connecting | connected | reconnecting | answered | ended | missed | declined | cancelled | failed | busy | timeout
  final bool isGroup;
  final DateTime? startedAt;
  final String? groupHostId;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endedReason;
  final int? durationSeconds;
  final String? sfuRoomId;
  final int? maxParticipants;
  final DateTime? updatedAt;
  final UserProfile? callerProfile;
  final UserProfile? calleeProfile;

  bool get isVideo => media == 'video';
  bool get isRinging => status == 'ringing';
  bool get isConnecting => status == 'connecting';
  bool get isConnected => status == 'connected' || status == 'answered';
  bool get isReconnecting => status == 'reconnecting';
  bool get isEnded => const {'ended', 'missed', 'declined', 'cancelled', 'failed', 'busy', 'timeout'}.contains(status);
  bool get isMissed => status == 'missed';
  bool get isDeclined => status == 'declined';
  bool get isFailed => status == 'failed';
  bool get isBusy => status == 'busy';
  bool get isCancelled => status == 'cancelled';

  bool isForUser(String userId) => callerId == userId || calleeId == userId || groupHostId == userId;

  String otherParticipantId(String me) {
    if (isGroup) return groupHostId == me ? (calleeId ?? callerId) : callerId;
    if (callerId == me) return calleeId ?? '';
    return callerId;
  }

  Duration? get duration {
    if (durationSeconds != null) return Duration(seconds: durationSeconds!);
    if (answeredAt != null && endedAt != null) return endedAt!.difference(answeredAt!);
    if (answeredAt != null) return DateTime.now().difference(answeredAt!);
    return null;
  }

  factory CallSession.fromJson(Map<String, dynamic> j) => CallSession(
        id: _s(j['id']),
        conversationId: _s(j['conversation_id']),
        callerId: _s(j['caller_id']),
        calleeId: j['callee_id'] as String?,
        media: _s(j['media'], 'voice'),
        status: _s(j['status'], 'ringing'),
        isGroup: _b(j['is_group']),
        startedAt: _d(j['started_at']),
        groupHostId: j['group_host_id'] as String?,
        answeredAt: _d(j['answered_at']),
        endedAt: _d(j['ended_at']),
        endedReason: j['ended_reason'] as String?,
        durationSeconds: j['duration_seconds'] as int?,
        sfuRoomId: j['sfu_room_id'] as String?,
        maxParticipants: j['max_participants'] as int?,
        updatedAt: _d(j['updated_at']),
        callerProfile: j['caller'] is Map<String, dynamic> ? UserProfile.fromJson(j['caller'] as Map<String, dynamic>) : null,
        calleeProfile: j['callee'] is Map<String, dynamic> ? UserProfile.fromJson(j['callee'] as Map<String, dynamic>) : null,
      );

  CallSession copyWith({String? status, DateTime? answeredAt, DateTime? endedAt, String? endedReason}) => CallSession(
        id: id,
        conversationId: conversationId,
        callerId: callerId,
        calleeId: calleeId,
        media: media,
        status: status ?? this.status,
        isGroup: isGroup,
        startedAt: startedAt,
        groupHostId: groupHostId,
        answeredAt: answeredAt ?? this.answeredAt,
        endedAt: endedAt ?? this.endedAt,
        endedReason: endedReason ?? this.endedReason,
        durationSeconds: durationSeconds,
        sfuRoomId: sfuRoomId,
        maxParticipants: maxParticipants,
        updatedAt: updatedAt,
        callerProfile: callerProfile,
        calleeProfile: calleeProfile,
      );
}

class CallParticipant {
  const CallParticipant({
    required this.callId,
    required this.userId,
    required this.role,
    required this.status,
    this.joinedAt,
    this.leftAt,
    required this.isMuted,
    required this.isCameraOn,
    required this.isDeafened,
    this.profile,
  });

  final String callId;
  final String userId;
  final String role; // host | member
  final String status; // invited | joined | left | declined | missed | failed
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final bool isMuted;
  final bool isCameraOn;
  final bool isDeafened;
  final UserProfile? profile;

  bool get isJoined => status == 'joined';
  bool get isHost => role == 'host';

  factory CallParticipant.fromJson(Map<String, dynamic> j) => CallParticipant(
        callId: _s(j['call_id']),
        userId: _s(j['user_id']),
        role: _s(j['role'], 'member'),
        status: _s(j['status'], 'invited'),
        joinedAt: _d(j['joined_at']),
        leftAt: _d(j['left_at']),
        isMuted: _b(j['is_muted']),
        isCameraOn: j['is_camera_on'] != false,
        isDeafened: _b(j['is_deafened']),
        profile: j['profile'] is Map<String, dynamic>
            ? UserProfile.fromJson(j['profile'] as Map<String, dynamic>)
            : j['profiles'] is Map<String, dynamic>
                ? UserProfile.fromJson(j['profiles'] as Map<String, dynamic>)
                : null,
      );
}

class CallSignal {
  const CallSignal({
    required this.id,
    required this.callId,
    required this.senderId,
    required this.receiverId,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String callId;
  final String senderId;
  final String? receiverId;
  final String kind; // offer | answer | ice-candidate | join | leave | end | decline | cancel | busy | reconnect | media-update
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  bool get isOffer => kind == 'offer';
  bool get isAnswer => kind == 'answer';
  bool get isIce => kind == 'ice-candidate';

  factory CallSignal.fromJson(Map<String, dynamic> j) => CallSignal(
        id: _s(j['id']),
        callId: _s(j['call_id']),
        senderId: _s(j['sender_id']),
        receiverId: j['receiver_id'] as String?,
        kind: _s(j['kind']),
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: _d(j['created_at']),
      );
}

class CallIceCandidate {
  const CallIceCandidate({required this.candidate, required this.sdpMid, required this.sdpMLineIndex});

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  Map<String, dynamic> toJson() => {'candidate': candidate, 'sdpMid': sdpMid, 'sdpMLineIndex': sdpMLineIndex};

  factory CallIceCandidate.fromJson(Map<String, dynamic> j) => CallIceCandidate(
        candidate: _s(j['candidate']),
        sdpMid: j['sdpMid'] as String?,
        sdpMLineIndex: j['sdpMLineIndex'] as int? ?? _i(j['sdpMLineIndex']),
      );
}

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.call,
    required this.direction, // incoming | outgoing | missed
    required this.otherUser,
    this.participants,
  });

  final CallSession call;
  final String direction;
  final UserProfile? otherUser;
  final List<CallParticipant>? participants;

  bool get isMissed => call.isMissed || direction == 'missed';
  bool get isOutgoing => direction == 'outgoing';
  bool get isIncoming => direction == 'incoming';
  bool get isVideo => call.isVideo;
  bool get isGroup => call.isGroup;

  String titleFallback(String me) {
    if (isGroup) return call.isVideo ? 'Group video call' : 'Group voice call';
    return otherUser?.displayName.isNotEmpty == true ? otherUser!.displayName : (otherUser?.username ?? 'Unknown');
  }
}

class CallSettings {
  const CallSettings({
    required this.micMuted,
    required this.speakerOn,
    required this.cameraFront,
    required this.videoQuality,
    required this.noiseSuppression,
    required this.echoCancellation,
    required this.dataSaver,
    required this.incomingNotifications,
  });

  final bool micMuted;
  final bool speakerOn;
  final bool cameraFront;
  final String videoQuality; // auto | low | medium | high
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool dataSaver;
  final bool incomingNotifications;

  factory CallSettings.defaults() => const CallSettings(
        micMuted: false,
        speakerOn: false,
        cameraFront: true,
        videoQuality: 'auto',
        noiseSuppression: true,
        echoCancellation: true,
        dataSaver: false,
        incomingNotifications: true,
      );

  factory CallSettings.fromJson(Map<String, dynamic> j) => CallSettings(
        micMuted: _b(j['mic_muted']),
        speakerOn: _b(j['speaker_on']),
        cameraFront: j['camera_front'] != false,
        videoQuality: _s(j['video_quality'], 'auto'),
        noiseSuppression: j['noise_suppression'] != false,
        echoCancellation: j['echo_cancellation'] != false,
        dataSaver: _b(j['data_saver']),
        incomingNotifications: j['incoming_notifications'] != false,
      );

  Map<String, dynamic> toJson() => {
        'mic_muted': micMuted,
        'speaker_on': speakerOn,
        'camera_front': cameraFront,
        'video_quality': videoQuality,
        'noise_suppression': noiseSuppression,
        'echo_cancellation': echoCancellation,
        'data_saver': dataSaver,
        'incoming_notifications': incomingNotifications,
      };

  CallSettings copyWith({
    bool? micMuted,
    bool? speakerOn,
    bool? cameraFront,
    String? videoQuality,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? dataSaver,
    bool? incomingNotifications,
  }) =>
      CallSettings(
        micMuted: micMuted ?? this.micMuted,
        speakerOn: speakerOn ?? this.speakerOn,
        cameraFront: cameraFront ?? this.cameraFront,
        videoQuality: videoQuality ?? this.videoQuality,
        noiseSuppression: noiseSuppression ?? this.noiseSuppression,
        echoCancellation: echoCancellation ?? this.echoCancellation,
        dataSaver: dataSaver ?? this.dataSaver,
        incomingNotifications: incomingNotifications ?? this.incomingNotifications,
      );
}
