import 'package:bubbleapp/models/social.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Story model', () {
    test('parses text story with privacy', () {
      final s = Story.fromJson({
        'id': 's1',
        'author_id': 'u1',
        'kind': 'text',
        'privacy': 'followers',
        'body': 'Hello world',
        'created_at': '2024-01-01T10:00:00Z',
        'expires_at': DateTime.now().add(const Duration(hours: 23)).toIso8601String(),
        'view_count': 5,
      });
      expect(s.kind, StoryKind.text);
      expect(s.privacy, StoryPrivacy.followers);
      expect(s.body, 'Hello world');
      expect(s.isExpired, isFalse);
    });

    test('expired story detection', () {
      final s = Story.fromJson({
        'id': 's2',
        'author_id': 'u1',
        'kind': 'photo',
        'privacy': 'everyone',
        'expires_at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      });
      expect(s.isExpired, isTrue);
    });

    test('custom audience privacy', () {
      final s = Story.fromJson({'id': 's3', 'author_id': 'u1', 'kind': 'text', 'privacy': 'custom', 'body': 'custom audience'});
      expect(s.privacy, StoryPrivacy.custom);
      expect(s.privacyLabel, 'Custom');
    });

    test('close_friends privacy', () {
      final s = Story.fromJson({'id': 's4', 'author_id': 'u1', 'kind': 'text', 'privacy': 'close_friends'});
      expect(s.privacy, StoryPrivacy.closeFriends);
    });

    test('stickers and textElements parsing', () {
      final s = Story.fromJson({
        'id': 's5',
        'author_id': 'u1',
        'kind': 'text',
        'privacy': 'contacts',
        'text_elements': [{'text': 'Hi', 'color': '#FFF', 'size': 18}],
        'stickers': [{'emoji': '❤️'}],
        'link_url': 'https://example.com',
      });
      expect(s.textElements.length, 1);
      expect(s.stickers.length, 1);
      expect(s.linkUrl, 'https://example.com');
    });

    test('toCreateJson respects DB mapping', () {
      final s = Story(id: 'id', authorId: 'u1', kind: StoryKind.video, privacy: StoryPrivacy.closeFriends, createdAt: null, expiresAt: null, body: 'vid', mediaPath: 'path', backgroundColor: '#FFF');
      final j = s.toCreateJson();
      expect(j['kind'], 'video');
      expect(j['privacy'], 'close_friends');
    });
  });

  group('Community', () {
    test('parses public community', () {
      final c = Community.fromJson({
        'id': 'c1',
        'name': 'Devs',
        'description': 'Dev community',
        'visibility': 'public',
        'owner_id': 'u1',
        'username': 'devs',
        'category': 'Tech',
        'join_approval': false,
        'member_count': 10,
      });
      expect(c.visibility, CommunityVisibility.public);
      expect(c.name, 'Devs');
      expect(c.username, 'devs');
    });

    test('private with approval', () {
      final c = Community.fromJson({'id': 'c2', 'name': 'Private', 'description': '', 'visibility': 'private', 'owner_id': 'u1', 'join_approval': true});
      expect(c.visibility, CommunityVisibility.private);
      expect(c.joinApproval, isTrue);
    });
  });

  group('Post', () {
    test('parses image post', () {
      final p = Post.fromJson({
        'id': 'p1',
        'author_id': 'u1',
        'kind': 'image',
        'visibility': 'public',
        'body': 'Check this #flutter @alice',
        'media_paths': ['post-media/u1/123.jpg'],
        'created_at': '2024-01-01T10:00:00Z',
        'reaction_count': 5,
      });
      expect(p.kind, PostKind.image);
      expect(p.hasMedia, isTrue);
      expect(p.body, contains('#flutter'));
    });

    test('link post with preview', () {
      final p = Post.fromJson({'id': 'p2', 'author_id': 'u1', 'kind': 'link', 'visibility': 'public', 'link_url': 'https://example.com', 'link_preview': {'title': 'Example'}});
      expect(p.linkUrl, 'https://example.com');
      expect(p.linkPreview?['title'], 'Example');
    });

    test('poll post', () {
      final p = Post.fromJson({'id': 'p3', 'author_id': 'u1', 'kind': 'poll', 'visibility': 'public', 'poll_id': 'poll1'});
      expect(p.pollId, 'poll1');
    });
  });

  group('Poll', () {
    test('parses poll with options and expiry', () {
      final poll = Poll.fromJson({
        'id': 'poll1',
        'author_id': 'u1',
        'question': 'Best language?',
        'allow_multiple': false,
        'allow_anonymous': true,
        'expires_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'total_votes': 10,
        'my_votes': ['opt1'],
        'options': [
          {'id': 'opt1', 'poll_id': 'poll1', 'label': 'Dart', 'sort_order': 0, 'vote_count': 7},
          {'id': 'opt2', 'poll_id': 'poll1', 'label': 'Kotlin', 'sort_order': 1, 'vote_count': 3},
        ],
      });
      expect(poll.question, 'Best language?');
      expect(poll.options.length, 2);
      expect(poll.allowAnonymous, isTrue);
      expect(poll.isExpired, isFalse);
      expect(poll.myVotes, contains('opt1'));
    });
  });

  group('GroupSettings', () {
    test('defaults allow all', () {
      final g = GroupSettings(conversationId: 'c1');
      expect(g.allowSendMessages, isTrue);
      expect(g.allowStartCalls, isTrue);
      expect(g.requireApproval, isFalse);
    });
    test('parses custom permissions', () {
      final g = GroupSettings.fromJson({'conversation_id': 'c1', 'allow_send_messages': false, 'allow_create_polls': false, 'require_approval': true});
      expect(g.allowSendMessages, isFalse);
      expect(g.allowCreatePolls, isFalse);
      expect(g.requireApproval, isTrue);
    });
  });

  group('Hashtag extraction', () {
    test('hashtag model', () {
      final h = Hashtag.fromJson({'tag': 'flutter', 'post_count': 42});
      expect(h.tag, 'flutter');
      expect(h.postCount, 42);
    });
  });

  group('Privacy enforcement', () {
    test('post visibility parsing', () {
      expect(Post.fromJson({'id':'p','author_id':'u1','kind':'text','visibility':'followers'}).visibility, PostVisibility.followers);
      expect(Post.fromJson({'id':'p','author_id':'u1','kind':'text','visibility':'contacts'}).visibility, PostVisibility.contacts);
      expect(Post.fromJson({'id':'p','author_id':'u1','kind':'text','visibility':'private'}).visibility, PostVisibility.private);
    });
  });
}
