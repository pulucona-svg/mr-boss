import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mirror_laikipia/screens/login_screen.dart';
import 'package:mirror_laikipia/screens/signup_screen.dart';
import 'package:mirror_laikipia/models/message.dart';
import 'package:mirror_laikipia/services/chat_service.dart';
import 'package:mirror_laikipia/providers/chat_provider.dart';
import 'package:mirror_laikipia/services/subscription_service.dart';
import 'package:mirror_laikipia/screens/admin/admin_messages_screen.dart';

class MockChatService extends ChatService {
  @override
  Stream<List<ConversationSummary>> streamAllConversations() {
    return Stream.value([
      ConversationSummary(
        userId: 'student-1',
        userName: 'John Student',
        userEmail: 'student@example.com',
        lastMessageText: 'Hello Admin',
        lastMessageTimestamp: DateTime.now(),
        adminUnreadCount: 1,
        isUserTyping: false,
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Social Buttons Polish Tests', () {
    testWidgets('LoginScreen: Google and Apple buttons have cyan glassmorphism style', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Verify Google button exists with cyan glass background
      final googleFinder = find.widgetWithText(OutlinedButton, 'Continue with Google');
      expect(googleFinder, findsOneWidget);
      final googleBtn = tester.widget<OutlinedButton>(googleFinder);
      final googleBgColor = googleBtn.style?.backgroundColor?.resolve({});
      expect(googleBgColor, const Color(0xFF20C8FF).withValues(alpha: 0.08));

      // Verify Apple button exists with cyan glass background and white icon
      final appleFinder = find.widgetWithText(OutlinedButton, 'Continue with Apple');
      expect(appleFinder, findsOneWidget);
      final appleBtn = tester.widget<OutlinedButton>(appleFinder);
      final appleBgColor = appleBtn.style?.backgroundColor?.resolve({});
      expect(appleBgColor, const Color(0xFF20C8FF).withValues(alpha: 0.08));

      // Verify Apple FaIcon is white
      final faIcons = tester.widgetList<FaIcon>(find.byType(FaIcon));
      final appleFaIcon = faIcons.firstWhere((i) => i.icon?.codePoint == FontAwesomeIcons.apple.codePoint);
      expect(appleFaIcon.color, Colors.white);

      // Verify Primary Login button is still intact
      final loginBtnFinder = find.widgetWithText(ElevatedButton, 'Login');
      expect(loginBtnFinder, findsOneWidget);
    });

    testWidgets('SignupScreen: Google, Apple, and Email buttons have cyan glassmorphism style & white icons', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SignupScreen(),
          ),
        ),
      );

      // Google Button
      final googleFinder = find.widgetWithText(OutlinedButton, 'Continue with Google');
      expect(googleFinder, findsOneWidget);
      final googleBtn = tester.widget<OutlinedButton>(googleFinder);
      final googleBg = googleBtn.style?.backgroundColor?.resolve({});
      expect(googleBg, const Color(0xFF20C8FF).withValues(alpha: 0.08));

      // Apple Button with white FaIcon
      final appleFinder = find.widgetWithText(OutlinedButton, 'Continue with Apple');
      expect(appleFinder, findsOneWidget);
      final faIcons = tester.widgetList<FaIcon>(find.byType(FaIcon));
      final appleFaIcon = faIcons.firstWhere((i) => i.icon?.codePoint == FontAwesomeIcons.apple.codePoint);
      expect(appleFaIcon.color, Colors.white);

      // Email Button with white mail icon
      final emailFinder = find.widgetWithText(OutlinedButton, 'Continue with Email');
      expect(emailFinder, findsOneWidget);
      final mailIconFinder = find.descendant(
        of: emailFinder,
        matching: find.byIcon(Icons.mail_outline_rounded),
      );
      expect(mailIconFinder, findsOneWidget);
      final mailIcon = tester.widget<Icon>(mailIconFinder);
      expect(mailIcon.color, Colors.white);
    });
  });

  group('Profile Subscription Status Tests', () {
    testWidgets('Subscription status badge updates reactively between Active (green) and Inactive (red)', (tester) async {
      final subscriptionService = SubscriptionService();
      subscriptionService.isSubscribedForTesting = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: subscriptionService,
              builder: (context, child) {
                final isSubscribed = subscriptionService.isSubscribed;
                final status = isSubscribed ? 'Active' : 'Inactive';
                final isActive = status.toUpperCase() == 'ACTIVE';
                return Container(
                  key: const ValueKey('status_badge'),
                  decoration: BoxDecoration(
                    color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.2),
                    border: Border.all(color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isActive ? Colors.greenAccent : Colors.red,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // 1. Initial Inactive state
      expect(find.text('Inactive'), findsOneWidget);
      final inactiveContainer = tester.widget<Container>(find.byKey(const ValueKey('status_badge')));
      final inactiveDeco = inactiveContainer.decoration as BoxDecoration;
      expect(inactiveDeco.color, Colors.red.withValues(alpha: 0.2));

      // 2. Switch to Active via authoritative SubscriptionService
      subscriptionService.isSubscribedForTesting = true;
      await tester.pump();

      // 3. Active state rendered with green styling
      expect(find.text('Active'), findsOneWidget);
      final activeContainer = tester.widget<Container>(find.byKey(const ValueKey('status_badge')));
      final activeDeco = activeContainer.decoration as BoxDecoration;
      expect(activeDeco.color, Colors.green.withValues(alpha: 0.2));

      // Reset test state
      subscriptionService.isSubscribedForTesting = false;
    });
  });

  group('Message Model & ChatService Tests', () {
    test('Message JSON and Firestore model conversion preserve all properties', () {
      final now = DateTime(2026, 9, 29, 12, 0);
      final msg = Message(
        id: 'msg-123',
        senderId: 'user-456',
        senderRole: 'user',
        text: 'Hello Admin',
        timestamp: now,
        isMe: true,
        type: MessageType.text,
        status: MessageStatus.sent,
        replyToId: 'reply-0',
        replyText: 'Previous message',
        reaction: '👍',
        isDeleted: false,
        deletedFor: ['deleted-user-1'],
      );

      final json = msg.toJson();
      expect(json['id'], 'msg-123');
      expect(json['senderId'], 'user-456');
      expect(json['senderRole'], 'user');
      expect(json['text'], 'Hello Admin');
      expect(json['reaction'], '👍');
      expect(json['deletedFor'], ['deleted-user-1']);

      final restored = Message.fromJson(json);
      expect(restored.id, 'msg-123');
      expect(restored.senderRole, 'user');
      expect(restored.text, 'Hello Admin');
      expect(restored.reaction, '👍');
      expect(restored.deletedFor, ['deleted-user-1']);

      final firestoreMap = msg.toFirestore();
      expect(firestoreMap['senderRole'], 'user');
      expect(firestoreMap['status'], 'sent');
    });

    test('ConversationSummary model extracts metadata correctly', () {
      final summary = ConversationSummary(
        userId: 'user-789',
        userName: 'John Doe',
        userEmail: 'john@example.com',
        userPhotoUrl: 'https://example.com/photo.jpg',
        lastMessageText: 'Can you help me?',
        lastMessageTimestamp: DateTime(2026, 9, 29, 14, 30),
        adminUnreadCount: 2,
        userUnreadCount: 0,
        isUserTyping: true,
        isAdminTyping: false,
      );

      expect(summary.userId, 'user-789');
      expect(summary.userName, 'John Doe');
      expect(summary.adminUnreadCount, 2);
      expect(summary.isUserTyping, true);
    });
  });

  group('Admin Messages Screen Tests', () {
    testWidgets('AdminMessagesScreen renders search bar and UI scaffold properly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWith((ref) => MockChatService()),
          ],
          child: const MaterialApp(
            home: AdminMessagesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify app bar and search bar
      expect(find.text('User Inquiries & Messages'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search by username or email...'), findsOneWidget);

      // Verify conversation item from stream is rendered
      expect(find.text('John Student'), findsOneWidget);
      expect(find.text('Hello Admin'), findsOneWidget);

      // Enter search text and verify filtering
      await tester.enterText(find.byType(TextField), 'student');
      await tester.pumpAndSettle();
      expect(find.text('John Student'), findsOneWidget);
    });
  });
}
