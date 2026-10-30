/// Messaging models — all fields match the actual Supabase schema.
/// See migrations 0006, 0009, 0010, 0011. Never invent column names.\n
import 'models.dart';

String _s(Object? v, [String f = '']) => v is String ? v : f;
bool _b(Object? v) => v == true;
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
DateTime? _dUtc(Object? v) => v is String ? DateTime.tryParse(v) : null;

// ---------------------------------------------------------------------------
// Conversation + members\n// ---------------------------------------------------------------------------

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.avatarUrl,
    required this.directKey,
    required this.createdBy,
    required this.lastMessageAt,
    required this.createdAt,
    required this.otherParticipant,
    required this.unreadCount,
    required this.lastMessagePreview,
    required this.lastMessageKind,
    required this.lastMessageSenderId,
    required this.isPinned,
    required this.isArchived,
    required this.isMuted,
    required this.role,
    required this.joinedAt,
    this.labelIds = const [],
  });

  final String id;
  final String kind; // direct | group | community
  final String? title;
  final String? avatarUrl;
  final String? directKey;
  final String? createdBy;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final UserProfile? otherParticipant; // for direct chats
  final int unreadCount;
  final String? lastMessagePreview;
  final String? lastMessageKind;
  final String? lastMessageSenderId;
  final bool isPinned;
  final bool isArchived;
  final bool isMuted;
  final String role;
  final DateTime? joinedAt;
  final List<String> labelIds;

  bool get isDirect => kind == 'direct';
  bool get isGroup => kind == 'group';

  String displayName(String fallback) {
    if (isDirect) {
      final p = otherParticipant;
      if (p != null) return p.displayName.isNotEmpty ? p.displayName : p.username;
    }
    if (title != null && title!.isNotEmpty) return title!;
    return fallback;
  }

  String get usernameOrId {
    if (isDirect) return otherParticipant?.username ?? id.substring(0, 8);
    return title ?? id.substring(0, 8);
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
        id: _s(j['id']),
        kind: _s(j['kind'], 'direct'),
        title: j['title'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        directKey: j['direct_key'] as String?,
        createdBy: j['created_by'] as String?,
        lastMessageAt: _d(j['last_message_at']),
        createdAt: _d(j['created_at']),
        otherParticipant: j['other_participant'] is Map<String, dynamic>
            ? UserProfile.fromJson(j['other_participant'] as Map<String, dynamic>)
            : null,
        unreadCount: _i(j['unread_count']),
        lastMessagePreview: j['last_message_preview'] as String?,
        lastMessageKind: j['last_message_kind'] as String?,
        lastMessageSenderId: j['last_message_sender_id'] as String?,
        isPinned: _b(j['pinned']),
        isArchived: _b(j['archived']),
        isMuted: _b(j['muted']),
        role: _s(j['role'], 'member'),
        joinedAt: _d(j['joined_at']),
        labelIds: (j['label_ids'] as List?)?.whereType<String>().toList() ?? const [],
      );

  ConversationSummary copyWith({
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    int? unreadCount,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) =>
      ConversationSummary(
        id: id,
        kind: kind,
        title: title,
        avatarUrl: avatarUrl,
        directKey: directKey,
        createdBy: createdBy,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        createdAt: createdAt,
        otherParticipant: otherParticipant,
        unreadCount: unreadCount ?? this.unreadCount,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        lastMessageKind: lastMessageKind,
        lastMessageSenderId: lastMessageSenderId,
        isPinned: isPinned ?? this.isPinned,
        isArchived: isArchived ?? this.isArchived,
        isMuted: isMuted ?? this.isMuted,
        role: role,
        joinedAt: joinedAt,
        labelIds: labelIds,
      );
}

class ConversationMember {
  const ConversationMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.leftAt,
    this.profile,
  });

  final String conversationId;
  final String userId;
  final String role;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final UserProfile? profile;

  bool get isActive => leftAt == null;

  factory ConversationMember.fromJson(Map<String, dynamic> j) => ConversationMember(
        conversationId: _s(j['conversation_id']),
        userId: _s(j['user_id']),
        role: _s(j['role'], 'member'),
        joinedAt: _d(j['joined_at']),
        leftAt: _d(j['left_at']),
        profile: j['profile'] is Map<String, dynamic>
            ? UserProfile.fromJson(j['profile'] as Map<String, dynamic>)
            : j['profiles'] is Map<String, dynamic>
                ? UserProfile.fromJson(j['profiles'] as Map<String, dynamic>)
                : null,
      );
}

// ---------------------------------------------------------------------------
// Messages, receipts, reactions, attachments\n// ---------------------------------------------------------------------------

/// Delivery lifecycle: sending (optimistic) -> sent -> delivered -> read -> failed\n
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

MessageStatus receiptToStatus(List<MessageReceipt> receipts, String currentUserId, String senderId) {
  // Sender sees receipts from recipients. Recipient's own message is always 'sent' for them.
  if (receipts.isEmpty) return MessageStatus.sent;
  final hasRead = receipts.any((r) => r.status == 'read');
  if (hasRead) return MessageStatus.read;
  final hasDelivered = receipts.any((r) => r.status == 'delivered');
  if (hasDelivered) return MessageStatus.delivered;
  return MessageStatus.sent;
}

class MessageModel {
  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.clientMessageId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.replyToId,
    this.forwardedFromId,
    this.editedAt,
    this.deletedAt,
    this.expiresAt,
    this.sender,
    this.replyTo,
    this.forwardedFrom,
    this.receipts = const [],
    this.reactions = const [],
    this.attachments = const [],
    this.isStarred = false,
    this.isPinned = false,
    this.isOptimistic = false,
    this.status = MessageStatus.sent,
  });

  final String id;
  final String conversationId;
  final String? senderId;
  final String clientMessageId;
  final String kind; // text | image | video | voice | document | location | contact | system
  final DateTime? createdAt;
  final String? body;
  final String? replyToId;
  final String? forwardedFromId;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? expiresAt;
  final UserProfile? sender;
  final MessageModel? replyTo;
  final MessageModel? forwardedFrom;
  final List<MessageReceipt> receipts;
  final List<MessageReaction> reactions;
  final List<MessageAttachment> attachments;
  final bool isStarred;
  final bool isPinned;
  final bool isOptimistic;
  final MessageStatus status;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isSystem => kind == 'system' || senderId == null;
  bool get isMedia => const {'image', 'video', 'voice', 'document'}.contains(kind);
  bool get hasAttachments => attachments.isNotEmpty;

  /// Effective display body: tombstone text for deleted, body otherwise.
  String get displayBody {
    if (isDeleted) return 'This message was deleted';
    return body ?? '';
  }

  bool isMine(String? currentUserId) => senderId != null && senderId == currentUserId;

  MessageModel copyWith({
    String? body,
    DateTime? editedAt,
    DateTime? deletedAt,
    List<MessageReceipt>? receipts,
    List<MessageReaction>? reactions,
    MessageStatus? status,
    bool? isStarred,
    bool? isPinned,
    bool? isOptimistic,
  }) =>
      MessageModel(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        clientMessageId: clientMessageId,
        kind: kind,
        createdAt: createdAt,
        body: body ?? this.body,
        replyToId: replyToId,
        forwardedFromId: forwardedFromId,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        expiresAt: expiresAt,
        sender: sender,
        replyTo: replyTo,
        forwardedFrom: forwardedFrom,
        receipts: receipts ?? this.receipts,
        reactions: reactions ?? this.reactions,
        attachments: attachments,
        isStarred: isStarred ?? this.isStarred,
        isPinned: isPinned ?? this.isPinned,
        isOptimistic: isOptimistic ?? this.isOptimistic,
        status: status ?? this.status,
      );

  factory MessageModel.fromJson(Map<String, dynamic> j) {
    // receipts may be nested array or absent
    final rawReceipts = j['message_receipts'] ?? j['receipts'];
    final rawReactions = j['message_reactions'] ?? j['reactions'];
    final rawAttachments = j['attachments'];
    return MessageModel(
      id: _s(j['id']),
      conversationId: _s(j['conversation_id']),
      senderId: j['sender_id'] as String?,
      clientMessageId: _s(j['client_message_id']),
      kind: _s(j['kind'], 'text'),
      createdAt: _d(j['created_at']),
      body: j['body'] as String?,
      replyToId: j['reply_to_id'] as String?,
      forwardedFromId: j['forwarded_from_id'] as String?,
      editedAt: _d(j['edited_at']),
      deletedAt: _d(j['deleted_at']),
      expiresAt: _d(j['expires_at']),
      sender: j['sender'] is Map<String, dynamic>
          ? UserProfile.fromJson(j['sender'] as Map<String, dynamic>)
          : j['profiles'] is Map<String, dynamic>
              ? UserProfile.fromJson(j['profiles'] as Map<String, dynamic>)
              : null,
      receipts: rawReceipts is List
          ? rawReceipts.whereType<Map<String, dynamic>>().map(MessageReceipt.fromJson).toList()
          : const [],
      reactions: rawReactions is List
          ? rawReactions.whereType<Map<String, dynamic>>().map(MessageReaction.fromJson).toList()
          : const [],
      attachments: rawAttachments is List
          ? rawAttachments.whereType<Map<String, dynamic>>().map(MessageAttachment.fromJson).toList()
          : const [],
      isStarred: _b(j['is_starred']),
      isPinned: _b(j['is_pinned']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'client_message_id': clientMessageId,
        'kind': kind,
        'body': body,
        'created_at': createdAt?.toIso8601String(),
        'reply_to_id': replyToId,
        'forwarded_from_id': forwardedFromId,
        'edited_at': editedAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}

class MessageReceipt {
  const MessageReceipt({
    required this.messageId,
    required this.userId,
    required this.status,
    required this.updatedAt,
  });

  final String messageId;
  final String userId;
  final String status; // delivered | read
  final DateTime? updatedAt;

  factory MessageReceipt.fromJson(Map<String, dynamic> j) => MessageReceipt(
        messageId: _s(j['message_id']),
        userId: _s(j['user_id']),
        status: _s(j['status'], 'delivered'),
        updatedAt: _d(j['updated_at']),
      );
}

class MessageReaction {
  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
    this.profile,
  });

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime? createdAt;
  final UserProfile? profile;

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        messageId: _s(j['message_id']),
        userId: _s(j['user_id']),
        emoji: _s(j['emoji']),
        createdAt: _d(j['created_at']),
        profile: j['profile'] is Map<String, dynamic>
            ? UserProfile.fromJson(j['profile'] as Map<String, dynamic>)
            : null,
      );
}

class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.conversationId,
    required this.uploaderId,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.messageId,
    this.width,
    this.height,
    this.durationMs,
  });

  final String id;
  final String conversationId;
  final String uploaderId;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime? createdAt;
  final String? messageId;
  final int? width;
  final int? height;
  final int? durationMs;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isPdf => mimeType == 'application/pdf';

  factory MessageAttachment.fromJson(Map<String, dynamic> j) => MessageAttachment(
        id: _s(j['id']),
        conversationId: _s(j['conversation_id']),
        uploaderId: _s(j['uploader_id']),
        storagePath: _s(j['storage_path']),
        mimeType: _s(j['mime_type']),
        sizeBytes: _i(j['size_bytes']),
        createdAt: _d(j['created_at']),
        messageId: j['message_id'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
        durationMs: j['duration_ms'] as int?,
      );
}

// ---------------------------------------------------------------------------
// Typing, presence, search\n// ---------------------------------------------------------------------------

class TypingIndicator {
  const TypingIndicator({
    required this.conversationId,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String conversationId;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory TypingIndicator.fromJson(Map<String, dynamic> j) => TypingIndicator(
        conversationId: _s(j['conversation_id']),
        userId: _s(j['user_id']),
        username: _s(j['username']),
        displayName: _s(j['display_name']),
        avatarUrl: j['avatar_url'] as String?,
      );
}

class PresenceState {
  const PresenceState({
    required this.userId,
    required this.isOnline,
    this.lastSeenAt,
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastSeenAt;

  bool get isRecentlyOnline =>
      isOnline || (lastSeenAt != null && DateTime.now().difference(lastSeenAt!).inMinutes < 5);

  factory PresenceState.fromJson(Map<String, dynamic> j) {
    final ls = _d(j['last_seen_at']);
    final online = ls != null && DateTime.now().difference(ls).inMinutes < 5;
    return PresenceState(userId: _s(j['id'] ?? j['user_id']), isOnline: online, lastSeenAt: ls);
  }
}

class SearchResult {
  const SearchResult({
    required this.users,
    required this.conversations,
    required this.messages,
    required this.channels,
  });

  final List<UserProfile> users;
  final List<ConversationSummary> conversations;
  final List<MessageModel> messages;
  final List<ChannelModel> channels;

  bool get isEmpty => users.isEmpty && conversations.isEmpty && messages.isEmpty && channels.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

class QueuedMessage {
  const QueuedMessage({
    required this.localId,
    required this.conversationId,
    required this.clientMessageId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.replyToId,
    this.forwardedFromId,
    this.attachmentPath,
    this.attachmentMime,
    this.attachmentSize,
    this.retryCount = 0,
    this.lastError,
  });

  final String localId;
  final String conversationId;
  final String clientMessageId;
  final String kind;
  final String? body;
  final DateTime createdAt;
  final String? replyToId;
  final String? forwardedFromId;
  final String? attachmentPath;
  final String? attachmentMime;
  final int? attachmentSize;
  final int retryCount;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'conversationId': conversationId,
        'clientMessageId': clientMessageId,
        'kind': kind,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'replyToId': replyToId,
        'forwardedFromId': forwardedFromId,
        'attachmentPath': attachmentPath,
        'attachmentMime': attachmentMime,
        'attachmentSize': attachmentSize,
        'retryCount': retryCount,
        'lastError': lastError,
      };

  factory QueuedMessage.fromJson(Map<String, dynamic> j) => QueuedMessage(
        localId: _s(j['localId']),
        conversationId: _s(j['conversationId']),
        clientMessageId: _s(j['clientMessageId']),
        kind: _s(j['kind'], 'text'),
        body: j['body'] as String?,
        createdAt: _dUtc(j['createdAt'])?.toLocal() ?? DateTime.now(),
        replyToId: j['replyToId'] as String?,
        forwardedFromId: j['forwardedFromId'] as String?,
        attachmentPath: j['attachmentPath'] as String?,
        attachmentMime: j['attachmentMime'] as String?,
        attachmentSize: j['attachmentSize'] as int?,
        retryCount: _i(j['retryCount']),
        lastError: j['lastError'] as String?,
      );

  QueuedMessage copyWith({int? retryCount, String? lastError}) => QueuedMessage(
        localId: localId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        kind: kind,
        body: body,
        createdAt: createdAt,
        replyToId: replyToId,
        forwardedFromId: forwardedFromId,
        attachmentPath: attachmentPath,
        attachmentMime: attachmentMime,
        attachmentSize: attachmentSize,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
      );
}

class BusinessLabel {
  const BusinessLabel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String name;
  final String color;
  final DateTime? createdAt;

  factory BusinessLabel.fromJson(Map<String, dynamic> j) => BusinessLabel(
        id: _s(j['id']),
        businessId: _s(j['business_id']),
        name: _s(j['name']),
        color: _s(j['color'], '#2563EB'),
        createdAt: _d(j['created_at']),
      );
}

class ScheduledMessageModel {
  const ScheduledMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.sendAt,
    required this.status,
    this.sentMessageId,
    this.error,
    this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime? sendAt;
  final String status;
  final String? sentMessageId;
  final String? error;
  final DateTime? createdAt;

  factory ScheduledMessageModel.fromJson(Map<String, dynamic> j) => ScheduledMessageModel(
        id: _s(j['id']),
        conversationId: _s(j['conversation_id']),
        senderId: _s(j['sender_id']),
        body: _s(j['body']),
        sendAt: _d(j['send_at']),
        status: _s(j['status'], 'pending'),
        sentMessageId: j['sent_message_id'] as String?,
        error: j['error'] as String?,
        createdAt: _d(j['created_at']),
      );
}
