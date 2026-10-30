/// Social ecosystem models — stories, channels, communities, groups, posts, polls, hashtags, reports.
/// All fields match Supabase schema (migrations 0003/0006/0013). Defensive parsing.

String _s(Object? v, [String f = '']) => v is String ? v : f;
bool _b(Object? v) => v == true;
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
DateTime? _dUtc(Object? v) => v is String ? DateTime.tryParse(v) : null;
List<String> _strList(Object? v) => v is List ? v.whereType<String>().toList() : [];

String _extractUsername(Map<String, dynamic> j) => _s(j['username']) != '' ? _s(j['username']) : _s(j['display_name']);

// ---------------------------------------------------------------------------
// Stories
// ---------------------------------------------------------------------------

enum StoryKind { text, photo, video, image }
enum StoryPrivacy { everyone, contacts, followers, closeFriends, custom }

StoryKind _storyKind(String s) {
  switch (s) {
    case 'video': return StoryKind.video;
    case 'photo': case 'image': return StoryKind.photo;
    default: return StoryKind.text;
  }
}
StoryPrivacy _storyPrivacy(String s) {
  switch (s) {
    case 'everyone': case 'everyone_public': return StoryPrivacy.everyone;
    case 'followers': return StoryPrivacy.followers;
    case 'close_friends': return StoryPrivacy.closeFriends;
    case 'custom': return StoryPrivacy.custom;
    default: return StoryPrivacy.contacts;
  }
}
String _storyPrivacyToDb(StoryPrivacy p) {
  switch (p) {
    case StoryPrivacy.everyone: return 'everyone';
    case StoryPrivacy.contacts: return 'contacts';
    case StoryPrivacy.followers: return 'followers';
    case StoryPrivacy.closeFriends: return 'close_friends';
    case StoryPrivacy.custom: return 'custom';
  }
}

class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.privacy,
    required this.createdAt,
    required this.expiresAt,
    this.body,
    this.caption,
    this.mediaPath,
    this.background,
    this.backgroundColor,
    this.textColor,
    this.textElements = const [],
    this.stickers = const [],
    this.linkUrl,
    this.musicUrl,
    this.pollId,
    this.viewCount = 0,
    this.isHighlight = false,
    this.author,
    this.hiddenAt,
  });

  final String id;
  final String authorId;
  final StoryKind kind;
  final StoryPrivacy privacy;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? hiddenAt;
  final String? body;
  final String? caption;
  final String? mediaPath;
  final String? background;
  final String? backgroundColor;
  final String? textColor;
  final List<Map<String, dynamic>> textElements;
  final List<Map<String, dynamic>> stickers;
  final String? linkUrl;
  final String? musicUrl;
  final String? pollId;
  final int viewCount;
  final bool isHighlight;
  final StoryAuthor? author;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isText => kind == StoryKind.text;
  String get privacyLabel {
    switch (privacy) {
      case StoryPrivacy.everyone: return 'Everyone';
      case StoryPrivacy.contacts: return 'Contacts';
      case StoryPrivacy.followers: return 'Followers';
      case StoryPrivacy.closeFriends: return 'Close Friends';
      case StoryPrivacy.custom: return 'Custom';
    }
  }

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: _s(j['id']),
        authorId: _s(j['author_id']),
        kind: _storyKind(_s(j['kind'], 'text')),
        privacy: _storyPrivacy(_s(j['privacy'], 'contacts')),
        body: j['body'] as String?,
        caption: j['caption'] as String?,
        mediaPath: j['media_path'] as String?,
        background: j['background'] as String?,
        backgroundColor: j['background_color'] as String?,
        textColor: j['text_color'] as String?,
        textElements: (j['text_elements'] is List) ? (j['text_elements'] as List).whereType<Map<String, dynamic>>().toList() : [],
        stickers: (j['stickers'] is List) ? (j['stickers'] as List).whereType<Map<String, dynamic>>().toList() : [],
        linkUrl: j['link_url'] as String?,
        musicUrl: j['music_url'] as String?,
        pollId: j['poll_id'] as String?,
        viewCount: _i(j['view_count']),
        isHighlight: _b(j['is_highlight']),
        createdAt: _d(j['created_at']),
        expiresAt: _d(j['expires_at']),
        hiddenAt: _d(j['hidden_at']),
        author: j['author'] is Map ? StoryAuthor.fromJson(j['author'] as Map<String, dynamic>) : (j['profiles'] is Map ? StoryAuthor.fromJson(j['profiles'] as Map<String, dynamic>) : null),
      );

  Map<String, dynamic> toCreateJson() => {
        'kind': kind == StoryKind.video ? 'video' : (kind == StoryKind.photo ? 'photo' : 'text'),
        'privacy': _storyPrivacyToDb(privacy),
        if (body != null) 'body': body,
        if (caption != null) 'caption': caption,
        if (mediaPath != null) 'media_path': mediaPath,
        if (background != null) 'background': background,
        if (backgroundColor != null) 'background_color': backgroundColor,
        if (textColor != null) 'text_color': textColor,
        'text_elements': textElements,
        'stickers': stickers,
        if (linkUrl != null) 'link_url': linkUrl,
        if (musicUrl != null) 'music_url': musicUrl,
        if (pollId != null) 'poll_id': pollId,
      };
}

class StoryAuthor {
  const StoryAuthor({required this.id, required this.username, required this.displayName, this.avatarUrl, this.isVerified = false, this.isPartner = false});
  final String id; final String username; final String displayName; final String? avatarUrl; final bool isVerified; final bool isPartner;
  factory StoryAuthor.fromJson(Map<String, dynamic> j) => StoryAuthor(
        id: _s(j['id']),
        username: _s(j['username']),
        displayName: _s(j['display_name'], _s(j['username'])),
        avatarUrl: j['avatar_url'] as String?,
        isVerified: _b(j['is_verified']),
        isPartner: _b(j['is_partner']),
      );
}

class StoryViewer {
  const StoryViewer({required this.storyId, required this.viewerId, required this.viewedAt, this.viewer});
  final String storyId; final String viewerId; final DateTime? viewedAt; final StoryAuthor? viewer;
  factory StoryViewer.fromJson(Map<String, dynamic> j) => StoryViewer(
        storyId: _s(j['story_id']),
        viewerId: _s(j['viewer_id']),
        viewedAt: _d(j['viewed_at']),
        viewer: j['viewer'] is Map ? StoryAuthor.fromJson(j['viewer'] as Map<String, dynamic>) : null,
      );
}

class StoryInsight {
  const StoryInsight({required this.storyId, required this.viewCount, required this.reactions, required this.replies, this.viewers = const []});
  final String storyId; final int viewCount; final int reactions; final int replies; final List<StoryViewer> viewers;
}

// ---------------------------------------------------------------------------
// Communities
// ---------------------------------------------------------------------------

enum CommunityVisibility { public, private }
enum CommunityRole { owner, admin, moderator, groupManager, member }

CommunityRole _communityRole(String s) {
  switch (s) { case 'owner': return CommunityRole.owner; case 'admin': return CommunityRole.admin; case 'moderator': return CommunityRole.moderator; case 'group_manager': return CommunityRole.groupManager; default: return CommunityRole.member; }
}
String _communityRoleDb(CommunityRole r) {
  switch (r) { case CommunityRole.owner: return 'owner'; case CommunityRole.admin: return 'admin'; case CommunityRole.moderator: return 'moderator'; case CommunityRole.groupManager: return 'group_manager'; case CommunityRole.member: return 'member'; }
}

class Community {
  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.ownerId,
    this.username,
    this.slug,
    this.category,
    this.rules,
    this.avatarUrl,
    this.coverUrl,
    this.joinApproval = false,
    this.allowInvites = true,
    this.memberCount = 0,
    this.conversationId,
    this.createdAt,
    this.myRole,
    this.isMember = false,
  });
  final String id; final String name; final String description; final CommunityVisibility visibility;
  final String ownerId; final String? username; final String? slug; final String? category; final String? rules;
  final String? avatarUrl; final String? coverUrl; final bool joinApproval; final bool allowInvites; final int memberCount;
  final String? conversationId; final DateTime? createdAt; final CommunityRole? myRole; final bool isMember;
  bool get isOwner => myRole == CommunityRole.owner;
  bool get isAdmin => myRole == CommunityRole.admin || isOwner;
  factory Community.fromJson(Map<String, dynamic> j) => Community(
        id: _s(j['id']),
        name: _s(j['name']),
        description: _s(j['description']),
        visibility: _s(j['visibility']) == 'public' ? CommunityVisibility.public : CommunityVisibility.private,
        ownerId: _s(j['owner_id']),
        username: j['username'] as String?,
        slug: j['slug'] as String?,
        category: j['category'] as String?,
        rules: j['rules'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        coverUrl: j['cover_url'] as String?,
        joinApproval: _b(j['join_approval']),
        allowInvites: j['allow_invites'] == null ? true : _b(j['allow_invites']),
        memberCount: _i(j['member_count']),
        conversationId: j['conversation_id'] as String?,
        createdAt: _d(j['created_at']),
        isMember: _b(j['is_member']),
        myRole: j['my_role'] is String ? _communityRole(j['my_role'] as String) : null,
      );
}

class CommunityMember {
  const CommunityMember({required this.communityId, required this.userId, required this.role, required this.joinedAt, this.profile});
  final String communityId; final String userId; final CommunityRole role; final DateTime? joinedAt; final StoryAuthor? profile;
  factory CommunityMember.fromJson(Map<String, dynamic> j) => CommunityMember(
        communityId: _s(j['community_id']),
        userId: _s(j['user_id']),
        role: _communityRole(_s(j['role'], 'member')),
        joinedAt: _d(j['joined_at']),
        profile: j['profile'] is Map ? StoryAuthor.fromJson(j['profile'] as Map<String, dynamic>) : null,
      );
}

class CommunityJoinRequest {
  const CommunityJoinRequest({required this.id, required this.communityId, required this.userId, required this.status, this.message, this.createdAt, this.profile});
  final String id; final String communityId; final String userId; final String status; final String? message; final DateTime? createdAt; final StoryAuthor? profile;
  bool get isPending => status == 'pending';
  factory CommunityJoinRequest.fromJson(Map<String, dynamic> j) => CommunityJoinRequest(
        id: _s(j['id']),
        communityId: _s(j['community_id']),
        userId: _s(j['user_id']),
        status: _s(j['status'], 'pending'),
        message: j['message'] as String?,
        createdAt: _d(j['created_at']),
        profile: j['profile'] is Map ? StoryAuthor.fromJson(j['profile'] as Map<String, dynamic>) : null,
      );
}

class CommunityGroup {
  const CommunityGroup({required this.id, required this.communityId, required this.conversationId, required this.title, this.description, this.createdAt});
  final String id; final String communityId; final String conversationId; final String title; final String? description; final DateTime? createdAt;
  factory CommunityGroup.fromJson(Map<String, dynamic> j) => CommunityGroup(
        id: _s(j['id']), communityId: _s(j['community_id']), conversationId: _s(j['conversation_id']), title: _s(j['title']), description: j['description'] as String?, createdAt: _d(j['created_at']));
}

// ---------------------------------------------------------------------------
// Posts / Feed
// ---------------------------------------------------------------------------

enum PostKind { text, image, images, video, poll, link, shareChannel, shareStory }
enum PostVisibility { public, followers, contacts, private }

PostKind _postKind(String s) {
  switch (s) { case 'image': return PostKind.image; case 'images': return PostKind.images; case 'video': return PostKind.video; case 'poll': return PostKind.poll; case 'link': return PostKind.link; case 'share_channel': return PostKind.shareChannel; case 'share_story': return PostKind.shareStory; default: return PostKind.text; }
}
PostVisibility _postVisibility(String s) {
  switch (s) { case 'followers': return PostVisibility.followers; case 'contacts': return PostVisibility.contacts; case 'private': return PostVisibility.private; default: return PostVisibility.public; }
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.visibility,
    required this.createdAt,
    this.body,
    this.mediaPaths = const [],
    this.linkUrl,
    this.linkPreview,
    this.pollId,
    this.communityId,
    this.conversationId,
    this.sharedPostId,
    this.sharedChannelPostId,
    this.isPinned = false,
    this.isEdited = false,
    this.author,
    this.reactionCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.myReaction,
    this.isBookmarked = false,
    this.updatedAt,
  });
  final String id; final String authorId; final PostKind kind; final PostVisibility visibility;
  final String? body; final List<String> mediaPaths; final String? linkUrl; final Map<String, dynamic>? linkPreview;
  final String? pollId; final String? communityId; final String? conversationId; final String? sharedPostId; final String? sharedChannelPostId;
  final bool isPinned; final bool isEdited; final DateTime? createdAt; final DateTime? updatedAt;
  final StoryAuthor? author; final int reactionCount; final int commentCount; final int viewCount; final String? myReaction; final bool isBookmarked;
  bool get hasMedia => mediaPaths.isNotEmpty;
  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: _s(j['id']),
        authorId: _s(j['author_id']),
        kind: _postKind(_s(j['kind'], 'text')),
        visibility: _postVisibility(_s(j['visibility'], 'public')),
        body: j['body'] as String?,
        mediaPaths: _strList(j['media_paths']),
        linkUrl: j['link_url'] as String?,
        linkPreview: j['link_preview'] is Map ? Map<String, dynamic>.from(j['link_preview'] as Map) : null,
        pollId: j['poll_id'] as String?,
        communityId: j['community_id'] as String?,
        conversationId: j['conversation_id'] as String?,
        sharedPostId: j['shared_post_id'] as String?,
        sharedChannelPostId: j['shared_channel_post_id'] as String?,
        isPinned: _b(j['is_pinned']),
        isEdited: _b(j['is_edited']),
        createdAt: _d(j['created_at']),
        updatedAt: _d(j['updated_at']),
        author: j['author'] is Map ? StoryAuthor.fromJson(j['author'] as Map<String, dynamic>) : (j['profiles'] is Map ? StoryAuthor.fromJson(j['profiles'] as Map<String, dynamic>) : null),
        reactionCount: _i(j['reaction_count']),
        commentCount: _i(j['comment_count']),
        viewCount: _i(j['view_count']),
        myReaction: j['my_reaction'] as String?,
        isBookmarked: _b(j['is_bookmarked']),
      );
}

class Comment {
  const Comment({required this.id, required this.postId, required this.authorId, required this.body, required this.depth, required this.createdAt, this.parentId, this.isEdited = false, this.author, this.reactionCount = 0, this.myReaction, this.updatedAt});
  final String id; final String postId; final String? parentId; final String authorId; final String body; final int depth; final bool isEdited; final DateTime? createdAt; final DateTime? updatedAt; final StoryAuthor? author; final int reactionCount; final String? myReaction;
  bool get isReply => parentId != null;
  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: _s(j['id']),
        postId: _s(j['post_id']),
        parentId: j['parent_id'] as String?,
        authorId: _s(j['author_id']),
        body: _s(j['body']),
        depth: _i(j['depth']),
        isEdited: _b(j['is_edited']),
        createdAt: _d(j['created_at']),
        updatedAt: _d(j['updated_at']),
        author: j['author'] is Map ? StoryAuthor.fromJson(j['author'] as Map<String, dynamic>) : null,
        reactionCount: _i(j['reaction_count']),
        myReaction: j['my_reaction'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Polls
// ---------------------------------------------------------------------------

class Poll {
  const Poll({required this.id, required this.authorId, required this.question, required this.options, this.allowMultiple = false, this.allowAnonymous = false, this.allowChange = true, this.expiresAt, this.createdAt, this.totalVotes = 0, this.myVotes = const []});
  final String id; final String authorId; final String question; final List<PollOption> options;
  final bool allowMultiple; final bool allowAnonymous; final bool allowChange; final DateTime? expiresAt; final DateTime? createdAt; final int totalVotes; final List<String> myVotes;
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        id: _s(j['id']),
        authorId: _s(j['author_id']),
        question: _s(j['question']),
        allowMultiple: _b(j['allow_multiple']),
        allowAnonymous: _b(j['allow_anonymous']),
        allowChange: j['allow_change'] == null ? true : _b(j['allow_change']),
        expiresAt: _d(j['expires_at']),
        createdAt: _d(j['created_at']),
        totalVotes: _i(j['total_votes']),
        myVotes: _strList(j['my_votes']),
        options: (j['options'] is List ? (j['options'] as List).whereType<Map<String, dynamic>>().map(PollOption.fromJson).toList() : []),
      );
}

class PollOption {
  const PollOption({required this.id, required this.pollId, required this.label, required this.sortOrder, this.voteCount = 0});
  final String id; final String pollId; final String label; final int sortOrder; final int voteCount;
  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
        id: _s(j['id']), pollId: _s(j['poll_id']), label: _s(j['label']), sortOrder: _i(j['sort_order']), voteCount: _i(j['vote_count']),
      );
}

// ---------------------------------------------------------------------------
// Hashtags & Mentions
// ---------------------------------------------------------------------------

class Hashtag {
  const Hashtag({required this.tag, required this.postCount, this.updatedAt});
  final String tag; final int postCount; final DateTime? updatedAt;
  factory Hashtag.fromJson(Map<String, dynamic> j) => Hashtag(tag: _s(j['tag']), postCount: _i(j['post_count']), updatedAt: _d(j['updated_at']));
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

class GroupSettings {
  const GroupSettings({
    required this.conversationId,
    this.allowSendMessages = true,
    this.allowSendMedia = true,
    this.allowAddMembers = true,
    this.allowChangeInfo = false,
    this.allowPinMessages = true,
    this.allowCreatePolls = true,
    this.allowStartCalls = true,
    this.allowManageInvites = true,
    this.requireApproval = false,
    this.inviteLink,
  });
  final String conversationId; final bool allowSendMessages; final bool allowSendMedia; final bool allowAddMembers; final bool allowChangeInfo; final bool allowPinMessages; final bool allowCreatePolls; final bool allowStartCalls; final bool allowManageInvites; final bool requireApproval; final String? inviteLink;
  factory GroupSettings.fromJson(Map<String, dynamic> j) => GroupSettings(
        conversationId: _s(j['conversation_id']),
        allowSendMessages: j['allow_send_messages'] == null ? true : _b(j['allow_send_messages']),
        allowSendMedia: j['allow_send_media'] == null ? true : _b(j['allow_send_media']),
        allowAddMembers: j['allow_add_members'] == null ? true : _b(j['allow_add_members']),
        allowChangeInfo: _b(j['allow_change_info']),
        allowPinMessages: j['allow_pin_messages'] == null ? true : _b(j['allow_pin_messages']),
        allowCreatePolls: j['allow_create_polls'] == null ? true : _b(j['allow_create_polls']),
        allowStartCalls: j['allow_start_calls'] == null ? true : _b(j['allow_start_calls']),
        allowManageInvites: j['allow_manage_invites'] == null ? true : _b(j['allow_manage_invites']),
        requireApproval: _b(j['require_approval']),
        inviteLink: j['invite_link'] as String?,
      );
}

class GroupInvite {
  const GroupInvite({required this.id, required this.conversationId, required this.code, this.maxUses, this.uses = 0, this.expiresAt, this.revokedAt, this.createdAt});
  final String id; final String conversationId; final String code; final int? maxUses; final int uses; final DateTime? expiresAt; final DateTime? revokedAt; final DateTime? createdAt;
  bool get isRevoked => revokedAt != null;
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  factory GroupInvite.fromJson(Map<String, dynamic> j) => GroupInvite(id: _s(j['id']), conversationId: _s(j['conversation_id']), code: _s(j['code']), maxUses: j['max_uses'] as int?, uses: _i(j['uses']), expiresAt: _d(j['expires_at']), revokedAt: _d(j['revoked_at']), createdAt: _d(j['created_at']));
}

// ---------------------------------------------------------------------------
// Search & Discovery
// ---------------------------------------------------------------------------

class SearchResult {
  const SearchResult({this.users = const [], this.channels = const [], this.communities = const [], this.posts = const []});
  final List<StoryAuthor> users; final List<Map<String,dynamic>> channels; final List<Map<String,dynamic>> communities; final List<Map<String,dynamic>> posts;
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        users: (j['users'] is List ? (j['users'] as List).whereType<Map<String,dynamic>>().map(StoryAuthor.fromJson).toList() : []),
        channels: (j['channels'] is List ? (j['channels'] as List).whereType<Map<String,dynamic>>().toList() : []),
        communities: (j['communities'] is List ? (j['communities'] as List).whereType<Map<String,dynamic>>().toList() : []),
        posts: (j['posts'] is List ? (j['posts'] as List).whereType<Map<String,dynamic>>().toList() : []),
      );
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

class Report {
  const Report({required this.id, required this.reporterId, required this.targetType, required this.targetId, required this.reason, required this.status, this.details, this.category, this.createdAt});
  final String id; final String reporterId; final String targetType; final String targetId; final String reason; final String? category; final String status; final String? details; final DateTime? createdAt;
  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: _s(j['id']), reporterId: _s(j['reporter_id']), targetType: _s(j['target_type']), targetId: _s(j['target_id']), reason: _s(j['reason']), category: j['category'] as String?, status: _s(j['status'], 'open'), details: j['details'] as String?, createdAt: _d(j['created_at']));
}
