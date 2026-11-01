import 'package:bubbleapp/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccessSnapshot', () {
    test('Owner has all permissions implicitly', () {
      const s = AccessSnapshot(
        isOwner: true,
        isAdmin: true,
        permissions: <String>{},
        partnerPermissions: <String>{},
        roles: ['owner'],
        rank: 100,
      );
      expect(s.can('users.warn'), isTrue);
      expect(s.can('security.manage'), isTrue);
      expect(s.can('settings.manage'), isTrue);
    });

    test('Admin with granular permissions', () {
      const s = AccessSnapshot(
        isOwner: false,
        isAdmin: true,
        permissions: {'reports.manage', 'audit.read'},
        partnerPermissions: <String>{},
        roles: ['moderator'],
        rank: 40,
      );
      expect(s.can('reports.manage'), isTrue);
      expect(s.can('security.read'), isFalse);
      expect(s.can('billing.manage'), isFalse);
    });

    test('partner permissions never imply platform admin rights', () {
      const s = AccessSnapshot(
        isOwner: false,
        isAdmin: false,
        permissions: <String>{},
        partnerPermissions: {'partners.approve'},
        roles: ['partner'],
        rank: 10,
      );
      expect(s.partnerPermissions, contains('partners.approve'));
      expect(s.can('users.warn'), isFalse);
      expect(s.isAdmin, isFalse);
    });

    test('parses the my_access payload', () {
      final s = AccessSnapshot.fromJson({
        'is_owner': false,
        'is_admin': true,
        'permissions': ['users.read', 'users.warn'],
        'partner_permissions': ['announcements.read'],
        'roles': ['super_admin'],
        'rank': 80,
      });
      expect(s.isAdmin, isTrue);
      expect(s.can('users.read'), isTrue);
      expect(s.partnerPermissions, contains('announcements.read'));
      expect(s.rank, 80);
    });
  });

  group('OwnerStats', () {
    test('reads real numbers and defaults missing keys to zero', () {
      final stats = OwnerStats.fromJson({'total_users': 10, 'online_users': 2});
      expect(stats.get('total_users'), 10);
      expect(stats.get('online_users'), 2);
      expect(stats.get('missing'), 0);
    });
  });

  group('Platform settings', () {
    test('boolean settings keep their real value', () {
      final values = {'maintenance_mode': true, 'registration_enabled': false};
      expect(values['maintenance_mode'], isTrue);
      expect(values['registration_enabled'], isFalse);
    });
  });
}
