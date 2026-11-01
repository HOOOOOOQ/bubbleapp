import 'package:bubbleapp/models/business_partner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActiveAccountMode', () {
    test('defaults to personal when the row is missing', () {
      const mode = ActiveAccountMode.personal;
      expect(mode.mode, AccountMode.personal);
      expect(mode.isBusiness, isFalse);
    });

    test('parses business mode with the active business id', () {
      final mode = ActiveAccountMode.fromJson({
        'active_account_mode': 'business',
        'active_business_id': 'biz-1',
      });
      expect(mode.mode, AccountMode.business);
      expect(mode.isBusiness, isTrue);
      expect(mode.businessId, 'biz-1');
    });

    test('business mode without a business id is not active', () {
      final mode = ActiveAccountMode.fromJson({'active_account_mode': 'business'});
      expect(mode.isBusiness, isFalse);
    });
  });

  group('BusinessMembership', () {
    final json = {
      'id': 'b1',
      'name': 'Alpha Studio',
      'username': 'alpha_studio',
      'category': 'Retail',
      'role': 'support',
      'status': 'open',
      'permissions': ['inquiries.reply', 'customers.view'],
      'is_verified': true,
      'is_setup_complete': true,
      'member_status': 'active',
      'open_inquiries': 3,
      'followers_count': 120,
      'pending_invites': 1,
      'description': 'Design studio',
      'logo_url': 'https://cdn.test/logo.png',
    };

    test('parses the RPC row', () {
      final m = BusinessMembership.fromJson(json);
      expect(m.name, 'Alpha Studio');
      expect(m.openInquiries, 3);
      expect(m.followersCount, 120);
      expect(m.isVerified, isTrue);
      expect(m.permissions, contains('inquiries.reply'));
    });

    test('granular permissions never escalate', () {
      final m = BusinessMembership.fromJson(json);
      expect(m.can('inquiries.reply'), isTrue);
      expect(m.can('catalog.manage'), isFalse);
      expect(m.can('business.delete'), isFalse);
    });

    test('owner implicitly holds every permission, including owner-only ones', () {
      final owner = BusinessMembership.fromJson({
        ...json,
        'role': 'owner',
        'permissions': <String>[],
      });
      expect(owner.isOwner, isTrue);
      expect(owner.can('business.delete'), isTrue);
      expect(owner.can('team.manage'), isTrue);
    });
  });

  group('BusinessProfile', () {
    final json = {
      'id': 'b1',
      'name': 'Alpha Studio',
      'username': 'alpha_studio',
      'description': 'We design things',
      'category': 'Retail',
      'status': 'open',
      'is_verified': false,
      'is_setup_complete': true,
      'is_member': true,
      'is_following': false,
      'followers_count': 12,
      'catalog_count': 4,
      'accepts_inquiries': true,
      'my_role': 'admin',
      'my_permissions': ['profile.edit'],
      'visibility': {'show_email': false, 'show_phone': false},
      'social_links': {'instagram': 'https://instagram.com/alpha'},
      'working_hours': {'mon': '09:00-17:00'},
      'contact_email': 'hello@alpha.test',
    };

    test('visibility flags control what the page shows', () {
      final p = BusinessProfile.fromJson(json);
      expect(p.showEmail, isFalse);
      expect(p.showPhone, isFalse);
      expect(p.socialLinks['instagram'], 'https://instagram.com/alpha');
      expect(p.workingHours['mon'], '09:00-17:00');
    });

    test('permissions are scoped to the membership', () {
      final p = BusinessProfile.fromJson(json);
      expect(p.can('profile.edit'), isTrue);
      expect(p.can('team.manage'), isFalse);
    });

    test('email is shown by default when visibility is absent', () {
      final p = BusinessProfile.fromJson({...json, 'visibility': <String, dynamic>{}});
      expect(p.showEmail, isTrue);
    });

    test('visitor payload has no role or permissions', () {
      final p = BusinessProfile.fromJson({
        ...json,
        'is_member': false,
        'my_role': null,
        'my_permissions': <String>[],
      });
      expect(p.isMember, isFalse);
      expect(p.myRole, isEmpty);
      expect(p.can('profile.edit'), isFalse);
    });
  });

  group('Catalog', () {
    test('draft maps to the exact RPC parameter names', () {
      final draft = CatalogDraft(
        itemId: 'item-1',
        kind: 'service',
        name: '  Packaging audit ',
        description: ' Review ',
        category: 'Design',
        priceMinor: 150000,
        currency: 'USD',
        gallery: const ['https://cdn.test/a.png'],
        status: 'published',
        stockQuantity: 2,
        variants: const [CatalogVariant(name: 'Standard', priceMinor: 150000)],
      );
      final params = draft.toParams('biz-1');
      expect(params.keys, containsAll([
        'p_business_id',
        'p_item_id',
        'p_kind',
        'p_name',
        'p_description',
        'p_category',
        'p_price_minor',
        'p_currency',
        'p_image_url',
        'p_gallery',
        'p_status',
        'p_stock_quantity',
        'p_external_url',
        'p_variants',
      ]));
      expect(params['p_business_id'], 'biz-1');
      expect(params['p_name'], 'Packaging audit');
      expect(params['p_description'], 'Review');
      expect(params['p_variants'], [
        {'name': 'Standard', 'price_minor': 150000}
      ]);
    });

    test('variant omits a null price instead of sending zero', () {
      expect(const CatalogVariant(name: 'Quote only').toJson(), {'name': 'Quote only'});
    });

    test('item parses gallery, variants and counters', () {
      final item = BusinessCatalogItem.fromJson({
        'id': 'i1',
        'business_id': 'b1',
        'kind': 'product',
        'name': 'Brand Sprint',
        'description': '',
        'category': 'Design',
        'currency': 'IDR',
        'status': 'published',
        'is_active': true,
        'gallery': ['https://cdn.test/a.png'],
        'variants': [
          {'name': 'Standard', 'price_minor': 4500000},
          {'name': 'Extended', 'price_minor': 7500000},
        ],
        'view_count': 12,
        'share_count': 3,
        'price_minor': 4500000,
        'stock_quantity': 5,
      });
      expect(item.isPublished, isTrue);
      expect(item.variants.length, 2);
      expect(item.variants[1].priceMinor, 7500000);
      expect(item.viewCount, 12);
      expect(item.shareCount, 3);
      expect(item.priceLabel, 'IDR 45000');
    });

    test('catalog detail carries server permission flags', () {
      final detail = CatalogDetail.fromJson({
        'id': 'i1',
        'business_id': 'b1',
        'kind': 'product',
        'name': 'Item',
        'status': 'draft',
        'gallery': <String>[],
        'variants': <Object>[],
        'currency': 'IDR',
        'can_manage': false,
        'can_message': true,
      });
      expect(detail.canManage, isFalse);
      expect(detail.canMessage, isTrue);
    });
  });

  group('BusinessAnalytics', () {
    final json = {
      'period_days': 30,
      'metrics': {
        'profile_views': 40,
        'catalog_views': 12,
        'inquiries': 3,
        'published_items': 2,
      },
      'previous': {'profile_views': 20, 'catalog_views': 0, 'inquiries': 0},
      'series': [
        {'day': '2026-10-01', 'profile_views': 4, 'catalog_views': 1, 'inquiries': 0},
        {'day': '2026-10-02', 'profile_views': 6, 'catalog_views': 2, 'inquiries': 1},
      ],
      'response': {
        'available': true,
        'answered': 2,
        'unanswered': 1,
        'avg_first_response_minutes': 12.5,
        'resolution_rate': 50.0,
      },
      'unavailable': [
        {'metric': 'paid_ad_reach', 'reason': 'Ads are not implemented'},
      ],
    };

    test('parses real metrics and response statistics', () {
      final a = BusinessAnalytics.fromJson(json);
      expect(a.metric('profile_views'), 40);
      expect(a.previousMetric('profile_views'), 20);
      expect(a.change('profile_views'), 100);
      expect(a.response.avgFirstResponseMinutes, 12.5);
      expect(a.response.available, isTrue);
      expect(a.series.length, 2);
      expect(a.series.first.profileViews, 4);
    });

    test('unavailable metrics are surfaced, never fabricated', () {
      final a = BusinessAnalytics.fromJson(json);
      expect(a.unavailable.single['metric'], 'paid_ad_reach');
      expect(a.metric('paid_ad_reach'), 0);
    });

    test('change is null when there is no previous baseline', () {
      final a = BusinessAnalytics.fromJson(json);
      expect(a.change('catalog_views'), isNull);
    });

    test('missing response block degrades safely', () {
      final a = BusinessAnalytics.fromJson({...json, 'response': <String, dynamic>{}});
      expect(a.response.available, isFalse);
      expect(a.response.answered, 0);
    });
  });

  group('Inquiries and customers', () {
    final inquiryJson = {
      'id': 'q1',
      'business_id': 'b1',
      'customer_id': 'u1',
      'conversation_id': 'c1',
      'subject': 'About Brand Sprint',
      'status': 'open',
      'priority': 'high',
      'message_count': 4,
      'can_manage': true,
      'customer_verified': false,
      'customer_name': 'Customer One',
      'customer_username': 'cust_one',
      'catalog_item_name': 'Brand Sprint',
      'last_message': 'Is it available?',
      'first_response_at': '2026-10-01T10:00:00Z',
    };

    test('parses the inquiry board row', () {
      final i = BusinessInquiry.fromJson(inquiryJson);
      expect(i.isOpen, isTrue);
      expect(i.priority, 'high');
      expect(i.messageCount, 4);
      expect(i.catalogItemName, 'Brand Sprint');
      expect(i.canManage, isTrue);
      expect(i.firstResponseAt, isNotNull);
    });

    test('detail hides the customer record for non-staff', () {
      final detail = BusinessInquiryDetail.fromJson({
        ...inquiryJson,
        'is_customer': true,
        'can_view_customer': false,
        'customer_record': null,
      });
      expect(detail.customerRecord, isNull);
      expect(detail.isCustomer, isTrue);
    });

    test('detail parses the internal record for staff', () {
      final detail = BusinessInquiryDetail.fromJson({
        ...inquiryJson,
        'customer_record': {
          'internal_note': 'Prefers WhatsApp',
          'follow_up_status': 'follow_up',
          'inquiry_count': 2,
          'open_inquiries': 1,
        },
      });
      expect(detail.customerRecord!.internalNote, 'Prefers WhatsApp');
      expect(detail.customerRecord!.followUpStatus, 'follow_up');
    });

    test('inquiry start result exposes the conversation to open', () {
      final r = InquiryStartResult.fromJson({
        'conversation_id': 'c1',
        'inquiry_id': 'q1',
        'business_id': 'b1',
        'subject': 'Message to Alpha Studio',
      });
      expect(r.conversationId, 'c1');
      expect(r.inquiryId, 'q1');
    });

    test('customer parses labels with usage', () {
      final customer = BusinessCustomer.fromJson({
        'id': 'cu1',
        'business_id': 'b1',
        'user_id': 'u1',
        'display_name': 'Customer One',
        'username': 'cust_one',
        'is_verified': false,
        'internal_note': 'Prefers WhatsApp',
        'follow_up_status': 'follow_up',
        'inquiry_count': 1,
        'open_inquiries': 0,
        'labels': [
          {'id': 'l1', 'name': 'VIP', 'color': '#16A34A', 'usage': 3},
        ],
      });
      expect(customer.labels.single.name, 'VIP');
      expect(customer.labels.single.color, '#16A34A');
    });

    test('label parses the assignment counter', () {
      final label = CustomerLabel.fromJson({'id': 'l1', 'name': 'VIP', 'color': '#16A34A', 'usage': 2});
      expect(label.usage, 2);
    });
  });

  group('Business team', () {
    test('team parses members, invites and the permission catalog', () {
      final team = BusinessTeam.fromJson({
        'can_manage': true,
        'members': [
          {
            'user_id': 'u1',
            'display_name': 'Alpha Owner',
            'username': 'alpha_owner',
            'role': 'owner',
            'status': 'active',
            'permissions': ['business.delete'],
            'is_verified': false,
          },
        ],
        'invites': [
          {
            'id': 'i1',
            'invited_user_id': 'u2',
            'display_name': 'New Member',
            'username': 'new_member',
            'role': 'support',
            'status': 'pending',
          },
        ],
        'permission_catalog': [
          {
            'key': 'catalog.manage',
            'label': 'Manage catalog',
            'category': 'catalog',
            'description': 'Create listings',
            'owner_only': false,
          },
          {
            'key': 'business.delete',
            'label': 'Delete business',
            'category': 'settings',
            'description': 'Remove everything',
            'owner_only': true,
          },
        ],
      });
      expect(team.canManage, isTrue);
      expect(team.members.single.role, 'owner');
      expect(team.invites.single.username, 'new_member');
      expect(team.permissionCatalog.last.ownerOnly, isTrue);
    });

    test('invite inbox parses the business name and inviter', () {
      final invite = BusinessInviteInboxItem.fromJson({
        'id': 'i1',
        'business_id': 'b1',
        'business_name': 'Alpha Studio',
        'business_username': 'alpha_studio',
        'business_verified': true,
        'role': 'support',
        'invited_by': 'Alpha Owner',
        'expires_at': '2026-11-08T10:00:00Z',
        'note': 'Help with the inbox',
      });
      expect(invite.businessName, 'Alpha Studio');
      expect(invite.invitedByName, 'Alpha Owner');
      expect(invite.businessVerified, isTrue);
    });
  });

  group('Business verification', () {
    test('pending application blocks a second submission', () {
      final state = BusinessVerificationState.fromJson({
        'business_id': 'b1',
        'is_verified': false,
        'can_submit': false,
        'can_manage': true,
        'requirements': {'summary': 'Business details required'},
        'application': {'id': 'a1', 'status': 'pending', 'decision_note': null},
        'history': [
          {'id': 1, 'action': 'submitted', 'to_status': 'pending'},
        ],
        'documents': <Object>[],
      });
      expect(state.canSubmit, isFalse);
      expect(state.status, 'pending');
      expect(state.history.single.action, 'submitted');
    });

    test('verified business reports its badge from the backend only', () {
      final state = BusinessVerificationState.fromJson({
        'business_id': 'b1',
        'is_verified': true,
        'can_submit': false,
        'can_manage': true,
        'requirements': <String, dynamic>{},
        'application': null,
        'history': <Object>[],
        'documents': <Object>[],
      });
      expect(state.isVerified, isTrue);
      expect(state.application, isNull);
    });
  });

  group('Partner workspace', () {
    final json = {
      'partner_status': 'active',
      'is_featured': true,
      'is_badge_visible': true,
      'announcements': 2,
      'resources_count': 5,
      'open_support_requests': 1,
      'featured_until': '2026-12-01T00:00:00Z',
      'benefits': [
        {
          'key': 'badge',
          'title': 'Partner badge',
          'description': 'Badge on your profile',
          'enabled': true,
          'granted': true,
          'is_public': true,
        },
        {
          'key': 'resources',
          'title': 'Resources',
          'description': 'Library',
          'enabled': false,
          'granted': true,
          'is_public': true,
        },
      ],
      'activity': [
        {'kind': 'approved', 'summary': 'Partner application approved'},
      ],
      'not_implemented': [
        {'key': 'revenue_share', 'reason': 'Payouts are not implemented'},
      ],
    };

    test('parses benefits and activity', () {
      final w = PartnerWorkspace.fromJson(json);
      expect(w.isActivePartner, isTrue);
      expect(w.isFeatured, isTrue);
      expect(w.benefits.length, 2);
      expect(w.activity.single.kind, 'approved');
      expect(w.notImplemented.single['key'], 'revenue_share');
    });

    test('a disabled benefit is never reported as usable', () {
      final w = PartnerWorkspace.fromJson(json);
      expect(w.canUse('badge'), isTrue);
      expect(w.canUse('resources'), isFalse);
      expect(w.canUse('unknown'), isFalse);
    });
  });

  group('Partner directory and applications', () {
    test('directory parses categories and partner cards', () {
      final directory = PartnerDirectory.fromJson({
        'enabled': true,
        'categories': ['Agency', 'Creator'],
        'partners': [
          {
            'user_id': 'u5',
            'display_name': 'Partner One Studio',
            'username': 'partner_one',
            'headline': 'Creator partnerships',
            'bio': 'We build campaigns',
            'specialties': ['Creators', 'Retail'],
            'partner_category': 'Agency',
            'is_featured': true,
            'is_verified': false,
            'is_badge_visible': true,
            'can_message': true,
          },
        ],
      });
      expect(directory.enabled, isTrue);
      expect(directory.partners.single.displayName, 'Partner One Studio');
      expect(directory.partners.single.specialties, ['Creators', 'Retail']);
      expect(directory.partners.single.canMessage, isTrue);
      expect(directory.categories, contains('Creator'));
    });

    test('requirements explain eligibility and cooldown', () {
      final req = PartnerApplicationRequirements.fromJson({
        'is_open': true,
        'can_apply': false,
        'reason': 'Your account is too new',
        'categories': ['Agency'],
        'requirements': 'Describe your work',
        'min_account_age_days': 7,
        'cooldown_days': 7,
      });
      expect(req.isOpen, isTrue);
      expect(req.canApply, isFalse);
      expect(req.reason, 'Your account is too new');
      expect(req.minAccountAgeDays, 7);
    });

    test('application record flags a request for more information', () {
      final app = PartnerApplicationRecord.fromJson({
        'id': 'a1',
        'organization': 'Partner Co',
        'partnership_category': 'Agency',
        'status': 'additional_info_required',
        'proposal': 'We work with creators',
        'info_requested': 'Share your registration number',
        'submitted_at': '2026-10-01T10:00:00Z',
      });
      expect(app.needsInfo, isTrue);
      expect(app.isEditable, isFalse);
      expect(app.infoRequested, 'Share your registration number');
    });

    test('own partner profile exposes directory visibility', () {
      final profile = PartnerOwnProfile.fromJson({
        'user_id': 'u5',
        'partner_status': 'active',
        'partner_category': 'Agency',
        'display_name': 'Partner One Studio',
        'headline': 'Creator partnerships',
        'bio': '',
        'specialties': ['Creators'],
        'directory_visible': false,
        'badge_enabled': true,
        'is_featured': false,
      });
      expect(profile.directoryVisible, isFalse);
      expect(profile.specialties, ['Creators']);
      expect(profile.isBadgeVisible, isTrue);
    });
  });
}
