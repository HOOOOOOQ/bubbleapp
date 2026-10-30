import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/messaging.dart';

/// Offline message queue — persists to secure storage so queued messages survive
/// app restarts. Supabase Postgres remains the source of truth; this is only a
/// durable outbox with deduplication via client_message_id.
///
/// No SQLite primary DB — this is a plain JSON list in keystore-backed storage.
class OfflineQueue {
  OfflineQueue({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'bubbleapp.offline_queue.v1';
  final FlutterSecureStorage _storage;

  final _controller = StreamController<List<QueuedMessage>>.broadcast();
  List<QueuedMessage> _items = [];
  bool _loaded = false;

  Stream<List<QueuedMessage>> get stream => _controller.stream;
  List<QueuedMessage> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(key: _key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _items = list.whereType<Map<String, dynamic>>().map(QueuedMessage.fromJson).toList();
      } catch (_) {
        _items = [];
      }
    }
    _loaded = true;
    _controller.add(_items);
  }

  Future<void> _persist() async {
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await _storage.write(key: _key, value: raw);
    _controller.add(List.unmodifiable(_items));
  }

  /// Enqueues — deduplicates by client_message_id (idempotency key).
  Future<void> enqueue(QueuedMessage item) async {
    await load();
    if (_items.any((e) => e.clientMessageId == item.clientMessageId)) return;
    _items.add(item);
    // Preserve insertion order (FIFO).
    await _persist();
  }

  Future<void> removeByClientId(String clientMessageId) async {
    await load();
    _items.removeWhere((e) => e.clientMessageId == clientMessageId);
    await _persist();
  }

  Future<void> removeByLocalId(String localId) async {
    await load();
    _items.removeWhere((e) => e.localId == localId);
    await _persist();
  }

  Future<void> markFailed(String clientMessageId, String error) async {
    await load();
    final idx = _items.indexWhere((e) => e.clientMessageId == clientMessageId);
    if (idx < 0) return;
    _items[idx] = _items[idx].copyWith(retryCount: _items[idx].retryCount + 1, lastError: error);
    await _persist();
  }

  Future<void> clear() async {
    _items = [];
    await _persist();
  }

  /// All pending items for a conversation, in FIFO order.
  List<QueuedMessage> forConversation(String conversationId) =>
      _items.where((e) => e.conversationId == conversationId).toList();

  bool hasPendingFor(String conversationId) => _items.any((e) => e.conversationId == conversationId);

  void dispose() => _controller.close();
}

/// Simple in-memory fallback when secure storage is unavailable (e.g. tests).
class MemoryOfflineQueue extends OfflineQueue {
  MemoryOfflineQueue() : super(storage: const FlutterSecureStorage());

  final List<QueuedMessage> _mem = [];

  @override
  Future<void> load() async {}

  @override
  Future<void> _persist() async {}
}
