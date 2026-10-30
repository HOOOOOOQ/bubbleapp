import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/connectivity_service.dart';
import '../core/offline_queue.dart';
import '../core/realtime_service.dart';
import '../data/messaging_repository.dart';
import '../models/messaging.dart';
import 'providers.dart';

// ---------------------------------------------------------------------------
// Repository + services\n// ---------------------------------------------------------------------------

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MessagingRepository(client);
});

final connectivityProvider = Provider<ConnectivityService>((ref) {
  final svc = ConnectivityService.instance;
  svc.start();
  ref.onDispose(svc.stop);
  return svc;
});

final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  final q = OfflineQueue();
  // Fire and forget load.
  q.load();
  ref.onDispose(q.dispose);
  return q;
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final svc = RealtimeService(client);
  final session = ref.watch(sessionProvider);
  if (session != null) svc.subscribe();
  // Resubscribe on auth change.
  ref.listen(sessionProvider, (prev, next) {
    if (next != null && prev == null) svc.subscribe();
    if (next == null && prev != null) svc.unsubscribe();
  });
  ref.onDispose(svc.dispose);
  return svc;
});

// ---------------------------------------------------------------------------
// Chat list state\n// ---------------------------------------------------------------------------

class ChatListFilter {
  const ChatListFilter({
    this.search = '',
    this.unreadOnly = false,
    this.kind, // direct | group | null = all
    this.archived = false,
    this.folder, // label id or null
  });

  final String search;
  final bool unreadOnly;
  final String? kind;
  final bool archived;
  final String? folder;

  ChatListFilter copyWith({
    String? search,
    bool? unreadOnly,
    String? kind,
    bool? archived,
    String? folder,
  }) =>
      ChatListFilter(
        search: search ?? this.search,
        unreadOnly: unreadOnly ?? this.unreadOnly,
        kind: kind ?? this.kind,
        archived: archived ?? this.archived,
        folder: folder ?? this.folder,
      );
}

class ChatListState {
  const ChatListState({
    required this.conversations,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.filter,
    this.error,
  });

  final List<ConversationSummary> conversations;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final ChatListFilter filter;
  final Object? error;

  List<ConversationSummary> get pinned => conversations.where((c) => c.isPinned).toList();
  List<ConversationSummary> get regular => conversations.where((c) => !c.isPinned).toList();
  int get totalUnread => conversations.fold(0, (s, c) => s + c.unreadCount);

  ChatListState copyWith({
    List<ConversationSummary>? conversations,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    ChatListFilter? filter,
    Object? error,
  }) =>
      ChatListState(
        conversations: conversations ?? this.conversations,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        filter: filter ?? this.filter,
        error: error,
      );
}

class ChatListNotifier extends StateNotifier<ChatListState> {
  ChatListNotifier(this._repo, this._realtime) : super(const ChatListState(conversations: [], isLoading: true, isLoadingMore: false, hasMore: true, filter: ChatListFilter())) {
    _listenRealtime();
    refresh();
  }

  final MessagingRepository _repo;
  final RealtimeService _realtime;
  StreamSubscription? _sub;
  int _offset = 0;
  static const _pageSize = 30;

  void _listenRealtime() {
    _sub = _realtime.onMessage.listen((msg) {
      // Refresh conversation preview when a new message arrives.
      refresh();
    });
    _realtime.onConversation.listen((_) => refresh());
    _realtime.onReceipt.listen((_) => refresh());
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    _offset = 0;
    try {
      final list = await _repo.fetchConversations(
        limit: _pageSize,
        offset: 0,
        search: state.filter.search.isEmpty ? null : state.filter.search,
        unreadOnly: state.filter.unreadOnly ? true : null,
        kindFilter: state.filter.kind,
        archived: state.filter.archived ? true : null,
      );
      _offset = list.length;
      state = state.copyWith(conversations: list, isLoading: false, hasMore: list.length >= _pageSize);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final more = await _repo.fetchConversations(
        limit: _pageSize,
        offset: _offset,
        search: state.filter.search.isEmpty ? null : state.filter.search,
        unreadOnly: state.filter.unreadOnly ? true : null,
        kindFilter: state.filter.kind,
        archived: state.filter.archived ? true : null,
      );
      _offset += more.length;
      // Deduplicate by id.
      final ids = state.conversations.map((c) => c.id).toSet();
      final dedup = more.where((c) => !ids.contains(c.id)).toList();
      state = state.copyWith(conversations: [...state.conversations, ...dedup], isLoadingMore: false, hasMore: more.length >= _pageSize);
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void setFilter(ChatListFilter filter) {
    state = state.copyWith(filter: filter);
    refresh();
  }

  void updateConversationLocal(String id, ConversationSummary Function(ConversationSummary) update) {
    final list = state.conversations.map((c) => c.id == id ? update(c) : c).toList();
    state = state.copyWith(conversations: list);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final chatListProvider = StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final repo = ref.watch(messagingRepositoryProvider);
  final rt = ref.watch(realtimeServiceProvider);
  return ChatListNotifier(repo, rt);
});

// ---------------------------------------------------------------------------
// Conversation messages state\n// ---------------------------------------------------------------------------

class ConversationState {
  const ConversationState({
    required this.messages,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.isSending,
    required this.typingUsers,
    required this.queuedMessages,
    this.conversation,
    this.error,
  });

  final ConversationSummary? conversation;
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSending;
  final List<TypingIndicator> typingUsers;
  final List<QueuedMessage> queuedMessages;
  final Object? error;

  /// Messages + optimistic queued messages interleaved, sorted by time.
  List<MessageModel> get displayedMessages {
    // Queued messages are shown as optimistic at the bottom.
    return messages;
  }

  ConversationState copyWith({
    ConversationSummary? conversation,
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSending,
    List<TypingIndicator>? typingUsers,
    List<QueuedMessage>? queuedMessages,
    Object? error,
  }) =>
      ConversationState(
        conversation: conversation ?? this.conversation,
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        isSending: isSending ?? this.isSending,
        typingUsers: typingUsers ?? this.typingUsers,
        queuedMessages: queuedMessages ?? this.queuedMessages,
        error: error,
      );
}

class ConversationNotifier extends StateNotifier<ConversationState> {
  ConversationNotifier({
    required this.conversationId,
    required MessagingRepository repo,
    required RealtimeService realtime,
    required OfflineQueue queue,
    required String? currentUserId,
  })  : _repo = repo,
        _realtime = realtime,
        _queue = queue,
        _currentUserId = currentUserId,
        super(const ConversationState(messages: [], isLoading: true, isLoadingMore: false, hasMore: true, isSending: false, typingUsers: [], queuedMessages: [])) {
    _init();
  }

  final String conversationId;
  final MessagingRepository _repo;
  final RealtimeService _realtime;
  final OfflineQueue _queue;
  final String? _currentUserId;

  StreamSubscription? _msgSub;
  StreamSubscription? _updateSub;
  StreamSubscription? _deleteSub;
  StreamSubscription? _receiptSub;
  StreamSubscription? _reactionSub;
  StreamSubscription? _queueSub;
  Timer? _typingTimer;
  final _seenIds = <String>{};

  static const _pageSize = 40;

  Future<void> _init() async {
    await _queue.load();
    // Observe queue changes for this conversation.
    _queueSub = _queue.stream.listen((items) {
      final forConv = items.where((e) => e.conversationId == conversationId).toList();
      state = state.copyWith(queuedMessages: forConv);
    });
    state = state.copyWith(queuedMessages: _queue.forConversation(conversationId));

    _msgSub = _realtime.onMessage.listen(_onNewMessage);
    _updateSub = _realtime.onMessageUpdate.listen(_onMessageUpdate);
    _deleteSub = _realtime.onMessageDelete.listen(_onMessageDelete);
    _receiptSub = _realtime.onReceipt.listen(_onReceipt);
    _reactionSub = _realtime.onReaction.listen(_onReaction);

    await refresh();
    // Mark delivered for messages not by self (proof of receipt, not just insert).
    await _markDeliveredForVisible();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final conv = await _repo.fetchConversation(conversationId);
      final msgs = await _repo.fetchMessages(conversationId, limit: _pageSize);
      for (final m in msgs) {
        _seenIds.add(m.id);
      }
      state = state.copyWith(conversation: conv, messages: msgs, isLoading: false, hasMore: msgs.length >= _pageSize);
      // Auto-mark read after initial load.
      unawaited(_markRead());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final oldest = state.messages.first.createdAt;
      final more = await _repo.fetchMessages(conversationId, limit: _pageSize, before: oldest);
      final dedup = more.where((m) => !_seenIds.contains(m.id)).toList();
      for (final m in dedup) {
        _seenIds.add(m.id);
      }
      state = state.copyWith(messages: [...dedup, ...state.messages], isLoadingMore: false, hasMore: more.length >= _pageSize);
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  // --- Sending with optimistic update + offline queue fallback ---

  Future<void> sendText({required String body, String? replyToId}) async {
    final text = body.trim();
    if (text.isEmpty) return;
    final clientId = _newUuid();
    final now = DateTime.now();

    // Optimistic message shown immediately.
    final optimistic = MessageModel(
      id: 'optimistic_$clientId',
      conversationId: conversationId,
      senderId: _currentUserId,
      clientMessageId: clientId,
      kind: 'text',
      body: text,
      createdAt: now,
      replyToId: replyToId,
      isOptimistic: true,
      status: MessageStatus.sending,
    );
    state = state.copyWith(messages: [...state.messages, optimistic], isSending: true);

    // If offline, enqueue and keep optimistic visible with queued badge.
    final online = await ConnectivityService.instance.checkNow();
    if (!online) {
      await _queue.enqueue(QueuedMessage(
        localId: optimistic.id,
        conversationId: conversationId,
        clientMessageId: clientId,
        kind: 'text',
        body: text,
        createdAt: now,
        replyToId: replyToId,
      ));
      state = state.copyWith(isSending: false);
      return;
    }

    try {
      final persisted = await _repo.sendTextMessage(conversationId: conversationId, body: text, clientMessageId: clientId, replyToId: replyToId);
      // Replace optimistic with persisted.
      final updated = state.messages.map((m) => m.id == optimistic.id ? persisted.copyWith(status: MessageStatus.sent) : m).toList();
      // Deduplicate if realtime already inserted it.
      final ids = updated.map((m) => m.id).toSet();
      if (ids.length != updated.length) {
        // Remove duplicate optimistic if persisted already came via realtime.
        state = state.copyWith(messages: updated.where((m) => !m.isOptimistic || m.clientMessageId != clientId).toList(), isSending: false);
      } else {
        state = state.copyWith(messages: updated, isSending: false);
      }
      // Clean any stale queue entry.
      await _queue.removeByClientId(clientId);
    } catch (e) {
      // Mark failed — allow retry. Also enqueue for later auto-retry.
      final failed = state.messages.map((m) => m.id == optimistic.id ? m.copyWith(status: MessageStatus.failed) : m).toList();
      state = state.copyWith(messages: failed, isSending: false);
      await _queue.enqueue(QueuedMessage(localId: optimistic.id, conversationId: conversationId, clientMessageId: clientId, kind: 'text', body: text, createdAt: now, replyToId: replyToId));
      // Persist error for retry banner.
      await _queue.markFailed(clientId, e.toString());
    }
  }

  Future<void> sendMedia({
    required String kind,
    String? body,
    String? replyToId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    int? width,
    int? height,
    int? durationMs,
  }) async {
    final clientId = _newUuid();
    final now = DateTime.now();
    final optimistic = MessageModel(
      id: 'optimistic_$clientId',
      conversationId: conversationId,
      senderId: _currentUserId,
      clientMessageId: clientId,
      kind: kind,
      body: body,
      createdAt: now,
      replyToId: replyToId,
      isOptimistic: true,
      status: MessageStatus.sending,
    );
    state = state.copyWith(messages: [...state.messages, optimistic], isSending: true);

    final online = await ConnectivityService.instance.checkNow();
    if (!online) {
      await _queue.enqueue(QueuedMessage(localId: optimistic.id, conversationId: conversationId, clientMessageId: clientId, kind: kind, body: body, createdAt: now, replyToId: replyToId));
      state = state.copyWith(isSending: false);
      return;
    }

    try {
      final path = await _repo.uploadChatFile(conversationId: conversationId, clientMessageId: clientId, fileName: fileName, mimeType: mimeType, bytes: bytes);
      final persisted = await _repo.sendMediaMessage(
        conversationId: conversationId,
        clientMessageId: clientId,
        kind: kind,
        body: body,
        replyToId: replyToId,
        storagePath: path,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        width: width,
        height: height,
        durationMs: durationMs,
      );
      final updated = state.messages.map((m) => m.id == optimistic.id ? persisted.copyWith(status: MessageStatus.sent) : m).toList();
      state = state.copyWith(messages: updated, isSending: false);
      await _queue.removeByClientId(clientId);
    } catch (e) {
      final failed = state.messages.map((m) => m.id == optimistic.id ? m.copyWith(status: MessageStatus.failed) : m).toList();
      state = state.copyWith(messages: failed, isSending: false);
      await _queue.enqueue(QueuedMessage(localId: optimistic.id, conversationId: conversationId, clientMessageId: clientId, kind: kind, body: body, createdAt: now, replyToId: replyToId));
      await _queue.markFailed(clientId, e.toString());
    }
  }

  Future<void> retryFailed(String optimisticId) async {
    final msg = state.messages.where((m) => m.id == optimisticId).firstOrNull;
    if (msg == null || msg.status != MessageStatus.failed) return;
    // Re-send via same clientMessageId to preserve idempotency.
    state = state.copyWith(messages: state.messages.map((m) => m.id == optimisticId ? m.copyWith(status: MessageStatus.sending) : m).toList());
    try {
      final persisted = await _repo.sendTextMessage(conversationId: conversationId, body: msg.body ?? '', clientMessageId: msg.clientMessageId, replyToId: msg.replyToId);
      state = state.copyWith(messages: state.messages.map((m) => m.id == optimisticId ? persisted.copyWith(status: MessageStatus.sent) : m).toList());
      await _queue.removeByClientId(msg.clientMessageId);
    } catch (e) {
      state = state.copyWith(messages: state.messages.map((m) => m.id == optimisticId ? m.copyWith(status: MessageStatus.failed) : m).toList());
      await _queue.markFailed(msg.clientMessageId, e.toString());
    }
  }

  /// Retries all queued messages for this conversation (called when connectivity returns).
  Future<void> retryAllQueued() async {
    final queued = _queue.forConversation(conversationId);
    for (final q in queued) {
      try {
        final persisted = await _repo.sendTextMessage(conversationId: q.conversationId, body: q.body ?? '', clientMessageId: q.clientMessageId, replyToId: q.replyToId);
        // Remove optimistic and add persisted (or replace).
        state = state.copyWith(messages: [
          ...state.messages.where((m) => m.id != q.localId),
          persisted.copyWith(status: MessageStatus.sent),
        ]..sort((a, b) => (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now())));
        await _queue.removeByClientId(q.clientMessageId);
      } catch (e) {
        await _queue.markFailed(q.clientMessageId, e.toString());
      }
    }
  }

  Future<void> editMessage(String messageId, String newBody) async {
    try {
      await _repo.editMessage(messageId: messageId, newBody: newBody);
      state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(body: newBody, editedAt: DateTime.now()) : m).toList());
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deleteForEveryone(String messageId) async {
    await _repo.deleteMessage(messageId);
    state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(deletedAt: DateTime.now()) : m).toList());
  }

  Future<void> deleteForMe(String messageId) async {
    await _repo.deleteMessageForMe(messageId);
    state = state.copyWith(messages: state.messages.where((m) => m.id != messageId).toList());
  }

  Future<void> forwardMessage(String messageId, String targetConversationId) async {
    await _repo.forwardMessage(messageId: messageId, targetConversationId: targetConversationId);
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    // Optimistic toggle.
    final hasIt = state.messages.where((m) => m.id == messageId).firstOrNull?.reactions.any((r) => r.userId == _currentUserId && r.emoji == emoji) ?? false;
    if (hasIt) {
      state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(reactions: m.reactions.where((r) => !(r.userId == _currentUserId && r.emoji == emoji)).toList()) : m).toList());
      await _repo.removeReaction(messageId: messageId, emoji: emoji);
    } else {
      final optimistic = MessageReaction(messageId: messageId, userId: _currentUserId ?? '', emoji: emoji, createdAt: DateTime.now());
      state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(reactions: [...m.reactions, optimistic]) : m).toList());
      await _repo.addReaction(messageId: messageId, emoji: emoji);
    }
  }

  Future<void> setPinned(String messageId, bool pinned) async {
    await _repo.setPinned(messageId: messageId, pinned: pinned);
    state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(isPinned: pinned) : m).toList());
  }

  Future<void> starMessage(String messageId) async {
    await _repo.starMessage(messageId);
    state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(isStarred: true) : m).toList());
  }

  Future<void> unstarMessage(String messageId) async {
    await _repo.unstarMessage(messageId);
    state = state.copyWith(messages: state.messages.map((m) => m.id == messageId ? m.copyWith(isStarred: false) : m).toList());
  }

  Future<void> markRead() => _markRead();

  Future<void> _markRead() async {
    try {
      await _repo.markConversationRead(conversationId);
    } catch (_) {}
  }

  Future<void> _markDeliveredForVisible() async {
    // Only for messages not by self and not already delivered.
    for (final m in state.messages) {
      if (m.senderId != _currentUserId && m.status == MessageStatus.sent) {
        try {
          await _repo.markMessageDelivered(m.id);
        } catch (_) {}
      }
    }
  }

  void setTyping(List<TypingIndicator> users) {
    state = state.copyWith(typingUsers: users);
    _typingTimer?.cancel();
    if (users.isNotEmpty) {
      _typingTimer = Timer(const Duration(seconds: 5), () => state = state.copyWith(typingUsers: []));
    }
  }

  // --- Realtime handlers (filtered to this conversation) ---

  void _onNewMessage(MessageModel msg) {
    if (msg.conversationId != conversationId) return;
    if (_seenIds.contains(msg.id)) return;
    _seenIds.add(msg.id);
    // Remove matching optimistic (same client_message_id).
    final filtered = state.messages.where((m) => m.clientMessageId != msg.clientMessageId || !m.isOptimistic).toList();
    // Resolve sender profile if missing — use existing cache or leave as is.
    state = state.copyWith(messages: [...filtered, msg]..sort((a, b) => (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now())));
    // If message is not by self, mark delivered (actual delivery acknowledgement).
    if (msg.senderId != _currentUserId) {
      unawaited(_repo.markMessageDelivered(msg.id));
    }
  }

  void _onMessageUpdate(MessageModel msg) {
    if (msg.conversationId != conversationId) return;
    state = state.copyWith(messages: state.messages.map((m) => m.id == msg.id ? msg : m).toList());
  }

  void _onMessageDelete(String id) {
    state = state.copyWith(messages: state.messages.map((m) => m.id == id ? m.copyWith(deletedAt: DateTime.now()) : m).toList());
  }

  void _onReceipt(MessageReceipt receipt) {
    state = state.copyWith(
        messages: state.messages.map((m) {
      if (m.id != receipt.messageId) return m;
      final receipts = [...m.receipts.where((r) => r.userId != receipt.userId), receipt];
      final status = receiptToStatus(receipts, _currentUserId ?? '', m.senderId ?? '');
      return m.copyWith(receipts: receipts, status: status);
    }).toList());
  }

  void _onReaction(MessageReaction reaction) {
    state = state.copyWith(
        messages: state.messages.map((m) {
      if (m.id != reaction.messageId) return m;
      if (reaction.emoji.isEmpty) {
        // Deletion signal.
        return m.copyWith(reactions: m.reactions.where((r) => r.userId != reaction.userId).toList());
      }
      // Add if not present.
      if (m.reactions.any((r) => r.userId == reaction.userId && r.emoji == reaction.emoji)) return m;
      return m.copyWith(reactions: [...m.reactions, reaction]);
    }).toList());
  }

  String _newUuid() => DateTime.now().microsecondsSinceEpoch.toString() + _currentUserId.hashCode.toString();

  @override
  void dispose() {
    _msgSub?.cancel();
    _updateSub?.cancel();
    _deleteSub?.cancel();
    _receiptSub?.cancel();
    _reactionSub?.cancel();
    _queueSub?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}

final conversationProvider = StateNotifierProvider.autoDispose.family<ConversationNotifier, ConversationState, String>((ref, id) {
  final repo = ref.watch(messagingRepositoryProvider);
  final rt = ref.watch(realtimeServiceProvider);
  final queue = ref.watch(offlineQueueProvider);
  final uid = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  return ConversationNotifier(conversationId: id, repo: repo, realtime: rt, queue: queue, currentUserId: uid);
});

// ---------------------------------------------------------------------------
// Presence / typing\n// ---------------------------------------------------------------------------

final presenceProvider = FutureProvider.autoDispose.family<PresenceState?, String>((ref, userId) async {
  final client = ref.watch(supabaseClientProvider);
  final row = await client
      .from('profiles')
      .select('id, last_seen_at')
      .eq('id', userId)
      .maybeSingle();
  if (row == null) return null;
  return PresenceState.fromJson(row);
});

/// Debounced typing broadcaster — call on each keystroke, it throttles.
class TypingNotifier extends StateNotifier<bool> {
  TypingNotifier(this._realtime, this._conversationId) : super(false);
  final RealtimeService _realtime;
  final String _conversationId;
  Timer? _timer;

  void onTyped() {
    if (state) return;
    state = true;
    _realtime.sendTyping(_conversationId);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () => state = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final typingProvider = StateNotifierProvider.autoDispose.family<TypingNotifier, bool, String>((ref, convId) {
  final rt = ref.watch(realtimeServiceProvider);
  return TypingNotifier(rt, convId);
});

void unawaited(Future<void> f) {}
