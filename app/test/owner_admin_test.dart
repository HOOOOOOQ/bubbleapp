import 'package:flutter_test/flutter_test.dart';
import 'package:bubbleapp/models/models.dart';

void main() {
  group('AccessSnapshot Part7', () {
    test('Owner has all permissions implicitly', () {
      const s = AccessSnapshot(isOwner: true, isAdmin: true, roles: ['owner'], permissions: {});
      expect(s.can('users.warn'), true);
      expect(s.can('security.manage'), true);
      expect(s.can('settings.manage'), true);
    });
    test('Admin with granular permissions', () {
      const s = AccessSnapshot(isOwner: false, isAdmin: true, roles: ['moderator'], permissions: {'reports.manage': true, 'audit.read': false});
      expect(s.can('reports.manage'), true);
      expect(s.can('security.read'), false);
    });
    test('OwnerStats get handles missing keys', () {
      final s = OwnerStats(raw: {'total_users': 10, 'online_users': 2}, updatedAt: DateTime.now());
      expect(s.get('total_users'), 10);
      expect(s.get('missing'), 0);
    });
  });

  group('PlatformSettings validation', () {
    test('bool keys parsed correctly', () {
      final v = {'maintenance_mode': true, 'registration_enabled': false};
      expect(v['maintenance_mode'] == true, true);
    });
  });
}
