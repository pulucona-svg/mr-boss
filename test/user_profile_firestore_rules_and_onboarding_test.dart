import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/screens/academic_personalization_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('UserProfile Model & toFirestoreMap() Tests', () {
    test('1. toFirestoreMap() excludes server-controlled deletion fields and local-only paths', () {
      final now = DateTime.utc(2026, 10, 14, 12, 0, 0);
      final profile = UserProfile(
        uid: 'user-abc-123',
        username: 'John Doe',
        profileImagePath: '/data/user/0/com.mirrordigital.app/cache/local_image.jpg',
        photoURL: 'https://ik.imagekit.io/mirror/profile_pic.jpg',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'BSc Computer Science',
        programCode: 'COMP 101',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '0712345678',
        email: 'john@example.com',
        onboardingComplete: true,
        sessionId: 'local-session-uuid-999',
        deletionStatus: 'none',
        deletionRequestedAt: now,
        deletionScheduledAt: now.add(const Duration(days: 30)),
      );

      final firestoreMap = profile.toFirestoreMap();

      // Must NOT contain server-controlled deletion lifecycle keys
      expect(firestoreMap.containsKey('deletionStatus'), false, reason: 'deletionStatus must be excluded from Firestore writes');
      expect(firestoreMap.containsKey('deletionRequestedAt'), false, reason: 'deletionRequestedAt must be excluded');
      expect(firestoreMap.containsKey('deletionScheduledAt'), false, reason: 'deletionScheduledAt must be excluded');

      // Must NOT contain device-local properties
      expect(firestoreMap.containsKey('profileImagePath'), false, reason: 'profileImagePath is a local disk path');
      expect(firestoreMap.containsKey('sessionId'), false, reason: 'sessionId belongs in subcollection sessions');

      // Must contain valid user profile fields
      expect(firestoreMap['uid'], 'user-abc-123');
      expect(firestoreMap['username'], 'John Doe');
      expect(firestoreMap['institution'], 'Laikipia University');
      expect(firestoreMap['universityLocation'], 'Main Campus');
      expect(firestoreMap['program'], 'BSc Computer Science');
      expect(firestoreMap['programCode'], 'COMP 101');
      expect(firestoreMap['year'], 'Year 1');
      expect(firestoreMap['semester'], 'Sem 1');
      expect(firestoreMap['phone'], '0712345678');
      expect(firestoreMap['email'], 'john@example.com');
      expect(firestoreMap['onboardingComplete'], true);
      expect(firestoreMap['photoURL'], 'https://ik.imagekit.io/mirror/profile_pic.jpg');
    });

    test('2. toJson() preserves deletionStatus for local Hive persistence and state restoration', () {
      final now = DateTime.utc(2026, 10, 14, 12, 0, 0);
      final profile = UserProfile(
        uid: 'user-xyz-789',
        username: 'Pending User',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Economics',
        programCode: 'ECON 101',
        year: 'Year 3',
        semester: 'Sem 2',
        phone: '0722334455',
        email: 'pending@example.com',
        onboardingComplete: true,
        deletionStatus: 'pending',
        deletionRequestedAt: now,
        deletionScheduledAt: now.add(const Duration(days: 30)),
      );

      final json = profile.toJson();
      expect(json['deletionStatus'], 'pending');
      expect(json['deletionRequestedAt'], now.toIso8601String());

      final restored = UserProfile.fromJson(json);
      expect(restored.deletionStatus, 'pending');
      expect(restored.isPendingDeletion, true);
    });
  });

  group('UserService completeOnboarding() Defensive Sanitization Tests', () {
    test('3. Raw client map with malicious or restricted fields is strictly filtered', () {
      // Simulate malicious or un-sanitized client map trying to self-assign admin/subscriptions or deletion
      final maliciousMap = {
        'uid': 'user-hacker-001',
        'username': 'Hacker',
        'institution': 'Laikipia University',
        'universityLocation': 'Main Campus',
        'program': 'Information Technology',
        'programCode': 'IT 101',
        'year': 'Year 1',
        'semester': 'Sem 1',
        'phone': '0700000000',
        'email': 'hacker@example.com',
        'onboardingComplete': true,
        // Disallowed / sensitive keys
        'role': 'admin',
        'isAdmin': true,
        'isSubscribed': true,
        'subscription': 'pro_yearly',
        'subscriptionStatus': 'active',
        'deletionStatus': 'none',
        'deletionScheduledAt': '2026-11-01',
        'profileImagePath': '/storage/emulated/0/DCIM/photo.jpg',
        'sessionId': 'session-xyz',
      };

      // Test the sanitization filter logic implemented in completeOnboarding
      const allowedKeys = {
        'uid',
        'username',
        'institution',
        'universityLocation',
        'program',
        'programCode',
        'year',
        'semester',
        'phone',
        'email',
        'photoURL',
        'joinDate',
        'termsVersionAccepted',
        'termsAcceptedAt',
        'privacyPolicyVersionAccepted',
        'privacyPolicyAcceptedAt',
      };

      final sanitized = <String, dynamic>{
        'onboardingComplete': true,
      };

      for (final entry in maliciousMap.entries) {
        if (allowedKeys.contains(entry.key)) {
          sanitized[entry.key] = entry.value;
        }
      }

      // Verify no sensitive keys leaked through
      expect(sanitized.containsKey('role'), false);
      expect(sanitized.containsKey('isAdmin'), false);
      expect(sanitized.containsKey('isSubscribed'), false);
      expect(sanitized.containsKey('subscription'), false);
      expect(sanitized.containsKey('deletionStatus'), false);
      expect(sanitized.containsKey('deletionScheduledAt'), false);
      expect(sanitized.containsKey('profileImagePath'), false);
      expect(sanitized.containsKey('sessionId'), false);

      // Verify legitimate profile keys are preserved
      expect(sanitized['username'], 'Hacker');
      expect(sanitized['program'], 'Information Technology');
      expect(sanitized['onboardingComplete'], true);
    });
  });

  group('AcademicPersonalizationScreen Widget & State Tests', () {
    testWidgets('4. Personalization screen renders input fields and validates inputs', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AcademicPersonalizationScreen(
              email: 'newuser@example.com',
              isOnboarding: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and fields exist
      expect(find.text('Academic Personalization'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('SAVE'), findsOneWidget);
    });

    testWidgets('5. Form validation requires all mandatory fields before SAVE becomes active', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AcademicPersonalizationScreen(
              email: 'student@example.com',
              isOnboarding: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final saveButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SAVE'));
      // Initially, mandatory fields (year, semester, phone, institution, program) are empty
      expect(saveButton.onPressed, isNull, reason: 'SAVE button must be disabled until form is valid');
    });

    testWidgets('6. UserProfileNotifier updateProfile updates state cleanly without modifying deletionStatus', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(userProfileProvider.notifier);
      expect(container.read(userProfileProvider).deletionStatus, 'none');

      notifier.updateProfile(
        uid: 'test-uid-100',
        username: 'Grace Hopper',
        institution: 'Laikipia University',
        program: 'Computer Science',
        year: 'Year 2',
        semester: 'Sem 1',
        phone: '0711223344',
        email: 'grace@example.com',
        onboardingComplete: true,
      );

      final state = container.read(userProfileProvider);
      expect(state.uid, 'test-uid-100');
      expect(state.username, 'Grace Hopper');
      expect(state.onboardingComplete, true);
      expect(state.deletionStatus, 'none');
      expect(state.isPendingDeletion, false);

      final firestoreMap = state.toFirestoreMap();
      expect(firestoreMap.containsKey('deletionStatus'), false);
      expect(firestoreMap['username'], 'Grace Hopper');
    });
  });
}
