import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/social.dart';

class SocialRepository {
  SocialRepository(this._client);
  final SupabaseClient _client;
  String? get uid => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------------
  // Followers / Close Friends
  // ---------------------------------------------------------------------------

  Future<void> follow(String userId) async {
    if (uid == null) throw const AuthException('Not signed in');
    await _client.from('follows').insert({'follower_id': uid, 'followee_id': userId});
  }
  Future<void> unfollow(String userId) async => _client.from('follows').delete().match({'follower_id': uid!, 'followee_id': userId});
  Future<bool> isFollowing(String userId) async {
    final r = await _client.from('follows').select().match({'follower_id': uid!, 'followee_id': userId}).maybeSingle();
    return r != null;
  }
  Future<List<String>> myFollowers() async {
    final rows = await _client.from('follows').select('follower_id').eq('followee_id', uid!);
    return (rows as List).map((e) => e['follower_id'] as String).toList();
  }

  Future<void> addCloseFriend(String friendId) async => _client.from('close_friends').insert({'owner_id': uid, 'friend_id': friendId});
  Future<void> removeCloseFriend(String friendId) async => _client.from('close_friends').delete().match({'owner_id': uid!, 'friend_id': friendId});
  Future<List<StoryAuthor>> closeFriends() async {
    final rows = await _client.from('close_friends').select('friend_id, profiles!close_friends_friend_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('owner_id', uid!);
    return (rows as List).map((r) {
      final p = r['profiles'] as Map<String, dynamic>?;
      if (p == null) return null;
      return StoryAuthor.fromJson(p..['id'] = r['friend_id']);
    }).whereType<StoryAuthor>().toList();
  }

  // ---------------------------------------------------------------------------
  // Stories
  // ---------------------------------------------------------------------------

  Future<Story> createStory({
    required String kind, // text | photo | video
    String? body,
    String? caption,
    String? mediaPath,
    String? background,
    String? backgroundColor,
    String? textColor,
    List<Map<String, dynamic>> textElements = const [],
    List<Map<String, dynamic>> stickers = const [],
    String? linkUrl,
    String? musicUrl,
    String privacy = 'contacts',
    List<String> customAudience = const [],
    List<String> hiddenFrom = const [],
    String? pollId,
  }) async {
    if (uid == null) throw const AuthException('Not signed in');
    final row = await _client.from('stories').insert({
      'author_id': uid,
      'kind': kind,
      'body': body,
      'caption': caption,
      'media_path': mediaPath,
      'background': background,
      'background_color': backgroundColor,
      'text_color': textColor,
      'text_elements': textElements,
      'stickers': stickers,
      'link_url': linkUrl,
      'music_url': musicUrl,
      'privacy': privacy,
      'poll_id': pollId,
    }).select().single();
    final id = row['id'] as String;
    if (customAudience.isNotEmpty) {
      await _client.from('story_audience').insert(customAudience.map((u) => {'story_id': id, 'user_id': u}).toList());
    }
    if (hiddenFrom.isNotEmpty) {
      await _client.from('story_hidden_from').insert(hiddenFrom.map((u) => {'story_id': id, 'hidden_user_id': u}).toList());
    }
    return Story.fromJson(row);
  }

  Future<String> uploadStoryMedia(String storyId, Uint8List bytes, String mime) async {
    final path = '${uid!}/$storyId-${DateTime.now().millisecondsSinceEpoch}';
    await _client.storage.from('story-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: true));
    // Return path, caller will update story media_path
    await _client.from('stories').update({'media_path': path}).eq('id', storyId);
    return path;
  }

  Future<List<Story>> feedStories({int limit = 50}) async {
    // Fetch stories visible to current user (RLS already filters), plus own
    final rows = await _client.from('stories').select('*, profiles!stories_author_id_fkey(id, username, display_name, avatar_url, is_verified)').isFilter('hidden_at', null).gt('expires_at', DateTime.now().toIso8601String()).order('created_at', ascending: false).limit(limit);
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      if (r['profiles'] != null) m['author'] = r['profiles'];
      return Story.fromJson(m);
    }).where((s) => !s.isExpired).toList();
  }

  Future<List<Story>> storiesByAuthor(String authorId) async {
    final rows = await _client.from('stories').select().eq('author_id', authorId).isFilter('hidden_at', null).gt('expires_at', DateTime.now().toIso8601String()).order('created_at', ascending: false);
    return (rows as List).map((e) => Story.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> viewStory(String storyId) async {
    await _client.from('story_views').insert({'story_id': storyId, 'viewer_id': uid});
    // increment view_count via RPC or trigger - do optimistic
    await _client.rpc('increment_story_view', params: {'p_story_id': storyId}).catchError((_) {});
  }

  Future<void> reactToStory(String storyId, String emoji) async {
    await _client.from('story_reactions').upsert({'story_id': storyId, 'user_id': uid, 'emoji': emoji});
  }
  Future<void> removeStoryReaction(String storyId) async => _client.from('story_reactions').delete().match({'story_id': storyId, 'user_id': uid!});

  Future<void> replyToStory(String storyId, String body) async {
    await _client.from('story_replies').insert({'story_id': storyId, 'author_id': uid, 'body': body});
  }

  Future<List<StoryViewer>> storyViewers(String storyId) async {
    final rows = await _client.from('story_views').select('story_id, viewer_id, viewed_at, viewer:profiles!story_views_viewer_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('story_id', storyId).order('viewed_at', ascending: false);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (e['viewer'] != null) m['viewer'] = e['viewer'];
      return StoryViewer.fromJson(m);
    }).toList();
  }

  Future<StoryInsight> storyInsights(String storyId) async {
    final viewers = await storyViewers(storyId);
    final reactions = await _client.from('story_reactions').select().eq('story_id', storyId);
    final replies = await _client.from('story_replies').select().eq('story_id', storyId);
    return StoryInsight(storyId: storyId, viewCount: viewers.length, reactions: (reactions as List).length, replies: (replies as List).length, viewers: viewers);
  }

  Future<void> muteStoryAuthor(String authorId) async => _client.from('story_mutes').insert({'user_id': uid, 'muted_id': authorId});
  Future<void> unmuteStoryAuthor(String authorId) async => _client.from('story_mutes').delete().match({'user_id': uid!, 'muted_id': authorId});
  Future<List<String>> mutedAuthors() async {
    final rows = await _client.from('story_mutes').select('muted_id').eq('user_id', uid!);
    return (rows as List).map((e) => e['muted_id'] as String).toList();
  }

  Future<void> hideStoryFrom(String storyId, List<String> userIds) async {
    await _client.from('story_hidden_from').insert(userIds.map((u) => {'story_id': storyId, 'hidden_user_id': u}).toList());
  }

  Future<void> deleteStory(String storyId) async => _client.from('stories').delete().eq('id', storyId);

  Future<String> storyMediaUrl(String path) async {
    // story-media is private; use signed URL
    final url = await _client.storage.from('story-media').createSignedUrl(path, 3600);
    return url;
  }

  // ---------------------------------------------------------------------------
  // Channels — extended
  // ---------------------------------------------------------------------------

  Future<Community> createChannel({
    required String name,
    required String username,
    String description = '',
    String? avatarPath,
    String? coverPath,
    bool isPublic = true,
    String? category,
    String? rules,
  }) async {
    final row = await _client.from('channels').insert({
      'name': name,
      'username': username.toLowerCase(),
      'description': description,
      'avatar_url': avatarPath,
      'cover_url': coverPath,
      'is_public': isPublic,
      'category': category,
      'rules': rules,
      'owner_id': uid,
    }).select().single();
    // auto-add owner as member
    await _client.from('channel_members').insert({'channel_id': row['id'], 'user_id': uid, 'role': 'owner'});
    return Community.fromJson(row..['visibility'] = isPublic ? 'public' : 'private');
  }

  Future<void> setChannelMemberRole(String channelId, String userId, String role) async {
    await _client.from('channel_members').upsert({'channel_id': channelId, 'user_id': userId, 'role': role});
  }

  Future<List<Map<String,dynamic>>> channelMembers(String channelId) async {
    final rows = await _client.from('channel_members').select('*, profiles!channel_members_user_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('channel_id', channelId);
    return (rows as List).cast<Map<String,dynamic>>();
  }

  Future<String> publishChannelPostEx({
    required String channelId,
    required String body,
    String kind = 'text',
    String? mediaPath,
    String? pollId,
    Map<String,dynamic>? linkPreview,
    DateTime? publishAt,
  }) async {
    final row = await _client.from('channel_posts').insert({
      'channel_id': channelId,
      'author_id': uid,
      'kind': kind,
      'body': body,
      'media_path': mediaPath,
      'poll_id': pollId,
      'link_preview': linkPreview,
      'publish_at': publishAt?.toIso8601String(),
      'is_scheduled': publishAt != null && publishAt.isAfter(DateTime.now()),
    }).select('id').single();
    return row['id'] as String;
  }

  Future<void> editChannelPost(String postId, String body) async => _client.from('channel_posts').update({'body': body, 'edited_at': DateTime.now().toIso8601String()}).eq('id', postId);
  Future<void> deleteChannelPost(String postId) async => _client.from('channel_posts').delete().eq('id', postId);

  // ---------------------------------------------------------------------------
  // Communities
  // ---------------------------------------------------------------------------

  Future<Community> createCommunity({
    required String name,
    String description = '',
    String? username,
    String? category,
    String? rules,
    String visibility = 'private',
    bool joinApproval = false,
    String? avatarPath,
    String? coverPath,
  }) async {
    final row = await _client.from('communities').insert({
      'name': name,
      'description': description,
      'username': username?.toLowerCase(),
      'category': category,
      'rules': rules,
      'visibility': visibility,
      'join_approval': joinApproval,
      'owner_id': uid,
      'avatar_url': avatarPath,
      'cover_url': coverPath,
    }).select().single();
    // creator auto-member owner
    await _client.from('community_members').insert({'community_id': row['id'], 'user_id': uid, 'role': 'owner'});
    return Community.fromJson(row);
  }

  Future<List<Community>> communities({int limit = 50, String? search}) async {
    var q = _client.from('communities').select().order('created_at', ascending: false).limit(limit);
    if (search != null && search.trim().isNotEmpty) {
      q = q.ilike('name', '%${search.trim()}%');
    }
    final rows = await q;
    return (rows as List).map((e) => Community.fromJson(e as Map<String,dynamic>)).toList();
  }

  Future<Community?> community(String id) async {
    final row = await _client.from('communities').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return Community.fromJson(row);
  }

  Future<void> joinCommunity(String communityId) async {
    // respect join_approval: create request if needed else direct member
    final comm = await _client.from('communities').select('join_approval').eq('id', communityId).single();
    final needApproval = comm['join_approval'] == true;
    if (needApproval) {
      await _client.from('community_join_requests').insert({'community_id': communityId, 'user_id': uid});
    } else {
      await _client.from('community_members').insert({'community_id': communityId, 'user_id': uid, 'role': 'member'});
      await _client.rpc('increment_community_member_count', params: {'p_community_id': communityId}).catchError((_) {});
    }
  }
  Future<void> leaveCommunity(String communityId) async => _client.from('community_members').delete().match({'community_id': communityId, 'user_id': uid!});
  Future<void> requestJoinCommunity(String communityId, {String? message}) async => _client.from('community_join_requests').insert({'community_id': communityId, 'user_id': uid, 'message': message});

  Future<List<CommunityJoinRequest>> communityJoinRequests(String communityId) async {
    final rows = await _client.from('community_join_requests').select('*, profile:profiles!community_join_requests_user_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('community_id', communityId).eq('status','pending');
    return (rows as List).map((e) {
      final m = Map<String,dynamic>.from(e as Map);
      if (e['profile'] != null) m['profile'] = e['profile'];
      return CommunityJoinRequest.fromJson(m);
    }).toList();
  }
  Future<void> approveJoinRequest(String requestId) async => _client.from('community_join_requests').update({'status':'approved','reviewed_by': uid}).eq('id', requestId);
  Future<void> rejectJoinRequest(String requestId) async => _client.from('community_join_requests').update({'status':'rejected','reviewed_by': uid}).eq('id', requestId);

  Future<List<CommunityMember>> communityMembers(String communityId) async {
    final rows = await _client.from('community_members').select('community_id, user_id, role, joined_at, profile:profiles!community_members_user_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('community_id', communityId);
    return (rows as List).map((e) {
      final m = Map<String,dynamic>.from(e as Map);
      if (e['profile'] != null) m['profile'] = e['profile'];
      return CommunityMember.fromJson(m);
    }).toList();
  }

  Future<void> setCommunityMemberRole(String communityId, String userId, String role) async => _client.rpc('set_community_member_role', params: {'p_community_id': communityId, 'p_user_id': userId, 'p_role': role});

  Future<CommunityGroup> createCommunityGroup({required String communityId, required String conversationId, required String title, String description = ''}) async {
    final row = await _client.from('community_groups').insert({'community_id': communityId, 'conversation_id': conversationId, 'title': title, 'description': description}).select().single();
    return CommunityGroup.fromJson(row);
  }
  Future<List<CommunityGroup>> communityGroups(String communityId) async {
    final rows = await _client.from('community_groups').select().eq('community_id', communityId);
    return (rows as List).map((e) => CommunityGroup.fromJson(e as Map<String,dynamic>)).toList();
  }

  // ---------------------------------------------------------------------------
  // Groups — settings & invites
  // ---------------------------------------------------------------------------

  Future<GroupSettings> groupSettings(String conversationId) async {
    final row = await _client.from('group_settings').select().eq('conversation_id', conversationId).maybeSingle();
    if (row == null) return GroupSettings(conversationId: conversationId);
    return GroupSettings.fromJson(row);
  }
  Future<void> updateGroupSettings(GroupSettings s) async => _client.from('group_settings').upsert({
        'conversation_id': s.conversationId,
        'allow_send_messages': s.allowSendMessages,
        'allow_send_media': s.allowSendMedia,
        'allow_add_members': s.allowAddMembers,
        'allow_change_info': s.allowChangeInfo,
        'allow_pin_messages': s.allowPinMessages,
        'allow_create_polls': s.allowCreatePolls,
        'allow_start_calls': s.allowStartCalls,
        'allow_manage_invites': s.allowManageInvites,
        'require_approval': s.requireApproval,
      });

  Future<GroupInvite> createGroupInvite(String conversationId, {int? maxUses, DateTime? expiresAt}) async {
    final row = await _client.from('group_invites').insert({'conversation_id': conversationId, 'created_by': uid, 'max_uses': maxUses, 'expires_at': expiresAt?.toIso8601String()}).select().single();
    return GroupInvite.fromJson(row);
  }
  Future<List<GroupInvite>> groupInvites(String conversationId) async {
    final rows = await _client.from('group_invites').select().eq('conversation_id', conversationId).order('created_at', ascending: false);
    return (rows as List).map((e) => GroupInvite.fromJson(e as Map<String,dynamic>)).toList();
  }
  Future<String> joinGroupByInvite(String code) async {
    final id = await _client.rpc('join_group_by_invite', params: {'p_code': code});
    return id as String;
  }

  // ---------------------------------------------------------------------------
  // Posts / Feed
  // ---------------------------------------------------------------------------

  Future<Post> createPost({
    required String body,
    String kind = 'text',
    List<String> mediaPaths = const [],
    String? linkUrl,
    Map<String,dynamic>? linkPreview,
    String? pollId,
    String? communityId,
    String? conversationId,
    String visibility = 'public',
    String? sharedPostId,
  }) async {
    // extract hashtags + mentions for indexing
    final row = await _client.from('posts').insert({
      'author_id': uid,
      'kind': kind,
      'body': body,
      'media_paths': mediaPaths,
      'link_url': linkUrl,
      'link_preview': linkPreview,
      'poll_id': pollId,
      'community_id': communityId,
      'conversation_id': conversationId,
      'visibility': visibility,
      'shared_post_id': sharedPostId,
    }).select().single();
    // index hashtags
    final tags = _extractHashtags(body);
    if (tags.isNotEmpty) {
      for (final t in tags) {
        await _client.from('hashtags').upsert({'tag': t}, onConflict: 'tag').catchError((_) {});
        await _client.from('post_hashtags').insert({'post_id': row['id'], 'tag': t}).catchError((_) {});
      }
      // update counts (best effort)
      for (final t in tags) { _client.rpc('increment_hashtag_count', params: {'p_tag': t}).catchError((_) {}); }
    }
    // mentions: find @username patterns, create mentions rows
    final mentions = _extractMentions(body);
    for (final m in mentions) {
      final profile = await _client.from('profiles').select('id').eq('username', m).maybeSingle().catchError((_) => null);
      if (profile != null) {
        await _client.from('mentions').insert({'post_id': row['id'], 'mentioned_user_id': profile['id'], 'author_id': uid}).catchError((_) {});
      }
    }
    return Post.fromJson(row);
  }

  List<String> _extractHashtags(String text) {
    final re = RegExp(r'#([a-zA-Z0-9_]{2,64})');
    return re.allMatches(text).map((m) => m.group(1)!.toLowerCase()).toSet().toList();
  }
  List<String> _extractMentions(String text) {
    final re = RegExp(r'@([a-zA-Z0-9_]{3,32})');
    return re.allMatches(text).map((m) => m.group(1)!).toSet().toList();
  }

  Future<List<Post>> feed({String? communityId, String? authorId, String kind = 'home', int limit = 20, int offset = 0}) async {
    var q = _client.from('posts').select('*, author:profiles!posts_author_id_fkey(id, username, display_name, avatar_url, is_verified)').isFilter('hidden_at', null).order('created_at', ascending: false).range(offset, offset+limit-1);
    if (communityId != null) q = q.eq('community_id', communityId);
    if (authorId != null) q = q.eq('author_id', authorId);
    if (kind == 'following') {
      final following = await _client.from('follows').select('followee_id').eq('follower_id', uid!);
      final ids = (following as List).map((e) => e['followee_id'] as String).toList()..add(uid!);
      q = q.inFilter('author_id', ids);
    }
    final rows = await q;
    // enrich with counts (requires separate queries for MVP — do best effort)
    final posts = (rows as List).map((e) {
      final m = Map<String,dynamic>.from(e as Map);
      if (e['author'] != null) m['author'] = e['author'];
      return Post.fromJson(m);
    }).toList();
    // fetch reaction counts in batch (optional, keep 0 if fails)
    return posts;
  }

  Future<List<Post>> trendingPosts({int limit = 20}) async {
    try {
      final rows = await _client.rpc('trending_posts', params: {'p_limit': limit});
      return (rows as List).map((e) => Post.fromJson(Map<String,dynamic>.from(e as Map))).toList();
    } catch (_) {
      return feed(limit: limit);
    }
  }

  Future<Post?> post(String id) async {
    final row = await _client.from('posts').select('*, author:profiles!posts_author_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('id', id).maybeSingle();
    if (row == null) return null;
    final m = Map<String,dynamic>.from(row);
    if (row['author'] != null) m['author'] = row['author'];
    return Post.fromJson(m);
  }

  Future<void> deletePost(String id) async => _client.from('posts').delete().eq('id', id);
  Future<void> editPost(String id, String body) async => _client.from('posts').update({'body': body, 'is_edited': true}).eq('id', id);
  Future<void> pinPost(String id, bool pinned) async => _client.from('posts').update({'is_pinned': pinned}).eq('id', id);
  Future<void> viewPost(String id) async => _client.from('post_views').insert({'post_id': id, 'user_id': uid}).catchError((_) {});

  Future<void> reactToPost(String postId, String emoji) async => _client.from('post_reactions').insert({'post_id': postId, 'user_id': uid, 'emoji': emoji});
  Future<void> unreactToPost(String postId, String emoji) async => _client.from('post_reactions').delete().match({'post_id': postId, 'user_id': uid!, 'emoji': emoji});
  Future<void> bookmarkPost(String postId) async => _client.from('post_bookmarks').insert({'post_id': postId, 'user_id': uid});
  Future<void> unbookmarkPost(String postId) async => _client.from('post_bookmarks').delete().match({'post_id': postId, 'user_id': uid!});
  Future<void> sharePost(String postId, {String? body}) async => createPost(body: body ?? '', kind: 'text', sharedPostId: postId);

  // Comments
  Future<Comment> addComment(String postId, String body, {String? parentId}) async {
    // depth computed server-side; we send 0 and let trigger increment? For now compute locally
    int depth = 0;
    if (parentId != null) {
      final parent = await _client.from('comments').select('depth').eq('id', parentId).single();
      depth = (parent['depth'] as int) + 1;
      if (depth > 5) throw Exception('Maximum reply depth reached');
    }
    final row = await _client.from('comments').insert({'post_id': postId, 'parent_id': parentId, 'author_id': uid, 'body': body, 'depth': depth}).select().single();
    return Comment.fromJson(row);
  }
  Future<List<Comment>> comments(String postId) async {
    final rows = await _client.from('comments').select('*, author:profiles!comments_author_id_fkey(id, username, display_name, avatar_url, is_verified)').eq('post_id', postId).isFilter('hidden_at', null).order('created_at', ascending: true);
    return (rows as List).map((e) {
      final m = Map<String,dynamic>.from(e as Map);
      if (e['author'] != null) m['author'] = e['author'];
      return Comment.fromJson(m);
    }).toList();
  }
  Future<void> editComment(String id, String body) async => _client.from('comments').update({'body': body, 'is_edited': true}).eq('id', id);
  Future<void> deleteComment(String id) async => _client.from('comments').delete().eq('id', id);
  Future<void> reactToComment(String commentId, String emoji) async => _client.from('comment_reactions').insert({'comment_id': commentId, 'user_id': uid, 'emoji': emoji});

  // ---------------------------------------------------------------------------
  // Polls
  // ---------------------------------------------------------------------------

  Future<Poll> createPoll({required String question, required List<String> options, bool allowMultiple = false, bool allowAnonymous = false, bool allowChange = true, DateTime? expiresAt}) async {
    final poll = await _client.from('polls').insert({'author_id': uid, 'question': question, 'allow_multiple': allowMultiple, 'allow_anonymous': allowAnonymous, 'allow_change': allowChange, 'expires_at': expiresAt?.toIso8601String()}).select().single();
    final pollId = poll['id'] as String;
    for (int i=0;i<options.length;i++) {
      await _client.from('poll_options').insert({'poll_id': pollId, 'label': options[i], 'sort_order': i});
    }
    return pollWithOptions(pollId);
  }

  Future<Poll> pollWithOptions(String pollId) async {
    final pollRow = await _client.from('polls').select().eq('id', pollId).single();
    final opts = await _client.from('poll_options').select().eq('poll_id', pollId).order('sort_order');
    final votes = await _client.from('poll_votes').select('option_id').eq('poll_id', pollId);
    final voteCounts = <String,int>{};
    for (final v in votes as List) {
      final oid = v['option_id'] as String;
      voteCounts[oid] = (voteCounts[oid] ?? 0) + 1;
    }
    final options = (opts as List).map((o) {
      final m = Map<String,dynamic>.from(o as Map);
      m['vote_count'] = voteCounts[m['id']] ?? 0;
      return PollOption.fromJson(m);
    }).toList();
    final myVotes = await _client.from('poll_votes').select('option_id').eq('poll_id', pollId).eq('user_id', uid!);
    final myIds = (myVotes as List).map((e) => e['option_id'] as String).toList();
    final m = Map<String,dynamic>.from(pollRow);
    m['options'] = options.map((o) => {'id': o.id, 'poll_id': o.pollId, 'label': o.label, 'sort_order': o.sortOrder, 'vote_count': o.voteCount}).toList();
    m['my_votes'] = myIds;
    m['total_votes'] = (votes as List).length;
    return Poll.fromJson(m);
  }

  Future<void> votePoll(String pollId, String optionId) async => _client.rpc('cast_poll_vote', params: {'p_poll_id': pollId, 'p_option_id': optionId});
  Future<void> unvotePoll(String pollId) async => _client.from('poll_votes').delete().match({'poll_id': pollId, 'user_id': uid!});

  Future<String> uploadPostMedia(String postId, Uint8List bytes, String mime, String ext) async {
    final path = '${uid!}/$postId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('post-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return path;
  }
  Future<void> updatePostMedia(String postId, List<String> mediaPaths) async {
    await _client.from('posts').update({'media_paths': mediaPaths}).eq('id', postId);
  }
  Future<String> uploadCommunityMedia(String communityId, Uint8List bytes, String mime, String ext) async {
    final path = '$communityId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('community-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return path;
  }

  // ---------------------------------------------------------------------------
  // Discovery & Hashtags
  // ---------------------------------------------------------------------------

  Future<SearchResult> searchAll(String query, {int limit = 20}) async {
    final data = await _client.rpc('search_all', params: {'p_query': query, 'p_limit': limit});
    return SearchResult.fromJson(data as Map<String,dynamic>);
  }
  Future<List<String>> recentSearches() async {
    final rows = await _client.from('recent_searches').select('query').eq('user_id', uid!).order('created_at', ascending: false).limit(20);
    return (rows as List).map((e) => e['query'] as String).toList();
  }
  Future<void> recordSearch(String query) async => _client.rpc('record_search', params: {'p_query': query});

  Future<List<Hashtag>> trendingHashtags({int limit = 10}) async {
    try {
      final rows = await _client.rpc('trending_hashtags', params: {'p_limit': limit});
      return (rows as List).map((e) => Hashtag.fromJson(e as Map<String,dynamic>)).toList();
    } catch (_) { return []; }
  }
  Future<List<Post>> hashtagPosts(String tag, {int limit = 20}) async {
    final rows = await _client.from('post_hashtags').select('post_id, posts!post_hashtags_post_id_fkey(id, author_id, body, kind, created_at)').eq('tag', tag.toLowerCase()).limit(limit);
    return (rows as List).map((e) {
      final p = e['posts'] as Map<String,dynamic>?;
      if (p == null) return null;
      return Post.fromJson(p);
    }).whereType<Post>().toList();
  }

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------

  Future<void> report({required String targetType, required String targetId, required String reason, String? details, String? category}) async {
    await _client.from('reports').insert({'reporter_id': uid, 'target_type': targetType, 'target_id': targetId, 'reason': reason, 'details': details, 'category': category});
  }
  Future<List<Report>> myReports() async {
    final rows = await _client.from('reports').select().eq('reporter_id', uid!).order('created_at', ascending: false);
    return (rows as List).map((e) => Report.fromJson(e as Map<String,dynamic>)).toList();
  }
}
