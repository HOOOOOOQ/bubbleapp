/// Part 8 models: business ecosystem, customer inbox and partner program.
///
/// Every class here parses the exact JSON returned by the RPCs in
/// `20261030000016_business_partner_ecosystem.sql`. Nothing in this file grants
/// permission: `permissions`, `can_manage` and `owner_only` are computed by the
/// database and are only used to decide which controls to render.
library;

String _str(Object? v) => v is String ? v : (v?.toString() ?? '');

String? _optStr(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

int? _optInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _optDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

bool _bool(Object? v) => v == true || v == 'true' || v == 1;

DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

List<String> _strings(Object? v) =>
    v is List ? v.whereType<Object>().map((e) => e.toString()).toList() : const <String>[];

Map<String, dynamic> _obj(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, value) => MapEntry(k.toString(), value));
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _objList(Object? v) =>
    v is List ? v.whereType<Object>().map((e) => _obj(e)).toList() : const <Map<String, dynamic>>[];

// ---------------------------------------------------------------- account mode

enum AccountMode {
  personal('Personal'),
  business('Business');

  const AccountMode(this.label);
  final String label;

  static AccountMode parse(Object? raw) =>
      raw == 'business' ? AccountMode.business : AccountMode.personal;
}

/// `user_settings.active_account_mode` + `active_business_id` as exposed to the
/// signed-in user. The server is the only writer (switch_account_mode).
class ActiveAccountMode {
  const ActiveAccountMode({required this.mode, this.businessId});

  final AccountMode mode;
  final String? businessId;

  bool get isBusiness => mode == AccountMode.business && businessId != null;

  static const personal = ActiveAccountMode(mode: AccountMode.personal);

  factory ActiveAccountMode.fromJson(Map<String, dynamic> json) => ActiveAccountMode(
        mode: AccountMode.parse(json['active_account_mode']),
        businessId: _optStr(json['active_business_id']),
      );
}

// ---------------------------------------------------------------- business

class BusinessPermission {
  const BusinessPermission({
    required this.key,
    required this.label,
    required this.category,
    required this.description,
    required this.ownerOnly,
  });

  final String key;
  final String label;
  final String category;
  final String description;
  final bool ownerOnly;

  factory BusinessPermission.fromJson(Map<String, dynamic> json) => BusinessPermission(
        key: _str(json['key']),
        label: _str(json['label']),
        category: _str(json['category']),
        description: _str(json['description']),
        ownerOnly: _bool(json['owner_only']),
      );
}

/// One row of `business_my_businesses()`.
class BusinessMembership {
  const BusinessMembership({
    required this.id,
    required this.name,
    required this.username,
    required this.category,
    required this.role,
    required this.status,
    required this.permissions,
    required this.isVerified,
    required this.isSetupComplete,
    required this.memberStatus,
    required this.openInquiries,
    required this.followersCount,
    required this.pendingInvites,
    required this.description,
    this.logoUrl,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String username;
  final String category;
  final String role;
  final String status;
  final Set<String> permissions;
  final bool isVerified;
  final bool isSetupComplete;
  final String memberStatus;
  final int openInquiries;
  final int followersCount;
  final int pendingInvites;
  final String description;
  final String? logoUrl;
  final String? coverUrl;

  bool get isOwner => role == 'owner';
  bool can(String permission) => isOwner || permissions.contains(permission);

  factory BusinessMembership.fromJson(Map<String, dynamic> json) => BusinessMembership(
        id: _str(json['id']),
        name: _str(json['name']),
        username: _str(json['username']),
        category: _str(json['category']),
        role: _str(json['role']),
        status: _str(json['status']),
        permissions: _strings(json['permissions']).toSet(),
        isVerified: _bool(json['is_verified']),
        isSetupComplete: _bool(json['is_setup_complete']),
        memberStatus: _str(json['member_status']),
        openInquiries: _int(json['open_inquiries']),
        followersCount: _int(json['followers_count']),
        pendingInvites: _int(json['pending_invites']),
        description: _str(json['description']),
        logoUrl: _optStr(json['logo_url']),
        coverUrl: _optStr(json['cover_url']),
      );
}

class BusinessProfile {
  const BusinessProfile({
    required this.id,
    required this.name,
    required this.username,
    required this.description,
    required this.category,
    required this.status,
    required this.isVerified,
    required this.isSetupComplete,
    required this.isMember,
    required this.isFollowing,
    required this.followersCount,
    required this.catalogCount,
    required this.acceptsInquiries,
    required this.myRole,
    required this.myPermissions,
    this.logoUrl,
    this.coverUrl,
    this.website,
    this.businessEmail,
    this.businessPhone,
    this.address,
    this.location,
    this.responseNote,
    this.verifiedAt,
    this.memberSince,
    this.workingHours = const {},
    this.socialLinks = const {},
    this.visibility = const {},
  });

  final String id;
  final String name;
  final String username;
  final String description;
  final String category;
  final String status;
  final bool isVerified;
  final bool isSetupComplete;
  final bool isMember;
  final bool isFollowing;
  final int followersCount;
  final int catalogCount;
  final bool acceptsInquiries;
  final String myRole;
  final Set<String> myPermissions;
  final String? logoUrl;
  final String? coverUrl;
  final String? website;
  final String? businessEmail;
  final String? businessPhone;
  final String? address;
  final String? location;
  final String? responseNote;
  final DateTime? verifiedAt;
  final DateTime? memberSince;
  final Map<String, dynamic> workingHours;
  final Map<String, dynamic> socialLinks;
  final Map<String, dynamic> visibility;

  bool can(String permission) => myRole == 'owner' || myPermissions.contains(permission);
  bool get showEmail => _bool(visibility['show_email'] ?? true);
  bool get showPhone => _bool(visibility['show_phone']);

  factory BusinessProfile.fromJson(Map<String, dynamic> json) => BusinessProfile(
        id: _str(json['id']),
        name: _str(json['name']),
        username: _str(json['username']),
        description: _str(json['description']),
        category: _str(json['category']),
        status: _str(json['status']),
        isVerified: _bool(json['is_verified']),
        isSetupComplete: _bool(json['is_setup_complete']),
        isMember: _bool(json['is_member']),
        isFollowing: _bool(json['is_following']),
        followersCount: _int(json['followers_count']),
        catalogCount: _int(json['catalog_count']),
        acceptsInquiries: _bool(json['accepts_inquiries'] ?? true),
        myRole: _str(json['my_role']),
        myPermissions: _strings(json['my_permissions']).toSet(),
        logoUrl: _optStr(json['logo_url']),
        coverUrl: _optStr(json['cover_url']),
        website: _optStr(json['website']),
        businessEmail: _optStr(json['contact_email'] ?? json['business_email']),
        businessPhone: _optStr(json['contact_phone'] ?? json['business_phone']),
        address: _optStr(json['address']),
        location: _optStr(json['location']),
        responseNote: _optStr(json['response_note']),
        verifiedAt: _date(json['verified_at']),
        memberSince: _date(json['member_since']),
        workingHours: _obj(json['working_hours']),
        socialLinks: _obj(json['social_links']),
        visibility: _obj(json['visibility']),
      );
}

class BusinessSetupProgress {
  const BusinessSetupProgress({
    required this.percent,
    required this.completed,
    required this.total,
    required this.missing,
    required this.isVerified,
    required this.status,
  });

  final int percent;
  final int completed;
  final int total;
  final List<String> missing;
  final bool isVerified;
  final String status;

  factory BusinessSetupProgress.fromJson(Map<String, dynamic> json) => BusinessSetupProgress(
        percent: _int(json['percent']),
        completed: _int(json['completed']),
        total: _int(json['total']),
        missing: _strings(json['missing']),
        isVerified: _bool(json['is_verified']),
        status: _str(json['status']),
      );
}

class BusinessTeamMember {
  const BusinessTeamMember({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.role,
    required this.status,
    required this.permissions,
    required this.isVerified,
    this.avatarUrl,
    this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String username;
  final String role;
  final String status;
  final Set<String> permissions;
  final bool isVerified;
  final String? avatarUrl;
  final DateTime? joinedAt;

  factory BusinessTeamMember.fromJson(Map<String, dynamic> json) => BusinessTeamMember(
        userId: _str(json['user_id']),
        displayName: _str(json['display_name']),
        username: _str(json['username']),
        role: _str(json['role']),
        status: _str(json['status']),
        permissions: _strings(json['permissions']).toSet(),
        isVerified: _bool(json['is_verified']),
        avatarUrl: _optStr(json['avatar_url']),
        joinedAt: _date(json['joined_at']),
      );
}

class BusinessTeamInvite {
  const BusinessTeamInvite({
    required this.id,
    required this.invitedUserId,
    required this.displayName,
    required this.username,
    required this.role,
    required this.status,
    this.note,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String invitedUserId;
  final String displayName;
  final String username;
  final String role;
  final String status;
  final String? note;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory BusinessTeamInvite.fromJson(Map<String, dynamic> json) => BusinessTeamInvite(
        id: _str(json['id']),
        invitedUserId: _str(json['invited_user_id']),
        displayName: _str(json['display_name']),
        username: _str(json['username']),
        role: _str(json['role']),
        status: _str(json['status']),
        note: _optStr(json['note']),
        expiresAt: _date(json['expires_at']),
        createdAt: _date(json['created_at']),
      );
}

class BusinessTeam {
  const BusinessTeam({
    required this.members,
    required this.invites,
    required this.canManage,
    required this.permissionCatalog,
  });

  final List<BusinessTeamMember> members;
  final List<BusinessTeamInvite> invites;
  final bool canManage;
  final List<BusinessPermission> permissionCatalog;

  factory BusinessTeam.fromJson(Map<String, dynamic> json) => BusinessTeam(
        members: _objList(json['members']).map(BusinessTeamMember.fromJson).toList(),
        invites: _objList(json['invites']).map(BusinessTeamInvite.fromJson).toList(),
        canManage: _bool(json['can_manage']),
        permissionCatalog:
            _objList(json['permission_catalog']).map(BusinessPermission.fromJson).toList(),
      );

  static const empty =
      BusinessTeam(members: [], invites: [], canManage: false, permissionCatalog: []);
}

/// Invitation addressed to the signed-in user (`my_business_invites`).
class BusinessInviteInboxItem {
  const BusinessInviteInboxItem({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.businessUsername,
    required this.role,
    required this.invitedByName,
    required this.businessVerified,
    required this.expiresAt,
    this.note,
    this.businessLogo,
    this.createdAt,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String businessUsername;
  final String role;
  final String invitedByName;
  final bool businessVerified;
  final DateTime? expiresAt;
  final String? note;
  final String? businessLogo;
  final DateTime? createdAt;

  factory BusinessInviteInboxItem.fromJson(Map<String, dynamic> json) => BusinessInviteInboxItem(
        id: _str(json['id']),
        businessId: _str(json['business_id']),
        businessName: _str(json['business_name']),
        businessUsername: _str(json['business_username']),
        role: _str(json['role']),
        invitedByName: _str(json['invited_by']),
        businessVerified: _bool(json['business_verified']),
        expiresAt: _date(json['expires_at']),
        note: _optStr(json['note']),
        businessLogo: _optStr(json['business_logo']),
        createdAt: _date(json['created_at']),
      );
}

// ---------------------------------------------------------------- catalog

class CatalogVariant {
  const CatalogVariant({required this.name, this.priceMinor});

  final String name;
  final int? priceMinor;

  factory CatalogVariant.fromJson(Map<String, dynamic> json) =>
      CatalogVariant(name: _str(json['name']), priceMinor: _optInt(json['price_minor']));

  Map<String, dynamic> toJson() => {
        'name': name,
        if (priceMinor != null) 'price_minor': priceMinor,
      };
}

class BusinessCatalogItem {
  const BusinessCatalogItem({
    required this.id,
    required this.businessId,
    required this.kind,
    required this.name,
    required this.description,
    required this.category,
    required this.currency,
    required this.status,
    required this.isActive,
    required this.gallery,
    required this.variants,
    required this.viewCount,
    required this.shareCount,
    this.priceMinor,
    this.stockQuantity,
    this.imageUrl,
    this.externalUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessId;
  final String kind;
  final String name;
  final String description;
  final String category;
  final String currency;
  final String status;
  final bool isActive;
  final List<String> gallery;
  final List<CatalogVariant> variants;
  final int viewCount;
  final int shareCount;
  final int? priceMinor;
  final int? stockQuantity;
  final String? imageUrl;
  final String? externalUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPublished => status == 'published';

  String? get priceLabel {
    if (priceMinor == null) return null;
    final unit = priceMinor! / 100;
    final text = unit == unit.roundToDouble() ? unit.toStringAsFixed(0) : unit.toStringAsFixed(2);
    return '$currency $text';
  }

  factory BusinessCatalogItem.fromJson(Map<String, dynamic> json) => BusinessCatalogItem(
        id: _str(json['id']),
        businessId: _str(json['business_id']),
        kind: _str(json['kind']),
        name: _str(json['name']),
        description: _str(json['description']),
        category: _str(json['category']),
        currency: _str(json['currency']).isEmpty ? 'IDR' : _str(json['currency']),
        status: _str(json['status']),
        isActive: _bool(json['is_active']),
        gallery: _strings(json['gallery']),
        variants: _objList(json['variants']).map(CatalogVariant.fromJson).toList(),
        viewCount: _int(json['view_count']),
        shareCount: _int(json['share_count']),
        priceMinor: _optInt(json['price_minor']),
        stockQuantity: _optInt(json['stock_quantity']),
        imageUrl: _optStr(json['image_url']),
        externalUrl: _optStr(json['external_url']),
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
      );
}

/// Editable catalog draft. `toParams()` mirrors the exact RPC argument names so
/// a rename in SQL fails loudly in the repository test instead of silently.
class CatalogDraft {
  CatalogDraft({
    this.itemId,
    this.kind = 'product',
    this.name = '',
    this.description = '',
    this.category,
    this.priceMinor,
    this.currency = 'IDR',
    this.imageUrl,
    this.gallery = const [],
    this.status = 'draft',
    this.stockQuantity,
    this.externalUrl,
    this.variants = const [],
  });

  final String? itemId;
  final String kind;
  final String name;
  final String description;
  final String? category;
  final int? priceMinor;
  final String currency;
  final String? imageUrl;
  final List<String> gallery;
  final String status;
  final int? stockQuantity;
  final String? externalUrl;
  final List<CatalogVariant> variants;

  factory CatalogDraft.fromItem(BusinessCatalogItem item) => CatalogDraft(
        itemId: item.id,
        kind: item.kind,
        name: item.name,
        description: item.description,
        category: item.category.isEmpty ? null : item.category,
        priceMinor: item.priceMinor,
        currency: item.currency,
        imageUrl: item.imageUrl,
        gallery: item.gallery,
        status: item.status,
        stockQuantity: item.stockQuantity,
        externalUrl: item.externalUrl,
        variants: item.variants,
      );

  Map<String, dynamic> toParams(String businessId) => {
        'p_business_id': businessId,
        'p_item_id': itemId,
        'p_kind': kind,
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_category': category,
        'p_price_minor': priceMinor,
        'p_currency': currency,
        'p_image_url': imageUrl,
        'p_gallery': gallery,
        'p_status': status,
        'p_stock_quantity': stockQuantity,
        'p_external_url': externalUrl,
        'p_variants': variants.map((v) => v.toJson()).toList(),
      };
}

class CatalogDetail {
  const CatalogDetail({required this.item, required this.canManage, required this.canMessage});

  final BusinessCatalogItem item;
  final bool canManage;
  final bool canMessage;

  factory CatalogDetail.fromJson(Map<String, dynamic> json) => CatalogDetail(
        item: BusinessCatalogItem.fromJson(json),
        canManage: _bool(json['can_manage']),
        canMessage: _bool(json['can_message']),
      );
}

// ---------------------------------------------------------------- analytics

class AnalyticsPoint {
  const AnalyticsPoint({
    required this.day,
    required this.profileViews,
    required this.catalogViews,
    required this.inquiries,
  });

  final String day;
  final int profileViews;
  final int catalogViews;
  final int inquiries;

  factory AnalyticsPoint.fromJson(Map<String, dynamic> json) => AnalyticsPoint(
        day: _str(json['day']),
        profileViews: _int(json['profile_views']),
        catalogViews: _int(json['catalog_views']),
        inquiries: _int(json['inquiries']),
      );
}

class ResponseStats {
  const ResponseStats({
    required this.available,
    required this.answered,
    required this.unanswered,
    this.avgFirstResponseMinutes,
    this.resolutionRate,
  });

  final bool available;
  final int answered;
  final int unanswered;
  final double? avgFirstResponseMinutes;
  final double? resolutionRate;

  factory ResponseStats.fromJson(Map<String, dynamic> json) => ResponseStats(
        available: _bool(json['available']),
        answered: _int(json['answered']),
        unanswered: _int(json['unanswered']),
        avgFirstResponseMinutes: _optDouble(json['avg_first_response_minutes']),
        resolutionRate: _optDouble(json['resolution_rate']),
      );

  factory ResponseStats.unavailable() =>
      const ResponseStats(available: false, answered: 0, unanswered: 0);
}

class BusinessAnalytics {
  const BusinessAnalytics({
    required this.periodDays,
    required this.metrics,
    required this.previous,
    required this.series,
    required this.response,
    required this.unavailable,
  });

  final int periodDays;
  final Map<String, num> metrics;
  final Map<String, num> previous;
  final List<AnalyticsPoint> series;
  final ResponseStats response;

  /// Metrics the platform genuinely does not collect yet. The UI must show why
  /// instead of fabricating numbers.
  final List<Map<String, dynamic>> unavailable;

  int metric(String key) => _int(metrics[key]);
  int previousMetric(String key) => _int(previous[key]);

  double? change(String key) {
    final prev = previousMetric(key);
    final now = metric(key);
    if (prev == 0) return now == 0 ? 0 : null;
    return ((now - prev) / prev) * 100;
  }

  factory BusinessAnalytics.fromJson(Map<String, dynamic> json) {
    final rawMetrics = _obj(json['metrics']);
    final rawPrevious = _obj(json['previous']);
    return BusinessAnalytics(
      periodDays: _int(json['period_days']),
      metrics: rawMetrics.map((k, v) => MapEntry(k, v is num ? v : _int(v))),
      previous: rawPrevious.map((k, v) => MapEntry(k, v is num ? v : _int(v))),
      series: _objList(json['series']).map(AnalyticsPoint.fromJson).toList(),
      response: ResponseStats.fromJson(_obj(json['response'])),
      unavailable: _objList(json['unavailable']),
    );
  }
}

// ---------------------------------------------------------------- inquiries

class BusinessInquiry {
  const BusinessInquiry({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.conversationId,
    required this.subject,
    required this.status,
    required this.priority,
    required this.messageCount,
    required this.canManage,
    required this.customerVerified,
    required this.customerName,
    required this.customerUsername,
    this.catalogItemId,
    this.catalogItemName,
    this.assignedTo,
    this.lastMessage,
    this.customerAvatar,
    this.lastMessageAt,
    this.firstResponseAt,
    this.resolvedAt,
    this.createdAt,
  });

  final String id;
  final String businessId;
  final String customerId;
  final String conversationId;
  final String subject;
  final String status;
  final String priority;
  final int messageCount;
  final bool canManage;
  final bool customerVerified;
  final String customerName;
  final String customerUsername;
  final String? catalogItemId;
  final String? catalogItemName;
  final String? assignedTo;
  final String? lastMessage;
  final String? customerAvatar;
  final DateTime? lastMessageAt;
  final DateTime? firstResponseAt;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  bool get isOpen => status == 'new' || status == 'open';

  factory BusinessInquiry.fromJson(Map<String, dynamic> json) => BusinessInquiry(
        id: _str(json['id']),
        businessId: _str(json['business_id']),
        customerId: _str(json['customer_id']),
        conversationId: _str(json['conversation_id']),
        subject: _str(json['subject']),
        status: _str(json['status']),
        priority: _str(json['priority']).isEmpty ? 'normal' : _str(json['priority']),
        messageCount: _int(json['message_count']),
        canManage: _bool(json['can_manage']),
        customerVerified: _bool(json['customer_verified']),
        customerName: _str(json['customer_name']),
        customerUsername: _str(json['customer_username']),
        catalogItemId: _optStr(json['catalog_item_id']),
        catalogItemName: _optStr(json['catalog_item_name']),
        assignedTo: _optStr(json['assigned_to']),
        lastMessage: _optStr(json['last_message']),
        customerAvatar: _optStr(json['customer_avatar']),
        lastMessageAt: _date(json['last_message_at']),
        firstResponseAt: _date(json['first_response_at']),
        resolvedAt: _date(json['resolved_at']),
        createdAt: _date(json['created_at']),
      );
}

class InquiryCustomerRecord {
  const InquiryCustomerRecord({
    required this.internalNote,
    required this.followUpStatus,
    required this.inquiryCount,
    required this.openInquiries,
    this.lastInteractionAt,
  });

  final String internalNote;
  final String followUpStatus;
  final int inquiryCount;
  final int openInquiries;
  final DateTime? lastInteractionAt;

  factory InquiryCustomerRecord.fromJson(Map<String, dynamic> json) => InquiryCustomerRecord(
        internalNote: _str(json['internal_note']),
        followUpStatus: _str(json['follow_up_status']),
        inquiryCount: _int(json['inquiry_count']),
        openInquiries: _int(json['open_inquiries']),
        lastInteractionAt: _date(json['last_interaction_at']),
      );
}

class BusinessInquiryDetail {
  const BusinessInquiryDetail({
    required this.inquiry,
    required this.canViewCustomer,
    required this.isCustomer,
    this.customerRecord,
  });

  final BusinessInquiry inquiry;
  final bool canViewCustomer;
  final bool isCustomer;
  final InquiryCustomerRecord? customerRecord;

  factory BusinessInquiryDetail.fromJson(Map<String, dynamic> json) {
    final record = json['customer_record'];
    return BusinessInquiryDetail(
      inquiry: BusinessInquiry.fromJson(json),
      canViewCustomer: _bool(json['can_view_customer']) || record is Map,
      isCustomer: _bool(json['is_customer']),
      customerRecord: record is Map ? InquiryCustomerRecord.fromJson(_obj(record)) : null,
    );
  }
}

class CustomerLabel {
  const CustomerLabel({
    required this.id,
    required this.name,
    required this.color,
    this.usage = 0,
  });

  final String id;
  final String name;
  final String color;

  /// How many customers currently carry this label (reported by business_label_list).
  final int usage;

  factory CustomerLabel.fromJson(Map<String, dynamic> json) => CustomerLabel(
        id: _str(json['id']),
        name: _str(json['name']),
        color: _str(json['color']).isEmpty ? '#2563EB' : _str(json['color']),
        usage: _int(json['usage']),
      );
}

class BusinessCustomer {
  const BusinessCustomer({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.displayName,
    required this.username,
    required this.isVerified,
    required this.internalNote,
    required this.followUpStatus,
    required this.inquiryCount,
    required this.openInquiries,
    required this.labels,
    this.avatarUrl,
    this.lastInteractionAt,
    this.lastMessageAt,
    this.createdAt,
  });

  final String id;
  final String businessId;
  final String userId;
  final String displayName;
  final String username;
  final bool isVerified;
  final String internalNote;
  final String followUpStatus;
  final int inquiryCount;
  final int openInquiries;
  final List<CustomerLabel> labels;
  final String? avatarUrl;
  final DateTime? lastInteractionAt;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  factory BusinessCustomer.fromJson(Map<String, dynamic> json) => BusinessCustomer(
        id: _str(json['id']),
        businessId: _str(json['business_id']),
        userId: _str(json['user_id']),
        displayName: _str(json['display_name']),
        username: _str(json['username']),
        isVerified: _bool(json['is_verified']),
        internalNote: _str(json['internal_note']),
        followUpStatus: _str(json['follow_up_status']),
        inquiryCount: _int(json['inquiry_count']),
        openInquiries: _int(json['open_inquiries']),
        labels: _objList(json['labels']).map(CustomerLabel.fromJson).toList(),
        avatarUrl: _optStr(json['avatar_url']),
        lastInteractionAt: _date(json['last_interaction_at']),
        lastMessageAt: _date(json['last_message_at']),
        createdAt: _date(json['created_at']),
      );
}

/// Result of `business_inquiry_start`: the conversation is a normal chat thread.
class InquiryStartResult {
  const InquiryStartResult({
    required this.conversationId,
    required this.inquiryId,
    required this.businessId,
    required this.subject,
  });

  final String conversationId;
  final String inquiryId;
  final String businessId;
  final String subject;

  factory InquiryStartResult.fromJson(Map<String, dynamic> json) => InquiryStartResult(
        conversationId: _str(json['conversation_id']),
        inquiryId: _str(json['inquiry_id']),
        businessId: _str(json['business_id']),
        subject: _str(json['subject']),
      );
}

// ---------------------------------------------------------------- verification

class VerificationTimelineEntry {
  const VerificationTimelineEntry({
    required this.id,
    required this.action,
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
    this.note,
  });

  final int id;
  final String action;
  final String toStatus;
  final DateTime? createdAt;
  final String? fromStatus;
  final String? note;

  factory VerificationTimelineEntry.fromJson(Map<String, dynamic> json) => VerificationTimelineEntry(
        id: _int(json['id']),
        action: _str(json['action']),
        toStatus: _str(json['to_status']),
        createdAt: _date(json['created_at']),
        fromStatus: _optStr(json['from_status']),
        note: _optStr(json['note']),
      );
}

class BusinessVerificationState {
  const BusinessVerificationState({
    required this.businessId,
    required this.isVerified,
    required this.canSubmit,
    required this.canManage,
    required this.requirements,
    required this.history,
    required this.documents,
    this.application,
  });

  final String businessId;
  final bool isVerified;
  final bool canSubmit;
  final bool canManage;
  final Map<String, dynamic> requirements;
  final Map<String, dynamic>? application;
  final List<VerificationTimelineEntry> history;
  final List<Map<String, dynamic>> documents;

  String get status => _str(application?['status']);
  String get decisionNote => _str(application?['decision_note']);

  factory BusinessVerificationState.fromJson(Map<String, dynamic> json) => BusinessVerificationState(
        businessId: _str(json['business_id']),
        isVerified: _bool(json['is_verified']),
        canSubmit: _bool(json['can_submit']),
        canManage: _bool(json['can_manage']),
        requirements: _obj(json['requirements']),
        application: json['application'] is Map ? _obj(json['application']) : null,
        history: _objList(json['history']).map(VerificationTimelineEntry.fromJson).toList(),
        documents: _objList(json['documents']),
      );
}

// ---------------------------------------------------------------- partner

class PartnerBenefit {
  const PartnerBenefit({
    required this.key,
    required this.title,
    required this.description,
    required this.enabled,
    required this.granted,
    required this.isPublic,
  });

  final String key;
  final String title;
  final String description;
  final bool enabled;
  final bool granted;
  final bool isPublic;

  bool get usable => enabled && granted;

  factory PartnerBenefit.fromJson(Map<String, dynamic> json) => PartnerBenefit(
        key: _str(json['key']),
        title: _str(json['title']),
        description: _str(json['description']),
        enabled: _bool(json['enabled']),
        granted: _bool(json['granted']),
        isPublic: _bool(json['is_public']),
      );
}

class PartnerActivityEntry {
  const PartnerActivityEntry({
    required this.kind,
    required this.summary,
    required this.createdAt,
  });

  final String kind;
  final String summary;
  final DateTime? createdAt;

  factory PartnerActivityEntry.fromJson(Map<String, dynamic> json) => PartnerActivityEntry(
        kind: _str(json['kind']),
        summary: _str(json['summary']),
        createdAt: _date(json['created_at']),
      );
}

class PartnerWorkspace {
  const PartnerWorkspace({
    required this.partnerStatus,
    required this.isFeatured,
    required this.isBadgeVisible,
    required this.announcements,
    required this.resourcesCount,
    required this.openSupportRequests,
    required this.benefits,
    required this.activity,
    required this.notImplemented,
    this.featuredUntil,
  });

  final String partnerStatus;
  final bool isFeatured;
  final bool isBadgeVisible;
  final int announcements;
  final int resourcesCount;
  final int openSupportRequests;
  final List<PartnerBenefit> benefits;
  final List<PartnerActivityEntry> activity;
  final List<Map<String, dynamic>> notImplemented;
  final DateTime? featuredUntil;

  bool get isActivePartner => partnerStatus == 'active';
  PartnerBenefit? benefit(String key) {
    for (final b in benefits) {
      if (b.key == key) return b;
    }
    return null;
  }

  bool canUse(String key) => benefit(key)?.usable ?? false;

  factory PartnerWorkspace.fromJson(Map<String, dynamic> json) => PartnerWorkspace(
        partnerStatus: _str(json['partner_status']),
        isFeatured: _bool(json['is_featured']),
        isBadgeVisible: _bool(json['is_badge_visible']),
        announcements: _int(json['announcements']),
        resourcesCount: _int(json['resources_count']),
        openSupportRequests: _int(json['open_support_requests']),
        benefits: _objList(json['benefits']).map(PartnerBenefit.fromJson).toList(),
        activity: _objList(json['activity']).map(PartnerActivityEntry.fromJson).toList(),
        notImplemented: _objList(json['not_implemented']),
        featuredUntil: _date(json['featured_until']),
      );
}

class PartnerResource {
  const PartnerResource({
    required this.id,
    required this.title,
    required this.kind,
    required this.description,
    this.url,
    this.body,
    this.createdAt,
  });

  final String id;
  final String title;
  final String kind;
  final String description;
  final String? url;
  final String? body;
  final DateTime? createdAt;

  factory PartnerResource.fromJson(Map<String, dynamic> json) => PartnerResource(
        id: _str(json['id']),
        title: _str(json['title']),
        kind: _str(json['kind']),
        description: _str(json['description']),
        url: _optStr(json['url']),
        body: _optStr(json['body']),
        createdAt: _date(json['created_at']),
      );
}

class PartnerSupportRequest {
  const PartnerSupportRequest({
    required this.id,
    required this.subject,
    required this.body,
    required this.status,
    this.response,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String subject;
  final String body;
  final String status;
  final String? response;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PartnerSupportRequest.fromJson(Map<String, dynamic> json) => PartnerSupportRequest(
        id: _str(json['id']),
        subject: _str(json['subject']),
        body: _str(json['body']),
        status: _str(json['status']),
        response: _optStr(json['response']),
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
      );
}

class PartnerPublicProfile {
  const PartnerPublicProfile({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.headline,
    required this.bio,
    required this.specialties,
    required this.partnerCategory,
    required this.isFeatured,
    required this.isVerified,
    required this.isBadgeVisible,
    required this.canMessage,
    this.logoUrl,
    this.coverUrl,
    this.website,
    this.approvedAt,
  });

  final String userId;
  final String displayName;
  final String username;
  final String headline;
  final String bio;
  final List<String> specialties;
  final String partnerCategory;
  final bool isFeatured;
  final bool isVerified;
  final bool isBadgeVisible;
  final bool canMessage;
  final String? logoUrl;
  final String? coverUrl;
  final String? website;
  final DateTime? approvedAt;

  factory PartnerPublicProfile.fromJson(Map<String, dynamic> json) => PartnerPublicProfile(
        userId: _str(json['user_id']),
        displayName: _str(json['display_name']),
        username: _str(json['username']),
        headline: _str(json['headline']),
        bio: _str(json['bio']),
        specialties: _strings(json['specialties']),
        partnerCategory: _str(json['partner_category']),
        isFeatured: _bool(json['is_featured']),
        isVerified: _bool(json['is_verified']),
        isBadgeVisible: _bool(json['is_badge_visible']),
        canMessage: _bool(json['can_message']),
        logoUrl: _optStr(json['logo_url']),
        coverUrl: _optStr(json['cover_url']),
        website: _optStr(json['website']),
        approvedAt: _date(json['approved_at']),
      );
}

class PartnerDirectory {
  const PartnerDirectory({required this.enabled, required this.partners, required this.categories});

  final bool enabled;
  final List<PartnerPublicProfile> partners;
  final List<String> categories;

  factory PartnerDirectory.fromJson(Map<String, dynamic> json) => PartnerDirectory(
        enabled: _bool(json['enabled']),
        partners: _objList(json['partners']).map(PartnerPublicProfile.fromJson).toList(),
        categories: _strings(json['categories']),
      );

  static const empty = PartnerDirectory(enabled: false, partners: [], categories: []);
}

class PartnerApplicationRequirements {
  const PartnerApplicationRequirements({
    required this.isOpen,
    required this.categories,
    required this.requirements,
    required this.minAccountAgeDays,
    required this.cooldownDays,
    required this.canApply,
    this.reason,
  });

  final bool isOpen;
  final List<String> categories;
  final String requirements;
  final int minAccountAgeDays;
  final int cooldownDays;
  final bool canApply;
  final String? reason;

  factory PartnerApplicationRequirements.fromJson(Map<String, dynamic> json) =>
      PartnerApplicationRequirements(
        isOpen: _bool(json['is_open']),
        categories: _strings(json['categories']),
        requirements: _str(json['requirements']),
        minAccountAgeDays: _int(json['min_account_age_days']),
        cooldownDays: _int(json['cooldown_days']),
        canApply: _bool(json['can_apply']),
        reason: _optStr(json['reason']),
      );
}

/// The signed-in partner's own editable profile. Reads `partner_profiles` (RLS
/// restricts the row to the owner), so a partner can edit a profile that is not
/// currently listed in the public directory.
class PartnerOwnProfile {
  const PartnerOwnProfile({
    required this.userId,
    required this.partnerStatus,
    required this.partnerCategory,
    required this.displayName,
    required this.headline,
    required this.bio,
    required this.specialties,
    required this.directoryVisible,
    required this.isBadgeVisible,
    required this.isFeatured,
    this.website,
    this.logoUrl,
    this.coverUrl,
    this.approvedAt,
    this.featuredUntil,
  });

  final String userId;
  final String partnerStatus;
  final String partnerCategory;
  final String displayName;
  final String headline;
  final String bio;
  final List<String> specialties;
  final bool directoryVisible;
  final bool isBadgeVisible;
  final bool isFeatured;
  final String? website;
  final String? logoUrl;
  final String? coverUrl;
  final DateTime? approvedAt;
  final DateTime? featuredUntil;

  factory PartnerOwnProfile.fromJson(Map<String, dynamic> json) => PartnerOwnProfile(
        userId: _str(json['user_id']),
        partnerStatus: _str(json['partner_status']),
        partnerCategory: _str(json['partner_category']),
        displayName: _str(json['display_name']),
        headline: _str(json['headline']),
        bio: _str(json['bio']),
        specialties: _strings(json['specialties']),
        directoryVisible: _bool(json['directory_visible'] ?? true),
        isBadgeVisible: _bool(json['badge_enabled'] ?? true),
        isFeatured: _bool(json['is_featured']),
        website: _optStr(json['website']),
        logoUrl: _optStr(json['logo_url']),
        coverUrl: _optStr(json['cover_url']),
        approvedAt: _date(json['approved_at']),
        featuredUntil: _date(json['featured_until']),
      );
}

/// A partner application row as returned by `my_partner_applications`.
class PartnerApplicationRecord {
  const PartnerApplicationRecord({
    required this.id,
    required this.organization,
    required this.category,
    required this.status,
    required this.proposal,
    required this.hasDraft,
    this.website,
    this.submittedAt,
    this.decisionNote,
    this.createdAt,
    this.updatedAt,
    this.infoRequested,
    this.infoResponse,
  });

  final String id;
  final String organization;
  final String category;
  final String status;
  final String proposal;
  final bool hasDraft;
  final String? website;
  final DateTime? submittedAt;
  final String? decisionNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? infoRequested;
  final String? infoResponse;

  bool get isEditable => status == 'draft';
  bool get isDecided => status == 'approved' || status == 'rejected';
  bool get needsInfo => status == 'additional_info_required';

  factory PartnerApplicationRecord.fromJson(Map<String, dynamic> json) => PartnerApplicationRecord(
        id: _str(json['id']),
        organization: _str(json['organization']),
        category: _str(json['partnership_category']),
        status: _str(json['status']),
        proposal: _str(json['proposal']),
        hasDraft: _str(json['status']) == 'draft',
        website: _optStr(json['website']),
        submittedAt: _date(json['submitted_at']),
        decisionNote: _optStr(json['decision_note']),
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
        infoRequested: _optStr(json['info_requested']),
        infoResponse: _optStr(json['info_response']),
      );
}
