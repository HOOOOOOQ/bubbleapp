import 'package:bubbleapp/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile', () {
    test('parses directory columns and never exposes email when absent', () {
      final p = UserProfile.fromJson({
        'id': 'u1',
        'username': 'alice',
        'display_name': 'Alice',
        'bio': '',
        'account_status': 'active',
        'is_verified': true,
      });
      expect(p.username, 'alice');
      expect(p.isVerified, isTrue);
      expect(p.email, isNull);
    });

    test('flags temporary usernames so the UI can prompt for a real one', () {
      final p = UserProfile.fromJson({'id': 'u1', 'username': 'user_0123456789abcdef'});
      expect(p.needsProfileSetup, isTrue);
    });

    test('missing fields fall back to safe defaults instead of throwing', () {
      final p = UserProfile.fromJson({'id': 'u1'});
      expect(p.username, '');
      expect(p.accountStatus, 'active');
      expect(p.isVerified, isFalse);
    });
  });

  group('AccessSnapshot', () {
    test('owner can do everything the UI gates on', () {
      final a = AccessSnapshot.fromJson({'is_owner': true, 'permissions': <String>[]});
      expect(a.can('users.manage'), isTrue);
      expect(a.can('audit.read'), isTrue);
    });

    test('non-owner only holds listed permissions', () {
      final a = AccessSnapshot.fromJson({
        'is_owner': false,
        'is_admin': true,
        'permissions': ['users.read'],
        'partner_permissions': ['partner.portal'],
        'rank': 50,
      });
      expect(a.can('users.read'), isTrue);
      expect(a.can('users.manage'), isFalse);
      // Partner-scoped rights are kept separate from platform rights.
      expect(a.partnerPermissions, contains('partner.portal'));
      expect(a.can('partner.portal'), isFalse);
    });

    test('empty snapshot grants nothing', () {
      expect(AccessSnapshot.empty.can('users.read'), isFalse);
      expect(AccessSnapshot.empty.isOwner, isFalse);
    });
  });

  group('VerificationApplication', () {
    test('open statuses are pending, under review and info requested', () {
      VerificationApplication withStatus(String s) =>
          VerificationApplication.fromJson({'id': '1', 'status': s});
      expect(withStatus('pending').isOpen, isTrue);
      expect(withStatus('under_review').isOpen, isTrue);
      expect(withStatus('info_requested').isOpen, isTrue);
      expect(withStatus('approved').isOpen, isFalse);
      expect(withStatus('revoked').isOpen, isFalse);
    });
  });

  group('ChannelModel', () {
    test('official mandatory channel is read from flags, not from its id', () {
      final c = ChannelModel.fromJson({
        'id': 'any-uuid',
        'username': 'bubbleapp',
        'is_official': true,
        'is_mandatory': true,
        'subscriber_count': 12,
      });
      expect(c.isOfficial, isTrue);
      expect(c.isMandatory, isTrue);
      expect(c.subscriberCount, 12);
    });
  });

  group('PartnerDashboard', () {
    test('reads status, rights and reason from partner_dashboard()', () {
      final d = PartnerDashboard.fromJson({
        'partner_status': 'suspended',
        'partner_category': 'Media',
        'display_name': 'Studio',
        'announcements': 3,
        'permissions': ['partner.portal'],
        'status_reason': 'Policy review',
      });
      expect(d.status, 'suspended');
      expect(d.permissions, ['partner.portal']);
      expect(d.statusReason, 'Policy review');
    });
  });
}
