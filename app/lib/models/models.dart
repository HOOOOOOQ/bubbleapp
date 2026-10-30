/// Plain data models mirroring the Supabase tables and RPC payloads.
/// Parsing is defensive: unknown or missing fields never crash the UI.

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _bool(Object? v) => v == true;
int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.accountStatus,
    required this.isVerified,
    this.avatarUrl,
    this.coverUrl,
    this.email,
    this.verifiedAt,
    this.lastSeenAt,
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String accountStatus;
  final bool isVerified;
  final String? avatarUrl;
  final String? coverUrl;
  final String? email;
  final DateTime? verifiedAt;
  final DateTime? lastSeenAt;

  /// Usernames assigned automatically at signup start with "user_" until the user chooses one.
  bool get needsProfileSetup => username.startsWith('user_');

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: _str(json['id']),
        username: _str(json['username']),
        displayName: _str(json['display_name']),
        bio: _str(json['bio']),
        accountStatus: _str(json['account_status'], 'active'),
        isVerified: _bool(json['is_verified']),
        avatarUrl: json['avatar_url'] as String?,
        coverUrl: json['cover_url'] as String?,
        email: json['email'] as String?,
        verifiedAt: _date(json['verified_at']),
        lastSeenAt: _date(json['last_seen_at']),
      );
}

class ChannelModel {
  const ChannelModel({
    required this.id,
    required this.name,
    required this.username,
    required this.description,
    required this.isPublic,
    required this.isVerified,
    required this.isOfficial,
    required this.isMandatory,
    required this.subscriberCount,
    this.ownerId,
    this.avatarUrl,
    this.coverUrl,
    this.commentsEnabled = false,
  });

  final String id;
  final String name;
  final String username;
  final String description;
  final bool isPublic;
  final bool isVerified;
  final bool isOfficial;
  final bool isMandatory;
  final int subscriberCount;
  final String? ownerId;
  final String? avatarUrl;
  final String? coverUrl;
  final bool commentsEnabled;

  factory ChannelModel.fromJson(Map<String, dynamic> json) => ChannelModel(
        id: _str(json['id']),
        name: _str(json['name']),
        username: _str(json['username']),
        description: _str(json['description']),
        isPublic: json['is_public'] != false,
        isVerified: _bool(json['is_verified']),
        isOfficial: _bool(json['is_official']),
        isMandatory: _bool(json['is_mandatory']),
        subscriberCount: _int(json['subscriber_count']),
        ownerId: json['owner_id'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        coverUrl: json['cover_url'] as String?,
        commentsEnabled: _bool(json['comments_enabled']),
      );
}

class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.channelId,
    required this.kind,
    required this.isPinned,
    required this.viewsCount,
    required this.publishAt,
    this.body,
    this.mediaPath,
  });

  final String id;
  final String channelId;
  final String kind;
  final bool isPinned;
  final int viewsCount;
  final DateTime? publishAt;
  final String? body;
  final String? mediaPath;

  factory ChannelPost.fromJson(Map<String, dynamic> json) => ChannelPost(
        id: _str(json['id']),
        channelId: _str(json['channel_id']),
        kind: _str(json['kind'], 'text'),
        isPinned: _bool(json['is_pinned']),
        viewsCount: _int(json['views_count']),
        publishAt: _date(json['publish_at']),
        body: json['body'] as String?,
        mediaPath: json['media_path'] as String?,
      );
}

class VerificationApplication {
  const VerificationApplication({
    required this.id,
    required this.applicantId,
    required this.applicationType,
    required this.status,
    required this.fullName,
    required this.category,
    required this.reason,
    required this.submittedAt,
    this.username,
    this.decisionNote,
    this.recommendation,
    this.businessId,
    this.channelId,
  });

  final String id;
  final String applicantId;
  final String applicationType;
  final String status;
  final String fullName;
  final String category;
  final String reason;
  final DateTime? submittedAt;
  final String? username;
  final String? decisionNote;
  final String? recommendation;
  final String? businessId;
  final String? channelId;

  bool get isOpen => const {'pending', 'under_review', 'info_requested'}.contains(status);

  factory VerificationApplication.fromJson(Map<String, dynamic> json) => VerificationApplication(
        id: _str(json['id']),
        applicantId: _str(json['applicant_id']),
        applicationType: _str(json['application_type'], 'user'),
        status: _str(json['status'], 'pending'),
        fullName: _str(json['full_name']),
        category: _str(json['category']),
        reason: _str(json['reason']),
        submittedAt: _date(json['submitted_at']),
        username: json['username'] as String?,
        decisionNote: json['decision_note'] as String?,
        recommendation: json['recommendation'] as String?,
        businessId: json['business_id'] as String?,
        channelId: json['channel_id'] as String?,
      );
}

class PartnerApplication {
  const PartnerApplication({
    required this.id,
    required this.status,
    required this.organization,
    required this.partnershipCategory,
    required this.createdAt,
    required this.fullName,
    this.decisionNote,
  });

  final String id;
  final String status;
  final String organization;
  final String partnershipCategory;
  final DateTime? createdAt;
  final String fullName;
  final String? decisionNote;

  factory PartnerApplication.fromJson(Map<String, dynamic> json) => PartnerApplication(
        id: _str(json['id']),
        status: _str(json['status'], 'pending'),
        organization: _str(json['organization']),
        partnershipCategory: _str(json['partnership_category']),
        createdAt: _date(json['created_at']),
        fullName: _str(json['full_name']),
        decisionNote: json['decision_note'] as String?,
      );
}

class PartnerDashboard {
  const PartnerDashboard({
    required this.status,
    required this.category,
    required this.displayName,
    required this.announcementCount,
    required this.permissions,
    this.statusReason,
  });

  final String status;
  final String category;
  final String displayName;
  final int announcementCount;
  final List<String> permissions;
  final String? statusReason;

  factory PartnerDashboard.fromJson(Map<String, dynamic> json) => PartnerDashboard(
        status: _str(json['partner_status'], 'active'),
        category: _str(json['partner_category']),
        displayName: _str(json['display_name']),
        announcementCount: _int(json['announcements']),
        permissions: (json['permissions'] as List? ?? const []).whereType<String>().toList(),
        statusReason: json['status_reason'] as String?,
      );
}

/// Effective access of the signed-in account, computed by the database (my_access()).
/// The UI uses it only to choose which panels to show; every action is re-checked server-side.
class AccessSnapshot {
  const AccessSnapshot({
    required this.isOwner,
    required this.isAdmin,
    required this.permissions,
    required this.partnerPermissions,
    required this.roles,
    required this.rank,
  });

  final bool isOwner;
  final bool isAdmin;
  final Set<String> permissions;
  final Set<String> partnerPermissions;
  final List<String> roles;
  final int rank;

  static const empty = AccessSnapshot(
    isOwner: false,
    isAdmin: false,
    permissions: {},
    partnerPermissions: {},
    roles: [],
    rank: 0,
  );

  bool can(String permission) => isOwner || permissions.contains(permission);

  factory AccessSnapshot.fromJson(Map<String, dynamic> json) => AccessSnapshot(
        isOwner: _bool(json['is_owner']),
        isAdmin: _bool(json['is_admin']),
        permissions: (json['permissions'] as List? ?? const []).whereType<String>().toSet(),
        partnerPermissions: (json['partner_permissions'] as List? ?? const []).whereType<String>().toSet(),
        roles: (json['roles'] as List? ?? const []).whereType<String>().toList(),
        rank: _int(json['rank']),
      );
}

class OwnerStats {
  const OwnerStats(this.values);

  final Map<String, dynamic> values;

  int get(String key) => _int(values[key]);

  factory OwnerStats.fromJson(Map<String, dynamic> json) => OwnerStats(json);
}

class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.username,
    required this.category,
    required this.isVerified,
    required this.isSetupComplete,
    required this.description,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String username;
  final String category;
  final bool isVerified;
  final bool isSetupComplete;
  final String description;
  final String? logoUrl;

  factory BusinessSummary.fromJson(Map<String, dynamic> json) => BusinessSummary(
        id: _str(json['id']),
        name: _str(json['name']),
        username: _str(json['username']),
        category: _str(json['category']),
        isVerified: _bool(json['is_verified']),
        isSetupComplete: _bool(json['is_setup_complete']),
        description: _str(json['description']),
        logoUrl: json['logo_url'] as String?,
      );
}
