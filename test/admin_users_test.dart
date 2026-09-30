import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/admin_user_model.dart';
import 'package:mirror_laikipia/screens/admin/admin_menu_bottom_sheet.dart';
import 'package:mirror_laikipia/screens/admin/admin_user_detail_screen.dart';
import 'package:mirror_laikipia/screens/admin/admin_users_screen.dart';
import 'package:mirror_laikipia/services/admin_service.dart';
import 'package:mirror_laikipia/services/admin_users_service.dart';

class FakeAdminUsersService extends AdminUsersService {
  final AdminUserFullProfile? profileToReturn;
  final Completer<AdminUserFullProfile>? completer;
  final List<AdminUserSummary>? usersToReturn;
  final String? nextPageTokenToReturn;

  FakeAdminUsersService({
    this.profileToReturn,
    this.completer,
    this.usersToReturn,
    this.nextPageTokenToReturn,
  }) : super.internal();

  @override
  Future<({List<AdminUserSummary> users, String? nextPageToken})> getUsersList({
    int pageSize = 25,
    String? pageToken,
    String? searchQuery,
    String roleFilter = 'all',
  }) async {
    return (
      users: usersToReturn ?? [],
      nextPageToken: nextPageTokenToReturn,
    );
  }

  @override
  Future<AdminUserFullProfile> getUserDetail(String targetUid) async {
    if (completer != null) {
      return completer!.future;
    }
    if (profileToReturn != null) {
      return profileToReturn!;
    }
    throw Exception('User not found');
  }

  @override
  Future<Map<String, dynamic>> toggleUserDisabled(
    String targetUid,
    bool disabled, {
    String? reason,
  }) async {
    return {
      'success': true,
      'disabled': disabled,
      'message': disabled ? 'User disabled' : 'User enabled',
    };
  }
}

void main() {
  group('1. AdminUserSummary Model Tests', () {
    test('parses complete map and matches fields', () {
      final map = {
        'uid': 'user_123',
        'email': 'student@laikipia.ac.ke',
        'displayName': 'Jane Doe',
        'phoneNumber': '+254712345678',
        'photoUrl': 'https://example.com/avatar.jpg',
        'role': 'admin',
        'institution': 'Laikipia University',
        'program': 'Computer Science',
        'programCode': 'COMS',
        'year': '3',
        'semester': '2',
        'hasActiveSubscription': true,
        'disabled': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'lastLogin': '2026-01-02T00:00:00.000Z',
      };

      final summary = AdminUserSummary.fromMap(map);

      expect(summary.uid, equals('user_123'));
      expect(summary.email, equals('student@laikipia.ac.ke'));
      expect(summary.displayName, equals('Jane Doe'));
      expect(summary.username, equals('Jane Doe'));
      expect(summary.phone, equals('+254712345678'));
      expect(summary.institution, equals('Laikipia University'));
      expect(summary.program, equals('Computer Science'));
      expect(summary.programCode, equals('COMS'));
      expect(summary.year, equals('3'));
      expect(summary.semester, equals('2'));
      expect(summary.isAdmin, isTrue);
      expect(summary.hasActiveSubscription, isTrue);
      expect(summary.disabled, isFalse);
      expect(summary.createdAt, isNotNull);
      expect(summary.lastLogin, isNotNull);
    });

    test('handles missing and null fields with graceful fallbacks', () {
      final map = <String, dynamic>{
        'uid': 'user_min',
      };

      final summary = AdminUserSummary.fromMap(map);

      expect(summary.uid, equals('user_min'));
      expect(summary.email, equals(''));
      expect(summary.displayName, equals('User'));
      expect(summary.phone, equals(''));
      expect(summary.institution, equals(''));
      expect(summary.program, equals(''));
      expect(summary.isAdmin, isFalse);
      expect(summary.hasActiveSubscription, isFalse);
      expect(summary.disabled, isFalse);
      expect(summary.createdAt, isNull);
      expect(summary.lastLogin, isNull);
    });

    test('identifies disabled and admin variations', () {
      final disabledMap = {
        'uid': 'user_dis',
        'disabled': true,
        'role': 'ADMIN',
      };
      final summary = AdminUserSummary.fromMap(disabledMap);
      expect(summary.disabled, isTrue);
      expect(summary.isAdmin, isTrue);
    });
  });

  group('2. AdminUserDetail Model Tests', () {
    test('parses full academic personalization and identity fields', () {
      final map = {
        'uid': 'detail_user_1',
        'username': 'Alex Kip',
        'email': 'alex@laikipia.ac.ke',
        'photoURL': 'https://example.com/pic.jpg',
        'institution': 'Laikipia University',
        'universityLocation': 'Main Campus',
        'program': 'Information Technology',
        'programCode': 'BIT',
        'year': '2',
        'semester': '1',
        'phone': '0700112233',
        'authProvider': 'password',
        'emailVerified': true,
        'onboardingComplete': true,
        'disabled': false,
        'isAdmin': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'lastLogin': '2026-01-03T00:00:00.000Z',
      };

      final detail = AdminUserDetail.fromMap(map);

      expect(detail.uid, equals('detail_user_1'));
      expect(detail.displayName, equals('Alex Kip'));
      expect(detail.email, equals('alex@laikipia.ac.ke'));
      expect(detail.institution, equals('Laikipia University'));
      expect(detail.universityLocation, equals('Main Campus'));
      expect(detail.program, equals('Information Technology'));
      expect(detail.programCode, equals('BIT'));
      expect(detail.year, equals('2'));
      expect(detail.semester, equals('1'));
      expect(detail.phone, equals('0700112233'));
      expect(detail.authProvider, equals('password'));
      expect(detail.emailVerified, isTrue);
      expect(detail.onboardingComplete, isTrue);
      expect(detail.disabled, isFalse);
      expect(detail.isAdmin, isFalse);
    });
  });

  group('3. AdminUserSubscription Model Tests', () {
    test('parses active subscription record correctly', () {
      final map = {
        'id': 'sub_001',
        'packageTitle': 'Monthly Pro',
        'amount': 250.0,
        'transactionCode': 'MPESA12345',
        'paystackReference': 'PAY_REF_999',
        'status': 'active',
        'purchaseDate': '2026-01-01T00:00:00.000Z',
        'activationDate': '2026-01-01T00:00:00.000Z',
        'expiryDate': '2026-01-31T00:00:00.000Z',
        'downloadCount': 12,
      };

      final sub = AdminUserSubscription.fromMap(map);

      expect(sub.id, equals('sub_001'));
      expect(sub.packageName, equals('Monthly Pro'));
      expect(sub.amount, equals(250.0));
      expect(sub.transactionCode, equals('MPESA12345'));
      expect(sub.paystackReference, equals('PAY_REF_999'));
      expect(sub.isActive, isTrue);
      expect(sub.downloadCount, equals(12));
    });

    test('parses expired and queued subscriptions', () {
      final expired = AdminUserSubscription.fromMap({
        'id': 'sub_exp',
        'status': 'expired',
      });
      expect(expired.isActive, isFalse);
      expect(expired.status, equals('expired'));

      final queued = AdminUserSubscription.fromMap({
        'id': 'sub_que',
        'status': 'queued',
      });
      expect(queued.isActive, isFalse);
      expect(queued.status, equals('queued'));
    });
  });

  group('4. AdminUserPayment Model Tests', () {
    test('parses safe payment audit records', () {
      final map = {
        'reference': 'PAY_AUDIT_101',
        'packageName': 'Semester Pass',
        'expectedAmountKes': 500.0,
        'paymentMethod': 'mobile_money',
        'phoneNumber': '0712***78',
        'status': 'success',
        'fulfilled': true,
        'failureReason': null,
        'operatorReceiptNumber': 'NL782190',
        'createdAt': '2026-01-01T00:00:00.000Z',
      };

      final payment = AdminUserPayment.fromMap(map);

      expect(payment.reference, equals('PAY_AUDIT_101'));
      expect(payment.packageName, equals('Semester Pass'));
      expect(payment.amount, equals(500.0));
      expect(payment.expectedAmountKes, equals(500.0));
      expect(payment.paymentMethod, equals('mobile_money'));
      expect(payment.status, equals('success'));
      expect(payment.fulfilled, isTrue);
      expect(payment.operatorReceiptNumber, equals('NL782190'));
    });

    test('guarantees sensitive card details and secrets are omitted', () {
      final mapWithForbiddenFields = {
        'reference': 'PAY_SAFE',
        'expectedAmountKes': 100.0,
        'secretKey': 'sk_live_hidden_secret',
        'cvv': '123',
        'cardNumber': '4111222233334444',
      };

      final payment = AdminUserPayment.fromMap(mapWithForbiddenFields);
      final jsonOutput = payment.toJson();

      expect(jsonOutput.containsKey('secretKey'), isFalse);
      expect(jsonOutput.containsKey('cvv'), isFalse);
      expect(jsonOutput.containsKey('cardNumber'), isFalse);
    });
  });

  group('5. AdminUserMaterialSummary & Items Tests', () {
    test('parses material summary counters', () {
      final map = {
        'totalUploads': 10,
        'approvedCount': 6,
        'pendingCount': 2,
        'rejectedCount': 1,
        'modifiedCount': 1,
        'archivedCount': 0,
        'totalViews': 350,
        'totalLikes': 45,
        'totalComments': 15,
      };

      final summary = AdminUserMaterialSummary.fromMap(map);

      expect(summary.totalCount, equals(10));
      expect(summary.totalUploads, equals(10));
      expect(summary.approvedCount, equals(6));
      expect(summary.pendingCount, equals(2));
      expect(summary.rejectedCount, equals(1));
      expect(summary.modifiedCount, equals(1));
      expect(summary.totalViews, equals(350));
      expect(summary.totalLikes, equals(45));
      expect(summary.totalComments, equals(15));
    });

    test('parses material item details', () {
      final map = {
        'id': 'res_001',
        'title': 'Operating Systems Notes',
        'fileName': 'os_notes.pdf',
        'type': 'notes',
        'unitName': 'Operating Systems',
        'unitCode': 'COMP 210',
        'materialFormat': 'PDF',
        'uploadDate': '2026-01-05T00:00:00.000Z',
        'status': 'approved',
        'approvedAt': '2026-01-06T00:00:00.000Z',
        'views': 120,
        'likes': 15,
        'comments': 4,
      };

      final item = AdminUserMaterialItem.fromMap(map);

      expect(item.id, equals('res_001'));
      expect(item.title, equals('Operating Systems Notes'));
      expect(item.category, equals('notes'));
      expect(item.unitCode, equals('COMP 210'));
      expect(item.unitName, equals('Operating Systems'));
      expect(item.status, equals('approved'));
      expect(item.views, equals(120));
      expect(item.likes, equals(15));
      expect(item.comments, equals(4));
    });
  });

  group('6. AdminUserSession Model Tests', () {
    test('parses multi-device session attributes', () {
      final map = {
        'deviceId': 'pixel_7_pro',
        'platform': 'Android 14',
        'isActive': true,
        'lastLogin': '2026-01-08T00:00:00.000Z',
      };

      final session = AdminUserSession.fromMap(map);

      expect(session.deviceId, equals('pixel_7_pro'));
      expect(session.platform, equals('Android 14'));
      expect(session.deviceModel, equals('Android 14'));
      expect(session.isActive, isTrue);
      expect(session.lastLoginAt, isNotNull);
    });
  });

  group('7. AdminUserFullProfile Aggregation Tests', () {
    test('aggregates profile, sessions, subscriptions, payments and materials', () {
      final fullMap = {
        'user': {
          'uid': 'usr_full_1',
          'username': 'Grace Hopper',
          'email': 'grace@computing.org',
          'isAdmin': true,
          'disabled': false,
        },
        'sessions': [
          {'deviceId': 'd1', 'platform': 'iOS', 'isActive': true}
        ],
        'subscriptions': [
          {'id': 's1', 'packageTitle': 'VIP', 'status': 'active'}
        ],
        'payments': [
          {'reference': 'p1', 'expectedAmountKes': 1000.0, 'status': 'success'}
        ],
        'materialsSummary': {
          'totalUploads': 1,
          'approvedCount': 1,
        },
        'materials': [
          {'id': 'm1', 'title': 'Compiler Design', 'status': 'approved'}
        ],
      };

      final full = AdminUserFullProfile.fromMap(fullMap);

      expect(full.userId, equals('usr_full_1'));
      expect(full.profile.displayName, equals('Grace Hopper'));
      expect(full.isDisabled, isFalse);
      expect(full.role, equals('admin'));
      expect(full.hasActiveSubscription, isTrue);
      expect(full.sessions.length, equals(1));
      expect(full.subscriptions.length, equals(1));
      expect(full.payments.length, equals(1));
      expect(full.materialsSummary.totalUploads, equals(1));
      expect(full.materials.length, equals(1));
    });
  });

  group('8. AdminUserDetailScreen Widget Tests', () {
    testWidgets('renders AppBar with user summary while loading details', (tester) async {
      final summary = AdminUserSummary(
        uid: 'test_uid_999',
        username: 'Grace Hopper',
        email: 'hopper@computing.org',
        institution: 'Naval Academy',
        program: 'Computer Science',
        programCode: 'CS',
        year: '4',
        semester: '2',
        phone: '123456789',
        isAdmin: true,
        hasActiveSubscription: true,
        disabled: false,
      );

      final completer = Completer<AdminUserFullProfile>();
      final fakeService = FakeAdminUsersService(completer: completer);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminUserDetailScreen(
            userId: 'test_uid_999',
            summary: summary,
            usersService: fakeService,
          ),
        ),
      );

      // Verify user's display name is visible in the title
      expect(find.text('Grace Hopper'), findsOneWidget);
      // Verify loading progress indicator appears while fetching full profile
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete future with mock profile
      completer.complete(AdminUserFullProfile(
        user: AdminUserDetail(
          uid: 'test_uid_999',
          username: 'Grace Hopper',
          email: 'hopper@computing.org',
          institution: 'Naval Academy',
          universityLocation: 'Main',
          program: 'Computer Science',
          programCode: 'CS',
          year: '4',
          semester: '2',
          phone: '123456789',
          authProvider: 'password',
          isAdmin: true,
        ),
        sessions: [],
        subscriptions: [],
        payments: [],
        materialsSummary: AdminUserMaterialSummary(
          totalUploads: 0,
          approvedCount: 0,
          pendingCount: 0,
          rejectedCount: 0,
          modifiedCount: 0,
          archivedCount: 0,
          totalViews: 0,
          totalLikes: 0,
          totalComments: 0,
        ),
        materials: [],
      ));

      await tester.pumpAndSettle();

      // Verify tabs are rendered
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Subscriptions (0)'), findsOneWidget);
      expect(find.text('Materials (0)'), findsOneWidget);
      expect(find.text('Sessions (0)'), findsOneWidget);

      // Verify action buttons are rendered
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Disable'), findsOneWidget);
    });

    testWidgets('renders empty history messages for users with zero activity', (tester) async {
      final fakeService = FakeAdminUsersService(
        profileToReturn: AdminUserFullProfile(
          user: AdminUserDetail(
            uid: 'fresh_student_1',
            username: 'Freshman Student',
            email: 'fresh@laikipia.ac.ke',
            institution: 'Laikipia University',
            universityLocation: 'Main',
            program: 'Education',
            programCode: 'BED',
            year: '1',
            semester: '1',
            phone: '0711000000',
            authProvider: 'google',
          ),
          sessions: [],
          subscriptions: [],
          payments: [],
          materialsSummary: AdminUserMaterialSummary(
            totalUploads: 0,
            approvedCount: 0,
            pendingCount: 0,
            rejectedCount: 0,
            modifiedCount: 0,
            archivedCount: 0,
            totalViews: 0,
            totalLikes: 0,
            totalComments: 0,
          ),
          materials: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AdminUserDetailScreen(
            userId: 'fresh_student_1',
            usersService: fakeService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Subscriptions Tab
      await tester.tap(find.text('Subscriptions (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No active subscription found. User is currently on the free tier.'), findsOneWidget);
      expect(find.text('No past subscription history.'), findsOneWidget);

      // Switch to Materials Tab
      await tester.tap(find.text('Materials (0)'));
      await tester.pumpAndSettle();
      expect(find.text('This user has not uploaded any materials yet.'), findsOneWidget);

      // Switch to Sessions Tab
      await tester.tap(find.text('Sessions (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No recorded device sessions.'), findsOneWidget);
    });
  });

  group('9. Admin Menu Navigation Tests', () {
    testWidgets('AdminMenuBottomSheet has Users item navigating to AdminUsersScreen', (tester) async {
      final capabilities = AdminCapabilities(
        authorized: true,
        role: 'super_admin',
        adminUid: 'admin_test_1',
        menu: [
          AdminMenuItem(
            id: 'users',
            title: 'Users',
            subtitle: 'View and inspect registered users',
            icon: 'person_outline',
            enabled: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminMenuBottomSheet(capabilities: capabilities),
          ),
        ),
      );

      expect(find.text('Users'), findsOneWidget);
      expect(find.text('View and inspect registered users'), findsOneWidget);
    });
  });

  group('10. AdminUsersScreen Widget Tests', () {
    testWidgets('renders search bar, filter chips, and user cards', (tester) async {
      final fakeService = FakeAdminUsersService(
        usersToReturn: [
          AdminUserSummary(
            uid: 'u_test_1',
            username: 'Esther Mutua',
            email: 'esther@laikipia.ac.ke',
            institution: 'Laikipia University',
            program: 'Education Arts',
            programCode: 'EDA',
            year: '3',
            semester: '1',
            phone: '0712345678',
            isAdmin: false,
            hasActiveSubscription: true,
            disabled: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AdminUsersScreen(usersService: fakeService),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & search
      expect(find.text('Users Management'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify filter chips
      expect(find.text('All Users'), findsOneWidget);
      expect(find.text('Active Subscribers'), findsOneWidget);
      expect(find.text('Admins'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);

      // Verify user card rendered
      expect(find.text('Esther Mutua'), findsOneWidget);
      expect(find.text('Subscribed'), findsOneWidget);
    });

    testWidgets('renders empty state when user list is empty', (tester) async {
      final fakeService = FakeAdminUsersService(usersToReturn: []);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminUsersScreen(usersService: fakeService),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No registered users found'), findsOneWidget);
    });
  });
}
