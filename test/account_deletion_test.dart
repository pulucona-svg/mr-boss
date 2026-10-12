import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/admin_service.dart';
import 'package:mirror_laikipia/services/author_profile_cache.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/screens/profile_screen.dart';
import 'package:mirror_laikipia/screens/account_deletion_screen.dart';
import 'package:mirror_laikipia/screens/account_restore_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    AuthorProfileCache.resetInstance();
  });

  group('UserProfile Deletion Model & State Tests', () {
    test('1. Default UserProfile has deletionStatus none and isPendingDeletion false', () {
      final profile = UserProfile(
        uid: 'user-001',
        username: 'Test User',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Computer Science',
        programCode: 'CS101',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '0712345678',
        email: 'test@example.com',
      );

      expect(profile.deletionStatus, 'none');
      expect(profile.isPendingDeletion, false);
      expect(profile.deletionRequestedAt, isNull);
      expect(profile.deletionScheduledAt, isNull);
    });

    test('2. UserProfile with deletionStatus pending sets isPendingDeletion true', () {
      final now = DateTime.now();
      final deadline = now.add(const Duration(days: 30));

      final profile = UserProfile(
        uid: 'user-002',
        username: 'Pending User',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Computer Science',
        programCode: 'CS101',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '0712345678',
        email: 'pending@example.com',
        deletionStatus: 'pending',
        deletionRequestedAt: now,
        deletionScheduledAt: deadline,
      );

      expect(profile.deletionStatus, 'pending');
      expect(profile.isPendingDeletion, true);
      expect(profile.deletionRequestedAt, now);
      expect(profile.deletionScheduledAt, deadline);
    });

    test('3. UserProfile serialization round-trip preserves deletion fields', () {
      final now = DateTime.utc(2026, 10, 8, 12, 0, 0);
      final deadline = DateTime.utc(2026, 11, 7, 12, 0, 0);

      final profile = UserProfile(
        uid: 'user-003',
        username: 'Serialized User',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Economics',
        programCode: 'EC101',
        year: 'Year 2',
        semester: 'Sem 1',
        phone: '0711223344',
        email: 'serialized@example.com',
        deletionStatus: 'pending',
        deletionRequestedAt: now,
        deletionScheduledAt: deadline,
      );

      final json = profile.toJson();
      expect(json['deletionStatus'], 'pending');
      expect(json['deletionRequestedAt'], now.toIso8601String());
      expect(json['deletionScheduledAt'], deadline.toIso8601String());

      final restored = UserProfile.fromJson(json);
      expect(restored.deletionStatus, 'pending');
      expect(restored.isPendingDeletion, true);
      expect(restored.isPermanentlyDeleted, false);
      expect(restored.deletionRequestedAt, now);
      expect(restored.deletionScheduledAt, deadline);
    });

    test('4. UserProfile with deletionStatus permanently_deleted sets isPermanentlyDeleted true', () {
      final profile = UserProfile(
        uid: 'user-004',
        username: 'Deleted User',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Computer Science',
        programCode: 'CS101',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '0712345678',
        email: 'deleted@example.com',
        deletionStatus: 'permanently_deleted',
      );

      expect(profile.deletionStatus, 'permanently_deleted');
      expect(profile.isPendingDeletion, false);
      expect(profile.isPermanentlyDeleted, true);
    });

    test('5. copyWith with clearDeletion resets status to none and dates to null', () {
      final now = DateTime.now();
      final profile = UserProfile(
        uid: 'user-004',
        username: 'Test',
        institution: 'LU',
        universityLocation: 'Main',
        program: 'CS',
        programCode: 'CS',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '',
        email: '',
        deletionStatus: 'pending',
        deletionRequestedAt: now,
        deletionScheduledAt: now.add(const Duration(days: 30)),
      );

      final restored = profile.copyWith(clearDeletion: true);
      expect(restored.deletionStatus, 'none');
      expect(restored.isPendingDeletion, false);
      expect(restored.deletionRequestedAt, isNull);
      expect(restored.deletionScheduledAt, isNull);
    });
  });

  group('AuthorProfileCache Anonymization Tests', () {
    test('5. Recognizes anonymous and deleted identifiers as anonymized', () {
      final cache = AuthorProfileCache();
      expect(cache.isAnonymized('anonymous'), true);
      expect(cache.isAnonymized('deleted'), true);
      expect(cache.isAnonymized(''), true);
      expect(cache.isAnonymized('regular-user-id'), false);
    });

    test('6. Resolves anonymous identifiers to "Anonymous User" and null photo', () {
      final cache = AuthorProfileCache();
      expect(cache.getName('anonymous'), AuthorProfileCache.anonymousName);
      expect(cache.getPhoto('anonymous'), isNull);
      expect(cache.getName('deleted'), AuthorProfileCache.anonymousName);
      expect(cache.getPhoto('deleted'), isNull);
    });

    test('7. Cached anonymized profile resolves correctly to Anonymous User', () {
      final cache = AuthorProfileCache();
      cache.setCachedProfileForTesting('user-anonymized-001', isAnon: true);

      expect(cache.isAnonymized('user-anonymized-001'), true);
      expect(cache.getName('user-anonymized-001'), AuthorProfileCache.anonymousName);
      expect(cache.getPhoto('user-anonymized-001'), isNull);
    });
  });

  group('ProfileScreen Trophy vs Three-Dot Menu Tests', () {
    testWidgets('8. Normal user sees three-dot menu icon, not trophy', (tester) async {
      AdminService().setIsAdminForTesting(false);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Normal user: Three-dot menu should exist, Trophy should NOT exist
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
      expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
    });

    testWidgets('9. Admin user sees golden trophy, not three-dot menu', (tester) async {
      AdminService().setIsAdminForTesting(true);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Admin user: Golden trophy should exist, Three-dot should NOT exist
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('10. Tapping normal user three-dot menu displays Delete Account option', (tester) async {
      AdminService().setIsAdminForTesting(false);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Tap the three-dot icon
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Verify the popup menu item appears
      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget);
    });
  });

  group('AccountDeletionScreen UI & Questionnaire Tests', () {
    testWidgets('11. AccountDeletionScreen renders title, 30-day explanation, and action buttons', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AccountDeletionScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Title
      expect(find.text('Delete account'), findsOneWidget);
      // Explanation
      expect(find.text('How Account Deletion Works'), findsOneWidget);
      expect(find.textContaining('30-day grace period'), findsWidgets);
      // Feedback section
      expect(find.text('Feedback (Optional)'), findsOneWidget);
      // Bottom buttons: Cancel (Blue) and Delete Account (Red)
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('12. Cancel button exits without deleting', (tester) async {
      bool didPop = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountDeletionScreen()),
                  );
                  didPop = true;
                },
                child: const Text('Open Deletion Screen'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Deletion Screen'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // We should be back on the original screen
      expect(didPop, true);
      expect(find.text('Open Deletion Screen'), findsOneWidget);
    });
  });

  group('AccountRestoreScreen UI & Countdown Tests', () {
    testWidgets('13. AccountRestoreScreen renders status, countdown, and action buttons', (tester) async {
      final now = DateTime.now();
      final deadline = now.add(const Duration(days: 30));

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) {
            final notifier = UserProfileNotifier();
            notifier.updateProfile(
              uid: 'user-pending-test',
              username: 'Pending User',
            );
            notifier.setDeletionStatus(
              status: 'pending',
              requestedAt: now,
              scheduledAt: deadline,
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AccountRestoreScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header
      expect(find.text('Account Scheduled for Deletion'), findsOneWidget);
      // Countdown card
      expect(find.text('Time Remaining in Grace Period'), findsOneWidget);
      // Bottom buttons: Restore Account (Green) and Cancel (Blue)
      expect(find.text('Restore Account'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('14. AccountRestoreScreen does not overflow on standard compact phone (360px width)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final requested = DateTime(2026, 9, 28, 23, 45);
      final deadline = DateTime(2026, 11, 28, 23, 45);

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) {
            final notifier = UserProfileNotifier();
            notifier.updateProfile(
              uid: 'user-pending-narrow',
              username: 'Narrow Screen User',
            );
            notifier.setDeletionStatus(
              status: 'pending',
              requestedAt: requested,
              scheduledAt: deadline,
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AccountRestoreScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check detail row texts rendered without layout exceptions
      expect(find.text('Deletion Requested:'), findsOneWidget);
      expect(find.text('Permanent Deletion:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
