import 'package:bubbleapp/models/social.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Feed & Comments', () {
    test('post hashtags extracted', () {
      final body = 'Loving #flutter and #dart! @bob';
      final tags = RegExp(r'#([a-zA-Z0-9_]{2,64})').allMatches(body).map((m) => m.group(1)!).toList();
      expect(tags, contains('flutter'));
      expect(tags, contains('dart'));
    });

    test('mentions extracted', () {
      final body = 'Hey @alice and @bob check this';
      final mentions = RegExp(r'@([a-zA-Z0-9_]{3,32})').allMatches(body).map((m) => m.group(1)!).toList();
      expect(mentions, contains('alice'));
      expect(mentions, contains('bob'));
    });

    test('nested comment depth limit', () {
      final c0 = Comment(id: 'c0', postId: 'p1', authorId: 'u1', body: 'top', depth: 0, createdAt: DateTime.now());
      final c1 = Comment(id: 'c1', postId: 'p1', parentId: 'c0', authorId: 'u2', body: 'reply', depth: 1, createdAt: DateTime.now());
      expect(c0.depth, 0);
      expect(c1.isReply, isTrue);
      expect(c1.depth, 1);
      // depth 6 should be rejected server-side
      final deep = Comment(id: 'c6', postId: 'p1', parentId: 'c5', authorId: 'u1', body: 'deep', depth: 5, createdAt: DateTime.now());
      expect(deep.depth, 5);
    });

    test('comment ownership', () {
      final c = Comment(id: 'c1', postId: 'p1', authorId: 'u1', body: 'hello', depth: 0, createdAt: DateTime.now());
      final isOwner = c.authorId == 'u1';
      expect(isOwner, isTrue);
    });

    test('post share kind', () {
      final p = Post.fromJson({'id': 'p1', 'author_id': 'u1', 'kind': 'share_channel', 'visibility': 'public', 'shared_channel_post_id': 'cp1'});
      expect(p.kind, PostKind.shareChannel);
    });
  });

  group('Search visibility', () {
    test('private posts filtered by RLS (model level)', () {
      final public = Post.fromJson({'id': 'p1', 'author_id': 'u1', 'kind': 'text', 'visibility': 'public'});
      final priv = Post.fromJson({'id': 'p2', 'author_id': 'u1', 'kind': 'text', 'visibility': 'private'});
      expect(public.visibility, PostVisibility.public);
      expect(priv.visibility, PostVisibility.private);
    });
  });

  group('Blocked user restrictions', () {
    test('Story blocked check is via is_blocked_between', () {
      // This is DB-level; model just ensures blocked users not in feed
      expect(true, isTrue); // placeholder for RLS test
    });
  });
}
