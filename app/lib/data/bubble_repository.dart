import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Single gateway to Supabase. Every write goes through a database function or a
/// table/column that the database grants and RLS allows. Nothing here decides
/// privileges: the database re-checks every call.
class BubbleRepository {
  BubbleRepository(this._client);

  final SupabaseClient _client;

  /// Profile columns the `authenticated` role may read. `email` is intentionally
  /// excluded; it is never granted to clients (see migration 0002).
  static const _profileColumns =
      'id, username, display_name, avatar_url, cover_url, bio, account_status, '
      'is_verified, verified_at, created_at, last_seen_at';

  String? get currentUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------- auth

  Future<void> sendEmailOtp(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: true);

  Future<void> verifyEmailOtp(String email, String token) =>
      _client.auth.verifyOTP(type: OtpType.email, email: email, token: token);

  Future<void> signOut() => _client.auth.signOut();

  Future<void> touchPresence() => _client.rpc('touch_presence');

  // ---------------------------------------------------------------- profile

  Future<AccessSnapshot> myAccess() async {
    final data = await _client.rpc('my_access');
    if (data is! Map<String, dynamic>) return AccessSnapshot.empty;
    return AccessSnapshot.fromJson(data);
  }

  Future<UserProfile?> myProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select(_profileColumns)
        .eq('id', uid)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  Future<void> updateMyProfile({
    required String username,
    required String displayName,
    required String bio,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('profiles').update({
      'username': username.trim().toLowerCase(),
      'display_name': displayName.trim(),
      'bio': bio.trim(),
    }).eq('id', uid);
  }

  Future<UserProfile?> profileById(String id) async {
    final row = await _client
        .from('profiles')
        .select(_profileColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  /// Staff directory. Requires users.read; the database enforces it.
  Future<List<Map<String, dynamic>>> adminListUsers({
    String? query,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc('admin_list_users', params: {
      'p_query': (query == null || query.trim().isEmpty) ? null : query.trim(),
      'p_status': status,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> adminSetAccountStatus({
    required String userId,
    required String status,
    String? reason,
  }) =>
      _client.rpc('admin_set_account_status', params: {
        'p_user_id': userId,
        'p_status': status,
        'p_reason': reason,
      });

  // ---------------------------------------------------------------- channels

  /// Re-applies mandatory subscriptions (e.g. the official channel) for the signed-in user.
  Future<void> ensureMandatorySubscriptions() =>
      _client.rpc('ensure_my_mandatory_subscriptions');

  Future<List<ChannelModel>> channels({int limit = 100}) async {
    final rows = await _client
        .from('channels')
        .select()
        .order('is_official', ascending: false)
        .order('subscriber_count', ascending: false)
        .limit(limit);
    return rows.map(ChannelModel.fromJson).toList();
  }

  /// Channels the signed-in user is subscribed to (includes the mandatory official channel).
  Future<List<ChannelModel>> mySubscriptions() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _client
        .from('channel_subscribers')
        .select('channels(*)')
        .eq('user_id', uid)
        .eq('is_active', true);
    return rows
        .map((r) => r['channels'])
        .whereType<Map<String, dynamic>>()
        .map(ChannelModel.fromJson)
        .toList();
  }

  Future<ChannelModel?> channel(String id) async {
    final row = await _client.from('channels').select().eq('id', id).maybeSingle();
    return row == null ? null : ChannelModel.fromJson(row);
  }

  Future<bool> isSubscribed(String channelId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    final row = await _client
        .from('channel_subscribers')
        .select('id')
        .eq('channel_id', channelId)
        .eq('user_id', uid)
        .eq('is_active', true)
        .maybeSingle();
    return row != null;
  }

  Future<void> subscribe(String channelId) =>
      _client.rpc('subscribe_to_channel', params: {'p_channel_id': channelId});

  Future<void> unsubscribe(String channelId) =>
      _client.rpc('unsubscribe_from_channel', params: {'p_channel_id': channelId});

  Future<String> joinChannelByInvite(String code) async {
    final id = await _client.rpc('join_channel_by_invite', params: {'p_code': code.trim()});
    return id.toString();
  }

  Future<String> createChannel({
    required String name,
    required String username,
    required String description,
    required bool isPublic,
    required bool commentsEnabled,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final row = await _client
        .from('channels')
        .insert({
          'owner_id': uid,
          'name': name.trim(),
          'username': username.trim().toLowerCase(),
          'description': description.trim(),
          'is_public': isPublic,
          'comments_enabled': commentsEnabled,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> deleteChannel(String channelId) =>
      _client.rpc('delete_channel', params: {'p_channel_id': channelId});

  Future<List<ChannelPost>> channelPosts(String channelId, {int limit = 50}) async {
    final rows = await _client
        .from('channel_posts')
        .select()
        .eq('channel_id', channelId)
        .order('is_pinned', ascending: false)
        .order('publish_at', ascending: false)
        .limit(limit);
    return rows.map(ChannelPost.fromJson).toList();
  }

  Future<void> publishChannelPost({required String channelId, required String body}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('channel_posts').insert({
      'channel_id': channelId,
      'author_id': uid,
      'kind': 'text',
      'body': body.trim(),
      'publish_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> setPostPinned(String postId, bool pinned) =>
      _client.rpc('set_channel_post_pinned', params: {'p_post_id': postId, 'p_pinned': pinned});

  Future<void> recordPostView(String postId) =>
      _client.rpc('record_channel_post_view', params: {'p_post_id': postId});

  Future<Map<String, dynamic>> channelStats(String channelId) async {
    final data = await _client.rpc('channel_stats', params: {'p_channel_id': channelId});
    return (data as Map).cast<String, dynamic>();
  }

  // ---------------------------------------------------------------- verification

  Future<List<VerificationApplication>> myVerificationApplications() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _client
        .from('verification_applications')
        .select()
        .eq('applicant_id', uid)
        .order('submitted_at', ascending: false);
    return rows.map(VerificationApplication.fromJson).toList();
  }

  Future<String> submitVerification({
    required String applicationType,
    required String fullName,
    required String username,
    required String category,
    required String description,
    required String reason,
    String? businessId,
    String? channelId,
  }) async {
    final id = await _client.rpc('submit_verification_application', params: {
      'p_application_type': applicationType,
      'p_full_name': fullName.trim(),
      'p_username': username.trim(),
      'p_category': category.trim(),
      'p_description': description.trim(),
      'p_reason': reason.trim(),
      'p_links': <String>[],
      'p_business_id': businessId,
      'p_channel_id': channelId,
    });
    return id.toString();
  }

  /// Uploads to the private `verification-docs` bucket at {uid}/{applicationId}/{file}
  /// and registers the document. Nothing is public; staff read via signed URLs only.
  Future<void> uploadVerificationDocument({
    required String applicationId,
    required String docType,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/$applicationId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client.storage.from('verification-docs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    await _client.rpc('add_verification_document', params: {
      'p_application_id': applicationId,
      'p_storage_path': path,
      'p_doc_type': docType,
      'p_mime_type': mimeType,
      'p_size_bytes': bytes.length,
    });
  }

  Future<List<Map<String, dynamic>>> verificationDocuments(String applicationId) async {
    final rows = await _client
        .from('verification_documents')
        .select()
        .eq('application_id', applicationId)
        .order('created_at');
    return rows.cast<Map<String, dynamic>>();
  }

  /// Short-lived link for staff or the applicant to view a private document.
  Future<String> signedDocumentUrl(String storagePath) =>
      _client.storage.from('verification-docs').createSignedUrl(storagePath, 300);

  Future<List<VerificationApplication>> verificationQueue({String? type, String? status}) async {
    final rows = await _client.rpc('list_verification_queue', params: {
      'p_type': type,
      'p_status': status,
    });
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(VerificationApplication.fromJson)
        .toList();
  }

  Future<String> reviewVerification({
    required String applicationId,
    required String action,
    String? note,
  }) async {
    final status = await _client.rpc('review_verification_application', params: {
      'p_application_id': applicationId,
      'p_action': action,
      'p_note': note,
    });
    return status.toString();
  }

  // ---------------------------------------------------------------- partners

  Future<PartnerDashboard?> partnerDashboard() async {
    final data = await _client.rpc('partner_dashboard');
    if (data is! Map<String, dynamic>) return null;
    return PartnerDashboard.fromJson(data);
  }

  Future<List<PartnerApplication>> myPartnerApplications() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _client
        .from('partner_applications')
        .select()
        .eq('applicant_id', uid)
        .order('created_at', ascending: false);
    return rows.map(PartnerApplication.fromJson).toList();
  }

  Future<List<PartnerApplication>> partnerQueue() async {
    final rows = await _client
        .from('partner_applications')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(PartnerApplication.fromJson).toList();
  }

  Future<String> submitPartnerApplication({
    required String fullName,
    required String username,
    required String email,
    required String organization,
    required String website,
    required String partnershipCategory,
    required String proposal,
    required String description,
  }) async {
    final id = await _client.rpc('submit_partner_application', params: {
      'p_full_name': fullName.trim(),
      'p_username': username.trim().toLowerCase(),
      'p_email': email.trim(),
      'p_organization': organization.trim(),
      'p_website': website.trim(),
      'p_social_media': <String, dynamic>{},
      'p_partnership_category': partnershipCategory.trim(),
      'p_proposal': proposal.trim(),
      'p_description': description.trim(),
    });
    return id.toString();
  }

  Future<String> reviewPartnerApplication({
    required String applicationId,
    required String action,
    String? note,
  }) async {
    final status = await _client.rpc('review_partner_application', params: {
      'p_application_id': applicationId,
      'p_action': action,
      'p_note': note,
    });
    return status.toString();
  }

  Future<List<Map<String, dynamic>>> partnerAnnouncements() async {
    final rows = await _client
        .from('partner_announcements')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> publishPartnerAnnouncement({
    required String title,
    required String body,
    String? category,
  }) =>
      _client.rpc('publish_partner_announcement', params: {
        'p_title': title.trim(),
        'p_body': body.trim(),
        'p_category': category,
      });

  // ---------------------------------------------------------------- business

  Future<List<BusinessSummary>> myBusinesses() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _client
        .from('business_members')
        .select('businesses(*)')
        .eq('user_id', uid);
    return rows
        .map((r) => r['businesses'])
        .whereType<Map<String, dynamic>>()
        .map(BusinessSummary.fromJson)
        .toList();
  }

  Future<String> createBusiness({
    required String name,
    required String username,
    required String category,
    required String businessEmail,
    required String description,
    String? website,
  }) async {
    final id = await _client.rpc('create_business', params: {
      'p_name': name.trim(),
      'p_username': username.trim().toLowerCase(),
      'p_category': category.trim(),
      'p_business_email': businessEmail.trim(),
      'p_description': description.trim(),
      'p_website': (website == null || website.trim().isEmpty) ? null : website.trim(),
      'p_business_phone': null,
    });
    return id.toString();
  }

  Future<Map<String, dynamic>> businessDashboard(String businessId) async {
    final data = await _client.rpc('business_dashboard', params: {'p_business_id': businessId});
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> switchAccountMode({required String mode, String? businessId}) =>
      _client.rpc('switch_account_mode', params: {'p_mode': mode, 'p_business_id': businessId});

  // ---------------------------------------------------------------- settings, notifications

  Future<Map<String, dynamic>?> mySettings() async {
    final uid = currentUserId;
    if (uid == null) return null;
    return _client.from('user_settings').select().eq('user_id', uid).maybeSingle();
  }

  Future<List<Map<String, dynamic>>> myNotifications({int limit = 50}) async {
    final rows = await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(String id) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  // ---------------------------------------------------------------- owner / admin

  Future<OwnerStats> ownerStats() async {
    final data = await _client.rpc('owner_dashboard_stats');
    return OwnerStats.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<Map<String, dynamic>>> adminAuditLog({int limit = 100}) async {
    final rows = await _client
        .from('admin_audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> ownerAuditLog({int limit = 100}) async {
    final rows = await _client
        .from('owner_audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> reports({String? status, int limit = 100}) async {
    var query = _client.from('reports').select();
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> resolveReport({required String reportId, required String action, String? note}) =>
      _client.rpc('resolve_report', params: {
        'p_report_id': reportId,
        'p_action': action,
        'p_note': note,
      });

  Future<void> publishPlatformAnnouncement({
    required String title,
    required String body,
    required String audience,
    required bool postToOfficial,
  }) =>
      _client.rpc('publish_platform_announcement', params: {
        'p_title': title.trim(),
        'p_body': body.trim(),
        'p_audience': audience,
        'p_post_to_official': postToOfficial,
      });
}
