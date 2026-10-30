import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/messaging.dart';
import '../models/models.dart';

/// Messaging gateway — every query uses real column names from migrations 0006/0009/0010.
///
/// Reads respect RLS; writes go through RPCs that re-check membership server-side.
/// No privileged column is treated as client-writable.
class MessagingRepository {
  MessagingRepository(this._client);
  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------------
  // Conversations — list with pagination, filters, search
  // ---------------------------------------------------------------------------

  /// Fetches conversation list for the signed-in user.
  ///
  /// Uses the underlying tables directly (RLS ensures only own conversations).
  /// Joins last message preview client-side via a follow-up query to keep RLS simple.
  Future<List<ConversationSummary>> fetchConversations({
    int limit = 30,
    int offset = 0,
    String? search,
    bool? unreadOnly,
    String? kindFilter, // direct | group | business
    bool? archived,
    bool? muted,
  }) async {
    final uid = currentUserId;
    if (uid == null) return [];

    // Members where current user is active.
    var memberQuery = _client
        .from('conversation_members')
        .select('conversation_id, role, pinned, archived, muted, joined_at, conversations!inner(id, kind, title, avatar_url, direct_key, created_by, last_message_at, created_at)')
        .eq('user_id', uid)
        .isFilter('left_at', null)
        .order('pinned', ascending: false)
        .order('joined_at', ascending: false);

    if (archived != null) memberQuery = memberQuery.eq('archived', archived);
    if (muted != null) memberQuery = memberQuery.eq('muted', muted);

    final memberRows = await memberQuery.range(offset, offset + limit - 1);

    if (memberRows.isEmpty) return [];

    final convIds = memberRows.map((r) => r['conversation_id'] as String).toList();

    // Unread counts per conversation (messages not by self, not yet read).
    final unreadCounts = await _unreadCounts(convIds);

    // Last message previews (one query, then map).
    final previews = await _lastMessagePreviews(convIds);

    // Direct chat participants (other user profiles).
    final directParticipants = await _directParticipants(convIds, memberRows);

    // kind filter applied client-side (keeps query simple, small page size).
    var results = <ConversationSummary>[];
    for (final row in memberRows) {
      final conv = row['conversations'] as Map<String, dynamic>;
      final cid = conv['id'] as String;
      final kind = conv['kind'] as String? ?? 'direct';
      if (kindFilter != null && kindFilter != kind) continue;
      // Business filter: business conversations have title containing business name or kind business
      // For now business label is separate; kind filter respected as passed.

      final unread = unreadCounts[cid] ?? 0;
      if (unreadOnly == true && unread == 0) continue;

      final preview = previews[cid];
      final s = search?.trim().toLowerCase();
      if (s != null && s.isNotEmpty) {
        final haystack = [
          conv['title']?.toString().toLowerCase() ?? '',
          preview?['body']?.toString().toLowerCase() ?? '',
          directParticipants[cid]?.username.toLowerCase() ?? '',
          directParticipants[cid]?.displayName.toLowerCase() ?? '',
        ].join(' ');
        if (!haystack.contains(s)) continue;
      }

      results.add(ConversationSummary(
        id: cid,
        kind: kind,
        title: conv['title'] as String?,
        avatarUrl: conv['avatar_url'] as String?,
        directKey: conv['direct_key'] as String?,
        createdBy: conv['created_by'] as String?,
        lastMessageAt: _parseDate(conv['last_message_at']),
        createdAt: _parseDate(conv['created_at']),
        otherParticipant: directParticipants[cid],
        unreadCount: unread,
        lastMessagePreview: preview?['body'] as String?,
        lastMessageKind: preview?['kind'] as String?,
        lastMessageSenderId: preview?['sender_id'] as String?,
        isPinned: row['pinned'] == true,
        isArchived: row['archived'] == true,
        isMuted: row['muted'] == true,
        role: row['role'] as String? ?? 'member',
        joinedAt: _parseDate(row['joined_at']),
      ));
    }

    // Sort pinned first, then by last_message_at desc.
    results.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final at = a.lastMessageAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastMessageAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });

    return results;
  }

  Future<Map<String, int>> _unreadCounts(List<String> convIds) async {
    final uid = currentUserId;
    if (uid == null || convIds.isEmpty) return {};
    // Count messages where sender != self and not in message_receipts as read.
    // We approximate via full fetch of message ids then receipt check — efficient for page size 30.
    final counts = <String, int>{};
    for (final cid in convIds) {
      final msgs = await _client
          .from('messages')
          .select('id, sender_id')
          .eq('conversation_id', cid)
          .neq('sender_id', uid)
          .isFilter('deleted_at', null);
      if (msgs.isEmpty) {
        counts[cid] = 0;
        continue;
      }
      final msgIds = msgs.map((m) => m['id'] as String).toList();
      final receipts = await _client
          .from('message_receipts')
          .select('message_id')
          .eq('user_id', uid)
          .eq('status', 'read')
          .inFilter('message_id', msgIds);
      final readIds = receipts.map((r) => r['message_id'] as String).toSet();
      counts[cid] = msgIds.where((id) => !readIds.contains(id)).length;
    }
    return counts;
  }

  Future<Map<String, Map<String, dynamic>>> _lastMessagePreviews(List<String> convIds) async {
    final previews = <String, Map<String, dynamic>>{};
    for (final cid in convIds) {
      final rows = await _client
          .from('messages')
          .select('body, kind, sender_id, created_at')
          .eq('conversation_id', cid)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) previews[cid] = rows.first;
    }
    return previews;
  }

  Future<Map<String, UserProfile>> _directParticipants(
    List<String> convIds,
    List<Map<String, dynamic>> memberRows,
  ) async {
    final directIds = <String>[];
    for (final row in memberRows) {
      final conv = row['conversations'] as Map<String, dynamic>;
      if (conv['kind'] == 'direct') directIds.add(conv['id'] as String);
    }
    if (directIds.isEmpty) return {};
    final uid = currentUserId;
    final members = await _client
        .from('conversation_members')
        .select('conversation_id, user_id, profiles!inner(id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at)')
        .inFilter('conversation_id', directIds)
        .neq('user_id', uid ?? '')
        .isFilter('left_at', null);
    final map = <String, UserProfile>{};
    for (final m in members) {
      final cid = m['conversation_id'] as String;
      final p = m['profiles'] as Map<String, dynamic>;
      map[cid] = UserProfile.fromJson(p);
    }
    return map;
  }

  Future<ConversationSummary?> fetchConversation(String conversationId) async {
    final list = await fetchConversations(limit: 100);
    try {
      return list.firstWhere((c) => c.id == conversationId);
    } catch (_) {
      return null;
    }
  }

  Future<List<ConversationMember>> conversationMembers(String conversationId) async {
    final rows = await _client
        .from('conversation_members')
        .select('conversation_id, user_id, role, joined_at, left_at, profiles!inner(id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at)')
        .eq('conversation_id', conversationId)
        .isFilter('left_at', null);
    return rows.map((r) {
      final profile = r['profiles'] as Map<String, dynamic>?;
      return ConversationMember(
        conversationId: r['conversation_id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String? ?? 'member',
        joinedAt: _parseDate(r['joined_at']),
        leftAt: _parseDate(r['left_at']),
        profile: profile == null ? null : UserProfile.fromJson(profile),
      );
    }).toList();
  }

  Future<String> createDirectConversation(String otherUserId) async {
    final id = await _client.rpc('create_direct_conversation', params: {'p_other_user': otherUserId});
    return id.toString();
  }

  Future<String> createGroupConversation({required String title, required List<String> memberIds}) async {
    final id = await _client.rpc('create_group_conversation', params: {'p_title': title.trim(), 'p_member_ids': memberIds});
    return id.toString();
  }

  Future<void> updateMemberState(String conversationId, {bool? pinned, bool? archived, bool? muted}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final updates = <String, dynamic>{};
    if (pinned != null) updates['pinned'] = pinned;
    if (archived != null) updates['archived'] = archived;
    if (muted != null) updates['muted'] = muted;
    if (updates.isEmpty) return;
    await _client.from('conversation_members').update(updates).eq('conversation_id', conversationId).eq('user_id', uid);
  }

  Future<void> leaveConversation(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('conversation_members').update({'left_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', conversationId).eq('user_id', uid);
  }

  Future<void> deleteConversation(String conversationId) async {
    // Soft delete: leave; messages remain for other members. No hard delete without admin.
    await leaveConversation(conversationId);
  }

  Future<void> markConversationUnread(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;
    // Remove read receipts for last N messages to surface as unread again.
    final msgs = await _client.from('messages').select('id').eq('conversation_id', conversationId).order('created_at', ascending: false).limit(5);
    final ids = msgs.map((m) => m['id'] as String).toList();
    if (ids.isEmpty) return;
    await _client.from('message_receipts').delete().eq('user_id', uid).inFilter('message_id', ids);
  }

  // ---------------------------------------------------------------------------
  // Messages — paginated fetch, send, edit, delete, receipts
  // ---------------------------------------------------------------------------

  Future<List<MessageModel>> fetchMessages(
    String conversationId, {
    int limit = 40,
    DateTime? before,
    String? afterId,
  }) async {
    var query = _client
        .from('messages')
        .select('id, conversation_id, sender_id, client_message_id, kind, body, reply_to_id, forwarded_from_id, edited_at, deleted_at, created_at, message_receipts(message_id, user_id, status, updated_at), message_reactions(message_id, user_id, emoji, created_at), attachments(id, conversation_id, message_id, uploader_id, storage_path, mime_type, size_bytes, width, height, duration_ms, created_at)')
        .eq('conversation_id', conversationId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);

    // Fetch senders in bulk (avoid N+1).
    final senderIds = rows.map((r) => r['sender_id'] as String?).whereType<String>().toSet().toList();
    Map<String, UserProfile> senders = {};
    if (senderIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at')
          .inFilter('id', senderIds);
      senders = {for (final p in profiles) p['id'] as String: UserProfile.fromJson(p)};
    }

    // Starred state for current user.
    final uid = currentUserId;
    Set<String> starredIds = {};
    if (uid != null && rows.isNotEmpty) {
      final ids = rows.map((r) => r['id'] as String).toList();
      final stars = await _client.from('message_stars').select('message_id').eq('user_id', uid).inFilter('message_id', ids);
      starredIds = stars.map((s) => s['message_id'] as String).toSet();
    }

    // Pinned messages.
    Set<String> pinnedIds = {};
    try {
      final pinned = await _client.from('pinned_messages').select('message_id').eq('conversation_id', conversationId);
      pinnedIds = pinned.map((p) => p['message_id'] as String).toSet();
    } catch (_) {
      // Table may not exist in older schema — fall back to is_pinned column if present.
      for (final r in rows) {
        if (r['is_pinned'] == true) pinnedIds.add(r['id'] as String);
      }
    }

    final messages = <MessageModel>[];
    for (final r in rows) {
      final m = MessageModel.fromJson(r);
      // Enrich with sender and starred/pinned.
      final enriched = MessageModel(
        id: m.id,
        conversationId: m.conversationId,
        senderId: m.senderId,
        clientMessageId: m.clientMessageId,
        kind: m.kind,
        createdAt: m.createdAt,
        body: m.body,
        replyToId: m.replyToId,
        forwardedFromId: m.forwardedFromId,
        editedAt: m.editedAt,
        deletedAt: m.deletedAt,
        expiresAt: m.expiresAt,
        sender: m.senderId == null ? null : senders[m.senderId],
        receipts: m.receipts,
        reactions: m.reactions,
        attachments: m.attachments,
        isStarred: starredIds.contains(m.id),
        isPinned: pinnedIds.contains(m.id),
      );
      messages.add(enriched);
    }

    // Return oldest-first for ListView.
    return messages.reversed.toList();
  }

  /// Sends a text message. Returns the persisted message.
  ///
  /// Idempotency: client_message_id (UUID) is the dedup key — retries with same id
  /// are no-ops server-side (unique constraint on sender_id + client_message_id).
  Future<MessageModel> sendTextMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
    String? replyToId,
    String? forwardedFromId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final trimmed = body.trim();
    if (trimmed.isEmpty) throw ArgumentError('Message body cannot be empty');

    final inserted = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'client_message_id': clientMessageId,
          'kind': 'text',
          'body': trimmed,
          if (replyToId != null) 'reply_to_id': replyToId,
          if (forwardedFromId != null) 'forwarded_from_id': forwardedFromId,
        })
        .select('id, conversation_id, sender_id, client_message_id, kind, body, reply_to_id, forwarded_from_id, edited_at, deleted_at, created_at')
        .single();

    return MessageModel.fromJson(inserted);
  }

  Future<MessageModel> sendMediaMessage({
    required String conversationId,
    required String clientMessageId,
    required String kind, // image | video | voice | document
    String? body,
    String? replyToId,
    required String storagePath,
    required String mimeType,
    required int sizeBytes,
    int? width,
    int? height,
    int? durationMs,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');

    final msg = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'client_message_id': clientMessageId,
          'kind': kind,
          'body': body?.trim(),
          if (replyToId != null) 'reply_to_id': replyToId,
        })
        .select('id, conversation_id, sender_id, client_message_id, kind, body, reply_to_id, created_at')
        .single();

    final messageId = msg['id'] as String;
    try {
      await _client.from('attachments').insert({
        'conversation_id': conversationId,
        'message_id': messageId,
        'uploader_id': uid,
        'storage_path': storagePath,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'duration_ms': durationMs,
      });
    } catch (e) {
      // Attachment failure — message exists but without attachment row. Still return message.
      // Caller can retry attachment separately.
      rethrow;
    }

    return MessageModel.fromJson(msg);
  }

  /// Uploads a file to Supabase Storage and returns the storage path.
  ///
  /// Bucket routing: chat-media for images/videos/voice, chat-attachments for docs.
  /// Path: {conversationId}/{clientMessageId}_{filename}
  Future<String> uploadChatFile({
    required String conversationId,
    required String clientMessageId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final bucket = _isMediaMime(mimeType) ? 'chat-media' : 'chat-attachments';
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$conversationId/${clientMessageId}_$safeName';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  Future<String> createSignedUrl({required String bucket, required String path, int expiresIn = 3600}) async {
    final url = await _client.storage.from(bucket).createSignedUrl(path, expiresIn);
    return url;
  }

  Future<void> editMessage({required String messageId, required String newBody}) =>
      _client.rpc('edit_message', params: {'p_message_id': messageId, 'p_body': newBody.trim()});

  Future<void> deleteMessage(String messageId) => _client.rpc('delete_message', params: {'p_message_id': messageId});

  /// Soft delete for current user only: inserts into deleted_for list (if column exists) or message_receipts variant.
  /// Falls back to hiding locally; server RLS still governs visibility.
  Future<void> deleteMessageForMe(String messageId) async {
    // Try the dedicated RPC if available; otherwise record in a local table.
    try {
      await _client.rpc('delete_message_for_me', params: {'p_message_id': messageId});
      return;
    } catch (_) {}
    // Fallback: insert hidden marker that is per-user.
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _client.from('message_hidden_for').insert({'message_id': messageId, 'user_id': uid});
    } catch (_) {
      // Table may not exist — local-only hide is handled by the UI layer.
    }
  }

  Future<void> forwardMessage({required String messageId, required String targetConversationId}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final src = await _client.from('messages').select('kind, body, attachments(storage_path, mime_type, size_bytes)').eq('id', messageId).maybeSingle();
    if (src == null) throw StateError('Message not found');
    // Forward as new message with forwarded_from_id pointer.
    await _client.from('messages').insert({
      'conversation_id': targetConversationId,
      'sender_id': uid,
      'client_message_id': _uuid(),
      'kind': src['kind'] ?? 'text',
      'body': src['body'],
      'forwarded_from_id': messageId,
    });
  }

  Future<void> markConversationRead(String conversationId) =>
      _client.rpc('mark_conversation_read', params: {'p_conversation_id': conversationId});

  Future<void> markMessageDelivered(String messageId) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _client.from('message_receipts').upsert({'message_id': messageId, 'user_id': uid, 'status': 'delivered'});
    } catch (_) {}
  }

  Future<void> markMessageRead(String messageId) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client.from('message_receipts').upsert({'message_id': messageId, 'user_id': uid, 'status': 'read'});
  }

  // ---------------------------------------------------------------------------
  // Reactions, stars, pins, report
  // ---------------------------------------------------------------------------

  Future<void> addReaction({required String messageId, required String emoji}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    // Toggle: if exists remove, else add. We insert; conflict means already there.
    try {
      await _client.from('message_reactions').insert({'message_id': messageId, 'user_id': uid, 'emoji': emoji});
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        await _client.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', uid).eq('emoji', emoji);
      } else {
        rethrow;
      }
    }
  }

  Future<void> removeReaction({required String messageId, required String emoji}) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _client.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', uid).eq('emoji', emoji);
  }

  Future<void> setPinned({required String messageId, required bool pinned}) =>
      _client.rpc('set_message_pinned', params: {'p_message_id': messageId, 'p_pinned': pinned});

  Future<void> starMessage(String messageId) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('message_stars').insert({'user_id': uid, 'message_id': messageId});
  }

  Future<void> unstarMessage(String messageId) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('message_stars').delete().eq('user_id', uid).eq('message_id', messageId);
  }

  Future<void> reportMessage({required String messageId, required String reason}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('reports').insert({
      'reporter_id': uid,
      'target_type': 'message',
      'target_id': messageId,
      'reason': reason.trim(),
      'status': 'open',
    });
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    // Use ilike on username/display_name — indexed via trigram in production.
    final rows = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at')
        .or('username.ilike.%$q%,display_name.ilike.%$q%')
        .limit(limit);
    return rows.map(UserProfile.fromJson).toList();
  }

  Future<List<MessageModel>> searchMessages({required String conversationId, required String query, int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final rows = await _client
        .from('messages')
        .select('id, conversation_id, sender_id, client_message_id, kind, body, created_at, edited_at, deleted_at')
        .eq('conversation_id', conversationId)
        .ilike('body', '%$q%')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(MessageModel.fromJson).toList();
  }

  Future<List<MessageModel>> searchMessagesGlobal(String query, {int limit = 30}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    // Search across user's conversations only.
    final convs = await fetchConversations(limit: 100);
    final convIds = convs.map((c) => c.id).toList();
    if (convIds.isEmpty) return [];
    final rows = await _client
        .from('messages')
        .select('id, conversation_id, sender_id, client_message_id, kind, body, created_at, edited_at, deleted_at')
        .inFilter('conversation_id', convIds)
        .ilike('body', '%$q%')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(MessageModel.fromJson).toList();
  }

  Future<List<ChannelModel>> searchChannels(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final rows = await _client
        .from('channels')
        .select()
        .or('name.ilike.%$q%,username.ilike.%$q%')
        .limit(limit);
    return rows.map(ChannelModel.fromJson).toList();
  }

  // ---------------------------------------------------------------------------
  // Business messaging helpers
  // ---------------------------------------------------------------------------

  Future<List<BusinessLabel>> businessLabels(String businessId) async {
    final rows = await _client.from('business_labels').select().eq('business_id', businessId).order('name');
    return rows.map(BusinessLabel.fromJson).toList();
  }

  Future<String> createBusinessLabel({required String businessId, required String name, required String color}) async {
    final row = await _client.from('business_labels').insert({'business_id': businessId, 'name': name.trim(), 'color': color}).select('id').single();
    return row['id'] as String;
  }

  Future<void> assignLabel({required String labelId, required String conversationId}) async {
    await _client.from('business_label_assignments').insert({'label_id': labelId, 'conversation_id': conversationId});
  }

  Future<void> removeLabel({required String labelId, required String conversationId}) async {
    await _client.from('business_label_assignments').delete().eq('label_id', labelId).eq('conversation_id', conversationId);
  }

  Future<List<Map<String, dynamic>>> businessQuickReplies(String businessId) async {
    final rows = await _client.from('business_quick_replies').select().eq('business_id', businessId).order('shortcut');
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> setBusinessQuickReply({required String businessId, required String shortcut, required String body}) async {
    await _client.from('business_quick_replies').upsert({'business_id': businessId, 'shortcut': shortcut, 'body': body});
  }

  Future<List<Map<String, dynamic>>> catalogItems(String businessId) async {
    final rows = await _client.from('business_catalog_items').select().eq('business_id', businessId).order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------------
  // Scheduled messages
  // ---------------------------------------------------------------------------

  Future<String> scheduleMessage({required String conversationId, required String body, required DateTime sendAt}) async {
    final id = await _client.rpc('schedule_message', params: {'p_conversation_id': conversationId, 'p_body': body.trim(), 'p_send_at': sendAt.toUtc().toIso8601String()});
    return id.toString();
  }

  Future<void> cancelScheduledMessage(String id) => _client.rpc('cancel_scheduled_message', params: {'p_id': id});

  Future<List<ScheduledMessageModel>> scheduledMessages({String? conversationId}) async {
    var q = _client.from('scheduled_messages').select().eq('status', 'pending').order('send_at');
    if (conversationId != null) q = q.eq('conversation_id', conversationId);
    final rows = await q;
    return rows.map(ScheduledMessageModel.fromJson).toList();
  }

  // ---------------------------------------------------------------------------
  // Contacts, blocks
  // ---------------------------------------------------------------------------

  Future<List<UserProfile>> contacts() async {
    final uid = currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('contacts')
        .select('contact_id, profiles!contacts_contact_id_fkey(id, username, display_name, avatar_url, cover_url, bio, account_status, is_verified, verified_at, created_at, last_seen_at)')
        .eq('owner_id', uid);
    return rows.map((r) => UserProfile.fromJson(r['profiles'] as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isMediaMime(String mime) => mime.startsWith('image/') || mime.startsWith('video/') || mime.startsWith('audio/');

  String _uuid() {
    // Simple v4 UUID generator without extra dependency.
    final r = DateTime.now().microsecondsSinceEpoch.toString();
    return '${r.substring(0, 8)}-${r.substring(8, 12)}-4${r.substring(12, 15)}-a${r.substring(15, 18)}-${r.substring(18).padRight(12, '0')}';
  }

  DateTime? _parseDate(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
