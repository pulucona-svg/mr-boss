import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/notification.dart';
import 'package:mirror_laikipia/services/notification_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

/// Simulates the evaluation logic of firestore.rules for `/notifications/{notificationId}`.
///
/// Rule definition in firestore.rules:
/// ```
/// match /notifications/{notificationId} {
///   allow read: if isAdmin() || (
///     isAuthenticated() && (
///       !('target' in resource.data) ||
///       resource.data.target == 'all' ||
///       resource.data.target == request.auth.uid
///     )
///   );
///   allow create, update, delete: if isAdmin();
/// }
/// ```
class FirestoreNotificationSecurityRulesSimulator {
  static const Set<String> adminEmails = {
    'pulucona@mail.com',
    'pulucona@gmail.com',
    'culucona@gmail.com',
    'admin@mirrorlaikipia.ac.ke',
    'testadmin@mirror.com',
    'admin@mirror.com',
  };

  static bool isAdmin({
    required bool isAuthenticated,
    String? email,
    bool emailVerified = false,
    bool tokenAdmin = false,
    String? tokenRole,
    bool inAdminDoc = false,
  }) {
    if (!isAuthenticated) return false;
    if (tokenAdmin == true) return true;
    if (tokenRole == 'admin') return true;
    if (emailVerified && email != null && adminEmails.contains(email)) return true;
    if (inAdminDoc) return true;
    return false;
  }

  static bool evaluateRead({
    required bool isAuthenticated,
    String? uid,
    bool isAdminUser = false,
    required Map<String, dynamic> resourceData,
  }) {
    if (isAdminUser) return true;
    if (!isAuthenticated || uid == null) return false;

    // !('target' in resource.data)
    if (!resourceData.containsKey('target')) return true;

    final target = resourceData['target'];
    // resource.data.target == 'all'
    if (target == 'all') return true;

    // resource.data.target == request.auth.uid
    if (target == uid) return true;

    return false;
  }

  static bool evaluateWrite({
    required bool isAdminUser,
  }) {
    return isAdminUser;
  }

  /// Verifies whether a Firestore query satisfies the rule statically without PERMISSION_DENIED.
  ///
  /// In Firestore, an open query is rejected unless the user is an admin or the query filter
  /// guarantees all matching documents satisfy the security rule.
  static bool evaluateQuerySafety({
    required bool isAuthenticated,
    String? uid,
    bool isAdminUser = false,
    required List<String>? whereInTargets,
  }) {
    if (isAdminUser) return true;
    if (!isAuthenticated || uid == null) return false;

    // An unfiltered query would attempt to read any document in /notifications,
    // which violates the rule for regular users.
    if (whereInTargets == null || whereInTargets.isEmpty) {
      return false;
    }

    // A query filtering by `target in [...]` is safe if and only if EVERY target queried
    // is either 'all' or the authenticated user's own uid.
    for (final target in whereInTargets) {
      if (target != 'all' && target != uid) {
        return false;
      }
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    NotificationService.resetInstance();
  });

  group('Firestore Security Rules Verification for /notifications', () {
    const userA = 'user_abc_111';
    const userB = 'user_xyz_222';
    const adminUid = 'admin_super_999';

    final userANotification = {
      'id': 'notif_approve_res1',
      'type': 'materialApproved',
      'title': 'Material Approved',
      'target': userA,
      'createdAt': 1760000000000,
    };

    final userBNotification = {
      'id': 'notif_reject_res2',
      'type': 'materialRejected',
      'title': 'Material Declined',
      'target': userB,
      'createdAt': 1760000001000,
    };

    final broadcastNotification = {
      'id': 'notif_announcement_1',
      'type': 'adminGlobal',
      'title': 'Semester Registration Open',
      'target': 'all',
      'createdAt': 1760000002000,
    };

    final legacyNotificationWithoutTarget = {
      'id': 'notif_legacy_1',
      'type': 'adminGlobal',
      'title': 'Welcome to Mirror Digital',
      'createdAt': 1760000003000,
    };

    test('1. User A CANNOT read User B targeted notification', () {
      final allowed = FirestoreNotificationSecurityRulesSimulator.evaluateRead(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        resourceData: userBNotification,
      );
      expect(allowed, isFalse, reason: 'User A must be forbidden from reading User B notification');
    });

    test('2. User A CAN read their own targeted notification', () {
      final allowed = FirestoreNotificationSecurityRulesSimulator.evaluateRead(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        resourceData: userANotification,
      );
      expect(allowed, isTrue, reason: 'User A must be allowed to read their own notification');
    });

    test('3. Intended users CAN read broadcast notifications and legacy notifications', () {
      final canReadBroadcast = FirestoreNotificationSecurityRulesSimulator.evaluateRead(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        resourceData: broadcastNotification,
      );
      expect(canReadBroadcast, isTrue, reason: 'Broadcast notifications with target == all must be readable');

      final canReadLegacy = FirestoreNotificationSecurityRulesSimulator.evaluateRead(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        resourceData: legacyNotificationWithoutTarget,
      );
      expect(canReadLegacy, isTrue, reason: 'Legacy notifications without target field must remain readable');
    });

    test('4. Unauthenticated callers CANNOT read any notifications', () {
      expect(
        FirestoreNotificationSecurityRulesSimulator.evaluateRead(
          isAuthenticated: false,
          resourceData: userANotification,
        ),
        isFalse,
      );
      expect(
        FirestoreNotificationSecurityRulesSimulator.evaluateRead(
          isAuthenticated: false,
          resourceData: broadcastNotification,
        ),
        isFalse,
      );
    });

    test('5. Administrators retain required read access across ALL notifications', () {
      expect(
        FirestoreNotificationSecurityRulesSimulator.evaluateRead(
          isAuthenticated: true,
          uid: adminUid,
          isAdminUser: true,
          resourceData: userANotification,
        ),
        isTrue,
        reason: 'Admins must be able to read user A targeted notifications',
      );
      expect(
        FirestoreNotificationSecurityRulesSimulator.evaluateRead(
          isAuthenticated: true,
          uid: adminUid,
          isAdminUser: true,
          resourceData: userBNotification,
        ),
        isTrue,
        reason: 'Admins must be able to read user B targeted notifications',
      );
      expect(
        FirestoreNotificationSecurityRulesSimulator.evaluateRead(
          isAuthenticated: true,
          uid: adminUid,
          isAdminUser: true,
          resourceData: broadcastNotification,
        ),
        isTrue,
        reason: 'Admins must be able to read broadcast notifications',
      );
    });

    test('6. Unauthorized regular users CANNOT write or delete notifications', () {
      final regularUserCanWrite = FirestoreNotificationSecurityRulesSimulator.evaluateWrite(
        isAdminUser: false,
      );
      expect(regularUserCanWrite, isFalse, reason: 'Regular users must not write or update /notifications');

      final adminCanWrite = FirestoreNotificationSecurityRulesSimulator.evaluateWrite(
        isAdminUser: true,
      );
      expect(adminCanWrite, isTrue, reason: 'Authorized admins must be able to write /notifications');
    });
  });

  group('Firestore Client Query Compatibility Tests', () {
    const userA = 'user_abc_111';
    const adminUid = 'admin_super_999';

    test('7. Scoped query with whereIn: [all, currentUserId] statically satisfies the security rule', () {
      final safeQuery = FirestoreNotificationSecurityRulesSimulator.evaluateQuerySafety(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        whereInTargets: ['all', userA],
      );
      expect(safeQuery, isTrue, reason: 'Query restricted to [all, userA] must pass security rules');
    });

    test('8. Overbroad or cross-user query fails rule verification', () {
      final openQuery = FirestoreNotificationSecurityRulesSimulator.evaluateQuerySafety(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        whereInTargets: null,
      );
      expect(openQuery, isFalse, reason: 'Unfiltered collection queries must be rejected for non-admins');

      final foreignUserQuery = FirestoreNotificationSecurityRulesSimulator.evaluateQuerySafety(
        isAuthenticated: true,
        uid: userA,
        isAdminUser: false,
        whereInTargets: ['all', 'other_user_id'],
      );
      expect(foreignUserQuery, isFalse, reason: 'Query requesting other user ID must be rejected');
    });

    test('9. Admin open query (without whereIn) succeeds for administrator role', () {
      final adminOpenQuery = FirestoreNotificationSecurityRulesSimulator.evaluateQuerySafety(
        isAuthenticated: true,
        uid: adminUid,
        isAdminUser: true,
        whereInTargets: null,
      );
      expect(adminOpenQuery, isTrue, reason: 'Admins must be permitted to run open queries in admin console');
    });
  });

  group('NotificationService Client-Side Targeting & Isolation Tests', () {
    test('10. NotificationService isolates User A and User B targeted notifications', () {
      final service = NotificationService();
      service.setTestUserId('userA');

      final now = DateTime.now();
      final notifications = [
        AppNotification(
          id: 'notif_userA',
          type: NotificationType.materialApproved,
          senderName: 'Admin',
          resourceTitle: 'Computer Science Paper',
          target: 'userA',
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        AppNotification(
          id: 'notif_userB',
          type: NotificationType.materialRejected,
          senderName: 'Admin',
          resourceTitle: 'Biology Revision Guide',
          target: 'userB',
          timestamp: now.subtract(const Duration(minutes: 4)),
        ),
        AppNotification(
          id: 'notif_global',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Campus Power Shutdown',
          target: 'all',
          timestamp: now.subtract(const Duration(minutes: 3)),
        ),
        AppNotification(
          id: 'notif_legacy',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Welcome to Campus',
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
      ];

      service.handleTestSnapshot(notifications);

      // Verify User A receives only their notification, broadcast, and legacy notification
      expect(service.notifications.length, 3);
      expect(service.notifications.any((n) => n.id == 'notif_userA'), isTrue);
      expect(service.notifications.any((n) => n.id == 'notif_global'), isTrue);
      expect(service.notifications.any((n) => n.id == 'notif_legacy'), isTrue);
      expect(service.notifications.any((n) => n.id == 'notif_userB'), isFalse,
          reason: 'User B targeted notification must never be delivered to User A');

      // Now switch active user to User B
      NotificationService.resetInstance();
      final serviceB = NotificationService();
      serviceB.setTestUserId('userB');

      serviceB.handleTestSnapshot(notifications);

      expect(serviceB.notifications.length, 3);
      expect(serviceB.notifications.any((n) => n.id == 'notif_userB'), isTrue);
      expect(serviceB.notifications.any((n) => n.id == 'notif_global'), isTrue);
      expect(serviceB.notifications.any((n) => n.id == 'notif_legacy'), isTrue);
      expect(serviceB.notifications.any((n) => n.id == 'notif_userA'), isFalse,
          reason: 'User A targeted notification must never be delivered to User B');
    });
  });
}
