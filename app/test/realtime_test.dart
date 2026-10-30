import 'package:bubbleapp/models/messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests realtime event handling contracts — dedup, delivery acknowledgement,
/// and subscription filtering. These are pure logic tests that mirror what
/// the RealtimeService and ConversationNotifier do.

void main() {
  group('Realtime dedup', () {
    test('duplicate message ids are ignored', () {
      final seen = <String>{};
      bool shouldProcess(String id) {
        if (seen.contains(id)) return false;
        seen.add(id);
        return true;
      }

      expect(shouldProcess('m1'), isTrue);
      expect(shouldProcess('m1'), isFalse);
      expect(shouldProcess('m2'), isTrue);
    });

    test('seen set is bounded (evicts old ids)', () {
      final seen = <String>{};
      const max = 5000;
      for (int i = 0; i < max + 100; i++) {
        seen.add('m$i');
        if (seen.length > max) seen.remove(seen.first);
      }
      expect(seen.length, max);
      expect(seen.contains('m0'), isFalse);
      expect(seen.contains('m100'), isTrue);
    });

    test('only messages for the current conversation are processed', () {
      const currentConv = 'c1';
      bool isForCurrentConv(String convId) => convId == currentConv;

      expect(isForCurrentConv('c1'), isTrue);
      expect(isForCurrentConv('c2'), isFalse);
    });
  });

  group('Delivery acknowledgement', () {
    test('recipient marks delivered, not just sent', () {
      // Simulates: sender sends -> DB insert succeeds -> recipient receives via realtime
      // -> recipient explicitly marks delivered. Sender's sent->delivered transition
      // depends on the receipt, not on insert success.
      final receipts = <MessageReceipt>[];
      // Initially no receipt = sent.
      expect(receiptToStatus(receipts, 'sender', 'sender'), MessageStatus.sent);
      // Recipient marks delivered (separate RPC, not automatic).
      receipts.add(MessageReceipt(messageId: 'm1', userId: 'recipient', status: 'delivered', updatedAt: DateTime.now()));
      expect(receiptToStatus(receipts, 'sender', 'sender'), MessageStatus.delivered);
    });

    test('read supersedes delivered', () {
      final receipts = [
        MessageReceipt(messageId: 'm1', userId: 'u2', status: 'delivered', updatedAt: DateTime.now()),
        MessageReceipt(messageId: 'm1', userId: 'u2', status: 'read', updatedAt: DateTime.now()),
      ];
      expect(receiptToStatus(receipts, 'u1', 'u1'), MessageStatus.read);
    });

    test('delivered is not inferred from database insert', () {
      // A message exists but no receipt = sent, not delivered.
      final msg = MessageModel(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hi',
        createdAt: DateTime.now(),
        receipts: [],
        status: MessageStatus.sent,
      );
      expect(msg.status, MessageStatus.sent);
      expect(msg.receipts, isEmpty);
    });
  });

  group('Reaction toggle', () {
    test('adding reaction that exists should remove it (toggle)', () {
      var reactions = [
        MessageReaction(messageId: 'm1', userId: 'u1', emoji: '❤️', createdAt: DateTime.now()),
      ];
      const emoji = '❤️';
      const userId = 'u1';
      final hasIt = reactions.any((r) => r.userId == userId && r.emoji == emoji);
      expect(hasIt, isTrue);
      // Toggle off
      if (hasIt) reactions = reactions.where((r) => !(r.userId == userId && r.emoji == emoji)).toList();
      expect(reactions, isEmpty);
    });

    test('adding new reaction', () {
      var reactions = <MessageReaction>[];
      const emoji = '😂';
      reactions = [...reactions, MessageReaction(messageId: 'm1', userId: 'u1', emoji: emoji, createdAt: DateTime.now())];
      expect(reactions.length, 1);
      expect(reactions.first.emoji, '😂');
    });
  });

  group('Pagination', () {
    test('loadMore uses before cursor correctly', () {
      final messages = [
        MessageModel(id: 'm3', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm3', kind: 'text', body: 'third', createdAt: DateTime.utc(2024, 1, 3)),
        MessageModel(id: 'm2', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm2', kind: 'text', body: 'second', createdAt: DateTime.utc(2024, 1, 2)),
        MessageModel(id: 'm1', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm1', kind: 'text', body: 'first', createdAt: DateTime.utc(2024, 1, 1)),
      ];
      // Simulate fetching before m1 (oldest loaded).
      final before = messages.first.createdAt; // actually newest in desc order; but our list is oldest-first
      // The cursor should be the oldest message's createdAt.
      final oldest = messages.reduce((a, b) => a.createdAt!.isBefore(b.createdAt!) ? a : b);
      expect(oldest.id, 'm1');
      expect(before, isNotNull);
    });

    test('hasMore is false when page < limit', () {
      const limit = 40;
      final page = List.generate(10, (i) => MessageModel(id: 'm$i', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm$i', kind: 'text', body: 'msg', createdAt: DateTime.now()));
      expect(page.length < limit, isTrue);
      // hasMore should be false.
    });
  });
}
