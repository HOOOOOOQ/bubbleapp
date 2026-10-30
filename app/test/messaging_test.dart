import 'package:bubbleapp/models/messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageModel', () {
    test('displayBody returns tombstone for deleted', () {
      final m = MessageModel(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hello',
        createdAt: DateTime.now(),
        deletedAt: DateTime.now(),
      );
      expect(m.displayBody, 'This message was deleted');
      expect(m.isDeleted, isTrue);
    });

    test('displayBody returns body for non-deleted', () {
      final m = MessageModel(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hello world',
        createdAt: DateTime.now(),
      );
      expect(m.displayBody, 'hello world');
      expect(m.isDeleted, isFalse);
    });

    test('isMine compares senderId correctly', () {
      final m = MessageModel(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm1',
        kind: 'text',
        body: 'hi',
        createdAt: DateTime.now(),
      );
      expect(m.isMine('u1'), isTrue);
      expect(m.isMine('u2'), isFalse);
      expect(m.isMine(null), isFalse);
    });

    test('parses from JSON defensively', () {
      final m = MessageModel.fromJson({'id': 'm1', 'conversation_id': 'c1'});
      expect(m.id, 'm1');
      expect(m.kind, 'text');
      expect(m.body, isNull);
      expect(m.receipts, isEmpty);
      expect(m.reactions, isEmpty);
    });

    test('isSystem for system kind or null sender', () {
      final sys = MessageModel(
        id: 'm1',
        conversationId: 'c1',
        senderId: null,
        clientMessageId: 'cm1',
        kind: 'system',
        body: 'joined',
        createdAt: DateTime.now(),
      );
      expect(sys.isSystem, isTrue);

      final text = MessageModel(
        id: 'm2',
        conversationId: 'c1',
        senderId: 'u1',
        clientMessageId: 'cm2',
        kind: 'text',
        body: 'hi',
        createdAt: DateTime.now(),
      );
      expect(text.isSystem, isFalse);
    });

    test('isMedia for image/video/voice/document', () {
      for (final kind in ['image', 'video', 'voice', 'document']) {
        final m = MessageModel(id: 'm1', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm1', kind: kind, createdAt: DateTime.now());
        expect(m.isMedia, isTrue, reason: kind);
      }
      final text = MessageModel(id: 'm1', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm1', kind: 'text', createdAt: DateTime.now());
      expect(text.isMedia, isFalse);
    });

    test('edited and deleted flags', () {
      final edited = MessageModel(id: 'm1', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm1', kind: 'text', body: 'hi', createdAt: DateTime.now(), editedAt: DateTime.now());
      expect(edited.isEdited, isTrue);
      expect(edited.isDeleted, isFalse);

      final deleted = MessageModel(id: 'm1', conversationId: 'c1', senderId: 'u1', clientMessageId: 'cm1', kind: 'text', body: 'hi', createdAt: DateTime.now(), deletedAt: DateTime.now());
      expect(deleted.isDeleted, isTrue);
    });
  });

  group('ConversationSummary', () {
    test('isDirect and isGroup', () {
      final direct = ConversationSummary(id: 'c1', kind: 'direct', title: null, avatarUrl: null, directKey: 'a:b', createdBy: 'u1', lastMessageAt: null, createdAt: DateTime.now(), otherParticipant: null, unreadCount: 0, lastMessagePreview: null, lastMessageKind: null, lastMessageSenderId: null, isPinned: false, isArchived: false, isMuted: false, role: 'member', joinedAt: DateTime.now());
      expect(direct.isDirect, isTrue);
      expect(direct.isGroup, isFalse);

      final group = ConversationSummary(id: 'c2', kind: 'group', title: 'Team', avatarUrl: null, directKey: null, createdBy: 'u1', lastMessageAt: null, createdAt: DateTime.now(), otherParticipant: null, unreadCount: 0, lastMessagePreview: null, lastMessageKind: null, lastMessageSenderId: null, isPinned: false, isArchived: false, isMuted: false, role: 'owner', joinedAt: DateTime.now());
      expect(group.isGroup, isTrue);
      expect(group.isDirect, isFalse);
    });

    test('copyWith preserves fields', () {
      final c = ConversationSummary(id: 'c1', kind: 'direct', title: 'Chat', avatarUrl: null, directKey: 'a:b', createdBy: 'u1', lastMessageAt: null, createdAt: DateTime.now(), otherParticipant: null, unreadCount: 2, lastMessagePreview: 'hi', lastMessageKind: 'text', lastMessageSenderId: 'u2', isPinned: false, isArchived: false, isMuted: false, role: 'member', joinedAt: DateTime.now());
      final pinned = c.copyWith(isPinned: true);
      expect(pinned.isPinned, isTrue);
      expect(pinned.unreadCount, 2);
      expect(pinned.id, 'c1');
    });
  });

  group('MessageStatus lifecycle', () {
    test('receiptToStatus returns read when any read', () {
      final receipts = [
        MessageReceipt(messageId: 'm1', userId: 'u2', status: 'delivered', updatedAt: DateTime.now()),
        MessageReceipt(messageId: 'm1', userId: 'u3', status: 'read', updatedAt: DateTime.now()),
      ];
      expect(receiptToStatus(receipts, 'u1', 'u1'), MessageStatus.read);
    });

    test('receiptToStatus returns delivered when no read', () {
      final receipts = [MessageReceipt(messageId: 'm1', userId: 'u2', status: 'delivered', updatedAt: DateTime.now())];
      expect(receiptToStatus(receipts, 'u1', 'u1'), MessageStatus.delivered);
    });

    test('receiptToStatus returns sent when empty', () {
      expect(receiptToStatus([], 'u1', 'u1'), MessageStatus.sent);
    });
  });

  group('MessageAttachment', () {
    test('mime helpers', () {
      final img = MessageAttachment(id: 'a1', conversationId: 'c1', uploaderId: 'u1', storagePath: 'c1/img.jpg', mimeType: 'image/jpeg', sizeBytes: 1000, createdAt: DateTime.now());
      expect(img.isImage, isTrue);
      expect(img.isVideo, isFalse);

      final video = MessageAttachment(id: 'a2', conversationId: 'c1', uploaderId: 'u1', storagePath: 'c1/vid.mp4', mimeType: 'video/mp4', sizeBytes: 5000, createdAt: DateTime.now());
      expect(video.isVideo, isTrue);

      final audio = MessageAttachment(id: 'a3', conversationId: 'c1', uploaderId: 'u1', storagePath: 'c1/voice.m4a', mimeType: 'audio/mp4', sizeBytes: 2000, createdAt: DateTime.now());
      expect(audio.isAudio, isTrue);

      final pdf = MessageAttachment(id: 'a4', conversationId: 'c1', uploaderId: 'u1', storagePath: 'c1/doc.pdf', mimeType: 'application/pdf', sizeBytes: 3000, createdAt: DateTime.now());
      expect(pdf.isPdf, isTrue);
    });
  });

  group('QueuedMessage', () {
    test('toJson and fromJson round-trip', () {
      final q = QueuedMessage(localId: 'local1', conversationId: 'c1', clientMessageId: 'cm1', kind: 'text', body: 'hello', createdAt: DateTime.utc(2024, 1, 1, 12, 0));
      final json = q.toJson();
      final restored = QueuedMessage.fromJson(json);
      expect(restored.localId, q.localId);
      expect(restored.conversationId, q.conversationId);
      expect(restored.clientMessageId, q.clientMessageId);
      expect(restored.body, 'hello');
    });

    test('copyWith increments retry', () {
      final q = QueuedMessage(localId: 'l1', conversationId: 'c1', clientMessageId: 'cm1', kind: 'text', body: 'hi', createdAt: DateTime.now());
      final retried = q.copyWith(retryCount: 1, lastError: 'network');
      expect(retried.retryCount, 1);
      expect(retried.lastError, 'network');
    });
  });

  group('PresenceState', () {
    test('isRecentlyOnline when lastSeen within 5 min', () {
      final p = PresenceState(userId: 'u1', isOnline: true, lastSeenAt: DateTime.now());
      expect(p.isRecentlyOnline, isTrue);

      final offline = PresenceState(userId: 'u1', isOnline: false, lastSeenAt: DateTime.now().subtract(const Duration(minutes: 10)));
      expect(offline.isRecentlyOnline, isFalse);
    });
  });

  group('SearchResult', () {
    test('isEmpty and isNotEmpty', () {
      const empty = SearchResult(users: [], conversations: [], messages: [], channels: []);
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
    });
  });

  group('BusinessLabel', () {
    test('parses JSON', () {
      final l = BusinessLabel.fromJson({'id': 'l1', 'business_id': 'b1', 'name': 'VIP', 'color': '#2563EB', 'created_at': '2024-01-01T00:00:00Z'});
      expect(l.name, 'VIP');
      expect(l.color, '#2563EB');
    });
  });
}
