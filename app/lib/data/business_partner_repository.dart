import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_partner.dart';

/// Part 8 gateway. Every method maps 1:1 to a database function from
/// `20261030000016_business_partner_ecosystem.sql`; the server re-checks the
/// caller's business permission, tenant and RLS on every call. Client-side
/// checks (`canManage`, `permissions`) only decide what to render.
class BusinessPartnerRepository {
  BusinessPartnerRepository(this._client);

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  String _requireUser() {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is List) {
      return value.whereType<Object>().map(_map).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  // ---------------------------------------------------------------- account mode

  /// Reads the mode written by `switch_account_mode`. The user may only read
  /// their own row (RLS), so this never leaks another account's choice.
  Future<ActiveAccountMode> activeAccountMode() async {
    final uid = _requireUser();
    final row = await _client
        .from('user_settings')
        .select('active_account_mode, active_business_id')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return ActiveAccountMode.personal;
    return ActiveAccountMode.fromJson(row);
  }

  Future<void> switchAccountMode({required AccountMode mode, String? businessId}) =>
      _client.rpc('switch_account_mode', params: {
        'p_mode': mode.name,
        'p_business_id': mode == AccountMode.business ? businessId : null,
      });

  // ---------------------------------------------------------------- businesses

  Future<List<BusinessMembership>> myBusinesses() async {
    _requireUser();
    final data = await _client.rpc('business_my_businesses');
    return _rows(data).map(BusinessMembership.fromJson).toList();
  }

  /// Profile payload. The same RPC serves members and visitors: the server adds
  /// `my_role`/`my_permissions` for members and strips private contact fields for
  /// visitors according to the business visibility settings.
  Future<BusinessProfile> profile(String businessId) async {
    final data =
        await _client.rpc('business_public_profile', params: {'p_business_id': businessId});
    return BusinessProfile.fromJson(_map(data));
  }

  Future<BusinessProfile> publicProfile(String businessId) => profile(businessId);

  Future<void> updateProfile(String businessId, Map<String, dynamic> patch) =>
      _client.rpc('business_update_profile', params: {
        'p_business_id': businessId,
        'p_patch': patch,
      });

  Future<BusinessSetupProgress> setupProgress(String businessId) async {
    final data = await _client.rpc('business_setup_progress', params: {'p_business_id': businessId});
    return BusinessSetupProgress.fromJson(_map(data));
  }

  Future<void> followBusiness(String businessId, bool follow) =>
      _client.rpc('business_follow', params: {'p_business_id': businessId, 'p_follow': follow});

  /// Records a real profile or catalog view. Returns true when the backend stored
  /// a new event (repeat views on the same day are de-duplicated server-side).
  Future<bool> recordView(String businessId, {String kind = 'profile_view', String? subjectId}) async {
    final data = await _client.rpc('business_record_event', params: {
      'p_business_id': businessId,
      'p_kind': kind,
      'p_subject_id': subjectId,
    });
    return data == true;
  }

  // ---------------------------------------------------------------- team

  Future<BusinessTeam> team(String businessId) async {
    final data = await _client.rpc('business_team_list', params: {'p_business_id': businessId});
    return BusinessTeam.fromJson(_map(data));
  }

  Future<List<BusinessInviteInboxItem>> myInvites() async {
    _requireUser();
    final data = await _client.rpc('my_business_invites');
    return _rows(data).map(BusinessInviteInboxItem.fromJson).toList();
  }

  Future<String> inviteMember({
    required String businessId,
    required String username,
    required String role,
    String? note,
  }) async {
    final data = await _client.rpc('business_team_invite', params: {
      'p_business_id': businessId,
      'p_username': username.trim(),
      'p_role': role,
      'p_note': note,
    });
    return data.toString();
  }

  Future<void> respondToInvite(String inviteId, {required bool accept}) =>
      _client.rpc('business_invite_respond', params: {'p_invite_id': inviteId, 'p_accept': accept});

  Future<void> setMemberRole(String businessId, String userId, String role) =>
      _client.rpc('business_team_set_role', params: {
        'p_business_id': businessId,
        'p_user_id': userId,
        'p_role': role,
      });

  Future<void> setMemberPermission(
    String businessId,
    String userId,
    String permission, {
    required bool granted,
  }) =>
      _client.rpc('business_team_set_permission', params: {
        'p_business_id': businessId,
        'p_user_id': userId,
        'p_permission': permission,
        'p_granted': granted,
      });

  Future<void> removeMember(String businessId, String userId) =>
      _client.rpc('business_team_remove', params: {'p_business_id': businessId, 'p_user_id': userId});

  Future<void> revokeInvite(String inviteId) =>
      _client.rpc('business_team_revoke_invite', params: {'p_invite_id': inviteId});

  // ---------------------------------------------------------------- catalog

  Future<List<BusinessCatalogItem>> catalog(
    String businessId, {
    String? search,
    String? kind,
    String? category,
    String? status,
    String sort = 'recent',
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc('business_catalog_list', params: {
      'p_business_id': businessId,
      'p_search': search,
      'p_kind': kind,
      'p_category': category,
      'p_status': status,
      'p_sort': sort,
      'p_limit': limit,
      'p_offset': offset,
    });
    return _rows(data).map(BusinessCatalogItem.fromJson).toList();
  }

  Future<List<BusinessCatalogItem>> publicCatalog(
    String businessId, {
    String? search,
    String? kind,
    String? category,
    String sort = 'recent',
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc('business_catalog_public', params: {
      'p_business_id': businessId,
      'p_search': search,
      'p_kind': kind,
      'p_category': category,
      'p_sort': sort,
      'p_limit': limit,
      'p_offset': offset,
    });
    return _rows(data).map(BusinessCatalogItem.fromJson).toList();
  }

  Future<CatalogDetail> catalogDetail(String itemId) async {
    final data = await _client.rpc('business_catalog_detail', params: {'p_item_id': itemId});
    return CatalogDetail.fromJson(_map(data));
  }

  Future<String> saveCatalogItem(String businessId, CatalogDraft draft) async {
    final data = await _client.rpc('business_catalog_save', params: draft.toParams(businessId));
    return data.toString();
  }

  Future<void> setCatalogStatus(String itemId, String status) =>
      _client.rpc('business_catalog_set_status', params: {'p_item_id': itemId, 'p_status': status});

  Future<void> deleteCatalogItem(String itemId) =>
      _client.rpc('business_catalog_delete', params: {'p_item_id': itemId});

  /// Returns the real in-app share path plus the new share counter.
  Future<Map<String, dynamic>> shareCatalogItem(String itemId) async {
    final data = await _client.rpc('business_catalog_share', params: {'p_item_id': itemId});
    return _map(data);
  }

  Future<List<String>> catalogCategories(String businessId) async {
    final data = await _client.rpc('business_catalog_categories', params: {'p_business_id': businessId});
    return data is List ? data.map((e) => e.toString()).toList() : const [];
  }

  // ---------------------------------------------------------------- analytics

  Future<BusinessAnalytics> analytics(String businessId, {int days = 30}) async {
    final data = await _client.rpc('business_analytics', params: {
      'p_business_id': businessId,
      'p_days': days,
    });
    return BusinessAnalytics.fromJson(_map(data));
  }

  // ---------------------------------------------------------------- inquiries

  Future<List<BusinessInquiry>> inquiries(String businessId, {String? status, String? search}) async {
    final data = await _client.rpc('business_inquiry_list', params: {
      'p_business_id': businessId,
      'p_status': status,
      'p_search': search,
    });
    return _rows(data).map(BusinessInquiry.fromJson).toList();
  }

  Future<List<BusinessInquiry>> myInquiries() async {
    _requireUser();
    final data = await _client.rpc('my_business_inquiries');
    return _rows(data).map(BusinessInquiry.fromJson).toList();
  }

  Future<BusinessInquiryDetail> inquiryDetail(String inquiryId) async {
    final data = await _client.rpc('business_inquiry_detail', params: {'p_inquiry_id': inquiryId});
    return BusinessInquiryDetail.fromJson(_map(data));
  }

  /// Starts (or continues) a real messaging thread with a business. The server
  /// creates the conversation, the first message and the inquiry record.
  Future<InquiryStartResult> startInquiry({
    required String businessId,
    required String message,
    String? catalogItemId,
    String? subject,
  }) async {
    final data = await _client.rpc('business_inquiry_start', params: {
      'p_business_id': businessId,
      'p_message': message.trim(),
      'p_catalog_item_id': catalogItemId,
      'p_subject': subject,
    });
    return InquiryStartResult.fromJson(_map(data));
  }

  Future<void> setInquiryStatus(String inquiryId, String status, {String? note}) =>
      _client.rpc('business_inquiry_set_status', params: {
        'p_inquiry_id': inquiryId,
        'p_status': status,
        'p_note': note,
      });

  Future<void> assignInquiry(String inquiryId, String userId) =>
      _client.rpc('business_inquiry_assign', params: {'p_inquiry_id': inquiryId, 'p_user_id': userId});

  Future<void> setInquiryPriority(String inquiryId, String priority) => _client.rpc(
        'business_inquiry_set_priority',
        params: {'p_inquiry_id': inquiryId, 'p_priority': priority},
      );

  // ---------------------------------------------------------------- customers

  Future<List<BusinessCustomer>> customers(
    String businessId, {
    String? search,
    String? labelId,
    String? followUp,
    int limit = 50,
  }) async {
    final data = await _client.rpc('business_customer_list', params: {
      'p_business_id': businessId,
      'p_search': search,
      'p_label_id': labelId,
      'p_follow_up': followUp,
      'p_limit': limit,
    });
    return _rows(data).map(BusinessCustomer.fromJson).toList();
  }

  Future<void> updateCustomer(String customerId, Map<String, dynamic> patch) =>
      _client.rpc('business_customer_update', params: {'p_customer_id': customerId, 'p_patch': patch});

  Future<void> setCustomerLabels(String customerId, List<String> labelIds) =>
      _client.rpc('business_customer_set_labels', params: {
        'p_customer_id': customerId,
        'p_label_ids': labelIds,
      });

  Future<List<CustomerLabel>> labels(String businessId) async {
    final data = await _client.rpc('business_label_list', params: {'p_business_id': businessId});
    return _rows(data).map(CustomerLabel.fromJson).toList();
  }

  Future<String> saveLabel(String businessId, {required String name, String color = '#2563EB'}) async {
    final data = await _client.rpc('business_label_save', params: {
      'p_business_id': businessId,
      'p_name': name.trim(),
      'p_color': color,
    });
    return data.toString();
  }

  Future<void> deleteLabel(String labelId) =>
      _client.rpc('business_label_delete', params: {'p_label_id': labelId});

  // ---------------------------------------------------------------- verification

  Future<BusinessVerificationState> businessVerification(String businessId) async {
    final data = await _client.rpc('business_verification_state', params: {'p_business_id': businessId});
    return BusinessVerificationState.fromJson(_map(data));
  }

  Future<void> respondVerificationInfo(String applicationId, String message) =>
      _client.rpc('verification_respond_info', params: {
        'p_application_id': applicationId,
        'p_message': message,
      });

  // ---------------------------------------------------------------- social

  Future<String> createBusinessPost({
    required String businessId,
    required String body,
    String kind = 'text',
    List<String> mediaPaths = const [],
    String? catalogItemId,
    String visibility = 'public',
  }) async {
    final data = await _client.rpc('business_post_create', params: {
      'p_business_id': businessId,
      'p_body': body.trim(),
      'p_kind': kind,
      'p_media_paths': mediaPaths,
      'p_catalog_item_id': catalogItemId,
      'p_visibility': visibility,
    });
    return data.toString();
  }

  Future<void> deleteBusinessPost(String postId) =>
      _client.rpc('business_post_delete', params: {'p_post_id': postId});

  // ---------------------------------------------------------------- partner

  Future<PartnerWorkspace> partnerWorkspace() async {
    _requireUser();
    final data = await _client.rpc('partner_my_benefits');
    return PartnerWorkspace.fromJson(_map(data));
  }

  /// The caller's own partner row (includes directory visibility and status).
  Future<PartnerOwnProfile?> myPartnerProfile() async {
    final uid = _requireUser();
    final row = await _client.from('partner_profiles').select().eq('user_id', uid).maybeSingle();
    return row == null ? null : PartnerOwnProfile.fromJson(_map(row));
  }

  Future<void> updatePartnerProfile(Map<String, dynamic> patch) =>
      _client.rpc('partner_profile_update', params: {'p_patch': patch});

  Future<List<PartnerResource>> partnerResources() async {
    final data = await _client.rpc('partner_resources_list');
    return _rows(data).map(PartnerResource.fromJson).toList();
  }

  Future<List<PartnerSupportRequest>> partnerSupport() async {
    final data = await _client.rpc('partner_support_list');
    return _rows(data).map(PartnerSupportRequest.fromJson).toList();
  }

  Future<String> createPartnerSupport({required String subject, required String body}) async {
    final data = await _client.rpc('partner_support_create', params: {
      'p_subject': subject.trim(),
      'p_body': body.trim(),
    });
    return data.toString();
  }

  Future<List<PartnerActivityEntry>> partnerActivity() async {
    final data = await _client.rpc('partner_activity_list');
    return _rows(data).map(PartnerActivityEntry.fromJson).toList();
  }

  Future<PartnerDirectory> partnerDirectory({
    String? search,
    String? category,
    bool featuredOnly = false,
    int limit = 50,
  }) async {
    final data = await _client.rpc('partner_directory', params: {
      'p_search': search,
      'p_category': category,
      'p_featured_only': featuredOnly,
      'p_limit': limit,
    });
    return PartnerDirectory.fromJson(_map(data));
  }

  Future<PartnerPublicProfile?> partnerPublicProfile(String userId) async {
    final data = await _client.rpc('partner_public_profile', params: {'p_user_id': userId});
    if (data is! Map) return null;
    return PartnerPublicProfile.fromJson(_map(data));
  }

  Future<PartnerApplicationRequirements> partnerRequirements() async {
    final data = await _client.rpc('partner_application_requirements');
    return PartnerApplicationRequirements.fromJson(_map(data));
  }

  /// The applicant's own applications. RLS restricts the select to the caller's
  /// rows, so no client-supplied filter can widen it.
  Future<List<PartnerApplicationRecord>> myPartnerApplications() async {
    final uid = _requireUser();
    final rows = await _client
        .from('partner_applications')
        .select()
        .eq('applicant_id', uid)
        .order('created_at', ascending: false);
    return _rows(rows).map(PartnerApplicationRecord.fromJson).toList();
  }

  Future<String> savePartnerDraft(Map<String, dynamic> payload) async {
    final data = await _client.rpc('partner_application_save_draft', params: {'p_payload': payload});
    return data.toString();
  }

  Future<String> submitPartnerApplication(String applicationId) async {
    final data = await _client
        .rpc('partner_application_submit', params: {'p_application_id': applicationId});
    return data.toString();
  }

  Future<void> respondPartnerInfo(String applicationId, String response) =>
      _client.rpc('partner_application_respond_info', params: {
        'p_application_id': applicationId,
        'p_response': response.trim(),
      });

  Future<void> withdrawPartnerApplication(String applicationId) =>
      _client.rpc('partner_application_withdraw', params: {'p_application_id': applicationId});

  Future<void> addPartnerDocument({
    required String applicationId,
    required String storagePath,
    required String docType,
    required String mimeType,
    required int sizeBytes,
  }) =>
      _client.rpc('partner_application_add_document', params: {
        'p_application_id': applicationId,
        'p_storage_path': storagePath,
        'p_doc_type': docType,
        'p_mime_type': mimeType,
        'p_size_bytes': sizeBytes,
      });
}
