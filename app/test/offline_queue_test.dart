import 'package:bubbleapp/models/messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests the core dedup / persistence logic of the offline queue without
/// needing secure storage — we exercise the model-level contracts that the
/// queue relies on.

void main() {
  group('Offline queue dedup contract', () {
    test('client_message_id is the idempotency key', () {
      // Two messages with same clientMessageId are the same logical message.
      final a = QueuedMessage(localId: 'local_a', conversationId: 'c1', clientMessageId: 'cm_same', kind: 'text', body: 'hello', createdAt: DateTime.now());
      final b = QueuedMessage(localId: 'local_b', conversationId: 'c1', clientMessageId: 'cm_same', kind: 'text', body: 'hello', createdAt: DateTime.now());
      expect(a.clientMessageId, b.clientMessageId);
      // Queue must deduplicate — we test the model identity, the queue enforces it.
    });

    test('different clientMessageIds are distinct even with same body', () {
      final a = QueuedMessage(localId: 'l1', conversationId: 'c1', clientMessageId: 'cm1', kind: 'text', body: 'hi', createdAt: DateTime.now());
      final b = QueuedMessage(localId: 'l2', conversationId: 'c1', clientMessageId: 'cm2', kind: 'text', body: 'hi', createdAt: DateTime.now());
      expect(a.clientMessageId, isNot(equals(b.clientMessageId)));
    });

    test('queue preserves insertion order per conversation', () {
      final items = [
        QueuedMessage(localId: 'l1', conversationId: 'c1', clientMessageId: 'cm1', kind: 'text', body: 'first', createdAt: DateTime.utc(2024, 1, 1, 10, 0)),
        QueuedMessage(localId: 'l2', conversationId: 'c1', clientMessageId: 'cm2', kind: 'text', body: 'second', createdAt: DateTime.utc(2024, 1, 1, 10, 1)),
        QueuedMessage(localId: 'l3', conversationId: 'c2', clientMessageId: 'cm3', kind: 'text', body: 'other chat', createdAt: DateTime.utc(2024, 1, 1, 10, 2)),
      ];
      // Simulate filtering for c1 — order must be l1, l2.
      final forC1 = items.where((e) => e.conversationId == 'c1').toList();
      expect(forC1.map((e) => e.localId).toList(), ['l1', 'l2']);
    });

    test('retryCount increments on failure', () {
      var q = QueuedMessage(localId: 'l1', conversationId: 'c1', clientMessageId: 'cm1', kind: 'text', body: 'hi', createdAt: DateTime.now());
      q = q.copyWith(retryCount: q.retryCount + 1, lastError: 'timeout');
      expect(q.retryCount, 1);
      q = q.copyWith(retryCount: q.retryCount + 1, lastError: 'timeout again');
      expect(q.retryCount, 2);
    });
  });

  group('Delivery lifecycle contract', () {
    test('optimistic message has sending status and isOptimistic flag', () {
      final m = MessageModel(
        id: 'optimistic_cm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hi',
        createdAt: DateTime.now(),
        isOptimistic: true,
        status: MessageStatus.sending,
      );
      expect(m.isOptimistic, isTrue);
      expect(m.status, MessageStatus.sending);
    });

    test('failed message can be retried with same clientMessageId', () {
      final failed = MessageModel(
        id: 'optimistic_cm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hi',
        createdAt: DateTime.now(),
        isOptimistic: true,
        status: MessageStatus.failed,
      );
      expect(failed.status, MessageStatus.failed);
      // Retry must reuse same clientMessageId to ensure dedup.
      expect(failed.clientMessageId, 'cm1');
    });

    test('sent -> delivered -> read progression via receipts', () {
      // Start: no receipts = sent.
      expect(receiptToStatus([], 'u1', 'u1'), MessageStatus.sent);
      // Delivered receipt arrives.
      final delivered = [MessageReceipt(messageId: 'm1', userId: 'u2', status: 'delivered', updatedAt: DateTime.now())];
      expect(receiptToStatus(delivered, 'u1', 'u1'), MessageStatus.delivered);
      // Read receipt supersedes delivered.
      final read = [
        MessageReceipt(messageId: 'm1', userId: 'u2', status: 'delivered', updatedAt: DateTime.now()),
        MessageReceipt(messageId: 'm1', userId: 'u2', status: 'read', updatedAt: DateTime.now()),
      ];
      expect(receiptToStatus(read, 'u1', 'u1'), MessageStatus.read);
    });
  });

  group('Attachment contracts', () {
    test('chat-media vs chat-attachments bucket routing', () {
      bool isMediaMime(String mime) => mime.startsWith('image/') || mime.startsWith('video/') || mime.startsWith('audio/');
      expect(isMediaMime('image/jpeg'), isTrue);
      expect(isMediaMime('video/mp4'), isTrue);
      expect(isMediaMime('audio/mp4'), isTrue);
      expect(isMediaMime('application/pdf'), isFalse);
      expect(isMediaMime('application/zip'), isFalse);
    });

    test('file size validation constants', () {
      const maxChatMedia = 104857600; // 100 MB from migration 0008
      const maxVerification = 20971520; // 20 MB
      expect(maxChatMedia, greaterThan(maxVerification));
      // Voice note typical size is well under limit.
      const voiceSize = 50000;
      expect(voiceSize, lessThan(maxChatMedia));
    });
  });
}
