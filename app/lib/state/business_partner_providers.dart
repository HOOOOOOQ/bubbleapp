import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_partner_repository.dart';
import '../models/business_partner.dart';
import 'providers.dart';

/// Part 8 data layer. Providers are deliberately thin: they read from the
/// database, they never compute or cache a permission decision locally.
final businessPartnerRepositoryProvider = Provider<BusinessPartnerRepository>(
  (ref) => BusinessPartnerRepository(ref.watch(supabaseClientProvider)),
);

final activeAccountModeProvider = FutureProvider<ActiveAccountMode>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).activeAccountMode();
});

final myBusinessMembershipsProvider = FutureProvider<List<BusinessMembership>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).myBusinesses();
});

final businessProfileProvider =
    FutureProvider.autoDispose.family<BusinessProfile, String>((ref, businessId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).profile(businessId);
});

final businessPublicProfileProvider =
    FutureProvider.autoDispose.family<BusinessProfile, String>((ref, businessId) {
  return ref.watch(businessPartnerRepositoryProvider).publicProfile(businessId);
});

final businessSetupProgressProvider =
    FutureProvider.autoDispose.family<BusinessSetupProgress, String>((ref, businessId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).setupProgress(businessId);
});

final businessTeamProvider =
    FutureProvider.autoDispose.family<BusinessTeam, String>((ref, businessId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).team(businessId);
});

final myBusinessInvitesProvider = FutureProvider<List<BusinessInviteInboxItem>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).myInvites();
});

/// Catalog filters kept in one value so the family cache is keyed by the query.
class CatalogQuery {
  const CatalogQuery(
    this.businessId, {
    this.search,
    this.kind,
    this.status,
    this.publicOnly = false,
  });

  final String businessId;
  final String? search;
  final String? kind;
  final String? status;
  final bool publicOnly;

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.businessId == businessId &&
      other.search == search &&
      other.kind == kind &&
      other.status == status &&
      other.publicOnly == publicOnly;

  @override
  int get hashCode => Object.hash(businessId, search, kind, status, publicOnly);
}

final businessCatalogProvider =
    FutureProvider.autoDispose.family<List<BusinessCatalogItem>, CatalogQuery>((ref, query) {
  ref.watch(sessionProvider);
  final repo = ref.watch(businessPartnerRepositoryProvider);
  return query.publicOnly
      ? repo.publicCatalog(query.businessId, search: query.search, kind: query.kind)
      : repo.catalog(query.businessId, search: query.search, kind: query.kind, status: query.status);
});

final catalogDetailProvider =
    FutureProvider.autoDispose.family<CatalogDetail, String>((ref, itemId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).catalogDetail(itemId);
});

final businessAnalyticsProvider =
    FutureProvider.autoDispose.family<BusinessAnalytics, (String, int)>((ref, arg) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).analytics(arg.$1, days: arg.$2);
});

final businessInquiriesProvider =
    FutureProvider.autoDispose.family<List<BusinessInquiry>, (String, String?)>((ref, arg) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).inquiries(arg.$1, status: arg.$2);
});

final myBusinessInquiriesProvider = FutureProvider<List<BusinessInquiry>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).myInquiries();
});

final inquiryDetailProvider =
    FutureProvider.autoDispose.family<BusinessInquiryDetail, String>((ref, inquiryId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).inquiryDetail(inquiryId);
});

final businessCustomersProvider =
    FutureProvider.autoDispose.family<List<BusinessCustomer>, (String, String?)>((ref, arg) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).customers(arg.$1, search: arg.$2);
});

/// Labels are read from the table because the RPC layer only exposes create and
/// delete; RLS already scopes the rows to the business team.
final businessLabelsProvider =
    FutureProvider.autoDispose.family<List<CustomerLabel>, String>((ref, businessId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).labels(businessId);
});

final businessVerificationProvider =
    FutureProvider.autoDispose.family<BusinessVerificationState, String>((ref, businessId) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).businessVerification(businessId);
});

final partnerWorkspaceProvider = FutureProvider<PartnerWorkspace?>((ref) async {
  if (ref.watch(sessionProvider) == null) return null;
  return ref.watch(businessPartnerRepositoryProvider).partnerWorkspace();
});

final myPartnerProfileProvider = FutureProvider<PartnerOwnProfile?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).myPartnerProfile();
});

final partnerResourcesProvider = FutureProvider<List<PartnerResource>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).partnerResources();
});

final partnerSupportProvider = FutureProvider<List<PartnerSupportRequest>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).partnerSupport();
});

final partnerActivityProvider = FutureProvider<List<PartnerActivityEntry>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).partnerActivity();
});

class PartnerDirectoryQuery {
  const PartnerDirectoryQuery({this.search, this.category, this.featuredOnly = false});

  final String? search;
  final String? category;
  final bool featuredOnly;

  @override
  bool operator ==(Object other) =>
      other is PartnerDirectoryQuery &&
      other.search == search &&
      other.category == category &&
      other.featuredOnly == featuredOnly;

  @override
  int get hashCode => Object.hash(search, category, featuredOnly);
}

final partnerDirectoryProvider =
    FutureProvider.autoDispose.family<PartnerDirectory, PartnerDirectoryQuery>((ref, query) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).partnerDirectory(
        search: query.search,
        category: query.category,
        featuredOnly: query.featuredOnly,
      );
});

final partnerPublicProfileProvider =
    FutureProvider.autoDispose.family<PartnerPublicProfile?, String>((ref, userId) {
  return ref.watch(businessPartnerRepositoryProvider).partnerPublicProfile(userId);
});

final partnerRequirementsProvider = FutureProvider<PartnerApplicationRequirements>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).partnerRequirements();
});

final myPartnerApplicationsProvider = FutureProvider<List<PartnerApplicationRecord>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(businessPartnerRepositoryProvider).myPartnerApplications();
});
