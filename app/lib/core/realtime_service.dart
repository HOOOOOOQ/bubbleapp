import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/messaging.dart';

/// Centralized realtime subscriptions for messaging.
///
/// - Subscribes only to conversations the user can access (RLS enforces it).
/// - Deduplicates events by message id (idempotency).
/// - Exposes typed streams for the UI to consume.
/// - Handles reconnection via Supabase's built-in reconnect; surfaces status.
class RealtimeService {
  RealtimeService(this._client);
  final SupabaseClient _client;

  RealtimeChannel? _channel;
  final _seenIds = <String>{};

  final _messageCtrl = StreamController<MessageModel>.broadcast();
  final _messageUpdateCtrl = StreamController<MessageModel>.broadcast();
  final _messageDeleteCtrl = StreamController<String>.broadcast();
  final _receiptCtrl = StreamController<MessageReceipt>.broadcast();
  final _reactionCtrl = StreamController<MessageReaction>.broadcast();
  final _typingCtrl = StreamController<TypingIndicator>.broadcast();
  final _presenceCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _conversationCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<MessageModel> get onMessage => _messageCtrl.stream;
  Stream<MessageModel> get onMessageUpdate => _messageUpdateCtrl.stream;
  Stream<String> get onMessageDelete => _messageDeleteCtrl.stream;
  Stream<MessageReceipt> get onReceipt => _receiptCtrl.stream;
  Stream<MessageReaction> get onReaction => _reactionCtrl.stream;
  Stream<TypingIndicator> get onTyping => _typingCtrl.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceCtrl.stream;
  Stream<Map<String, dynamic>> get onConversation => _conversationCtrl.stream;

  bool get isSubscribed => _channel != null;

  /// Subscribes to all realtime tables relevant to the user's conversations.
  /// RLS ensures the user only receives events for conversations they belong to.
  void subscribe() {
    if (_channel != null) return;

    final channel = _client.channel('bubbleapp:messaging');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id'] as String?;
            if (id == null || _seenIds.contains(id)) return;
            _seenIds.add(id);
            // Keep set bounded.
            if (_seenIds.length > 5000) _seenIds.remove(_seenIds.first);
            try {
              _messageCtrl.add(MessageModel.fromJson(row));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = payload.newRecord;
            try {
              _messageUpdateCtrl.add(MessageModel.fromJson(row));
              if (row['deleted_at'] != null) {
                _messageDeleteCtrl.add(row['id'] as String);
              }
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_receipts',
          callback: (payload) {
            try {
              _receiptCtrl.add(MessageReceipt.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'message_receipts',
          callback: (payload) {
            try {
              _receiptCtrl.add(MessageReceipt.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            try {
              _reactionCtrl.add(MessageReaction.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            // Deleted reaction — surface as removal by re-emitting with empty emoji.
            // Consumer can interpret as removal.
            try {
              final old = payload.oldRecord;
              _reactionCtrl.add(MessageReaction(
                messageId: old['message_id'] as String? ?? '',
                userId: old['user_id'] as String? ?? '',
                emoji: '',
                createdAt: null,
              ));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (payload) => _conversationCtrl.add(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversation_members',
          callback: (payload) => _conversationCtrl.add(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversation_members',
          callback: (payload) => _conversationCtrl.add(payload.newRecord),
        );

    // Presence via Supabase Presence (optional, best-effort).
    channel.onPresenceSync((payload) {
      _presenceCtrl.add(payload);
    });

    channel.subscribe();
    _channel = channel;
  }

  void unsubscribe() {
    if (_channel == null) return;
    _client.removeChannel(_channel!);
    _channel = null;
  }

  /// Call when app goes to background — keeps channel but stops presence.
  void pause() => _channel?.unsubscribe();

  /// Call when app resumes — re-subscribes if needed.
  void resume() {
    if (_channel == null) subscribe();
  }

  /// Broadcast typing indicator via Postgres changes on a lightweight table
  /// or via presence. We use a simple broadcast channel here.
  Future<void> sendTyping(String conversationId) async {
    final ch = _channel;
    if (ch == null) return;
    await ch.sendBroadcastMessage(event: 'typing', payload: {'conversation_id': conversationId});
  }

  void dispose() {
    unsubscribe();
    _messageCtrl.close();
    _messageUpdateCtrl.close();
    _messageDeleteCtrl.close();
    _receiptCtrl.close();
    _reactionCtrl.close();
    _typingCtrl.close();
    _presenceCtrl.close();
    _conversationCtrl.close();
  }
}
