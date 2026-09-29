import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirror_laikipia/models/comment.dart';
import 'package:mirror_laikipia/models/message.dart';
import 'package:mirror_laikipia/services/comment_service.dart';
import 'package:mirror_laikipia/services/chat_service.dart';
import 'package:mirror_laikipia/services/author_profile_cache.dart';
import 'package:mirror_laikipia/widgets/comment_modal.dart';
import 'package:mirror_laikipia/screens/admin/admin_chat_detail_screen.dart';
import 'package:mirror_laikipia/providers/providers.dart';

class MockCommentService extends CommentService {
  final List<Comment> _mockComments;
  MockCommentService(this._mockComments) : super.forTesting();

  @override
  Stream<List<Comment>> streamComments(String resourceId) {
    return Stream.value(_mockComments);
  }
}

class MockChatServiceForAdmin extends ChatService {
  final List<Message> _mockMessages;
  MockChatServiceForAdmin(this._mockMessages);

  @override
  List<Message> get messages => _mockMessages;

  @override
  Stream<List<Message>> streamConversationMessages(String userId, {String? adminId}) {
    return Stream.value(_mockMessages);
  }

  @override
  Future<void> markAdminRead(String userId) async {}

  @override
  void setAdminTyping({required String userId, required bool isTyping}) {}
}

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier(UserProfile initial) {
    state = initial;
  }
}

UserProfile _createTestProfile({
  required String uid,
  required String username,
  required String email,
}) {
  return UserProfile(
    uid: uid,
    username: username,
    email: email,
    institution: 'Laikipia University',
    universityLocation: 'Main Campus',
    program: 'Computer Science',
    programCode: 'COMP',
    year: 'Year 2',
    semester: 'Semester 1',
    phone: '0712345678',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CommentService.resetInstance();
    AuthorProfileCache.resetInstance();
  });

  tearDown(() {
    CommentService.resetInstance();
    AuthorProfileCache.resetInstance();
  });

  group('Comment Model & Moderation Serialization Tests', () {
    test('Comment model correctly handles isModerated and placeholder text', () {
      final now = DateTime(2026, 9, 29, 10, 0);
      final rawMap = {
        'authorId': 'user_123',
        'author': 'Jane Doe',
        'authorProfileImage': 'https://example.com/avatar.jpg',
        'text': 'Offensive message that violates policy',
        'timestamp': now,
        'likes': 5,
        'likedBy': ['user_123', 'user_456'],
        'reactions': {'👍': 2},
        'isModerated': true,
        'moderationReason': 'Harassment / Inappropriate Language',
        'moderatedAt': now,
        'moderatedBy': 'admin_001',
      };

      final comment = Comment.fromMap(rawMap, 'comment_abc', currentUserId: 'user_123');

      // Moderated comments must have placeholder text and sanitized likes/reactions
      expect(comment.id, 'comment_abc');
      expect(comment.isModerated, isTrue);
      expect(comment.text, 'This comment was reported to admin');
      expect(comment.moderationReason, 'Harassment / Inappropriate Language');
      expect(comment.moderatedBy, 'admin_001');
      expect(comment.likes, 0);
      expect(comment.likedBy, isEmpty);
      expect(comment.reactions, isEmpty);
      expect(comment.isLiked, isFalse);

      // Verify toMap() preserves moderation fields
      final outputMap = comment.toMap();
      expect(outputMap['isModerated'], isTrue);
      expect(outputMap['text'], 'This comment was reported to admin');
      expect(outputMap['moderationReason'], 'Harassment / Inappropriate Language');
      expect(outputMap['moderatedBy'], 'admin_001');
    });

    test('Unmoderated comment retains normal text and active reactions', () {
      final now = DateTime(2026, 9, 29, 10, 0);
      final rawMap = {
        'authorId': 'user_123',
        'author': 'Jane Doe',
        'text': 'Great lecture notes, thanks!',
        'timestamp': now,
        'likes': 3,
        'likedBy': ['user_123'],
        'reactions': {'❤️': 2},
        'isModerated': false,
      };

      final comment = Comment.fromMap(rawMap, 'comment_xyz', currentUserId: 'user_123');
      expect(comment.isModerated, isFalse);
      expect(comment.text, 'Great lecture notes, thanks!');
      expect(comment.likes, 3);
      expect(comment.isLiked, isTrue);
      expect(comment.reactions, {'❤️': 2});
    });
  });

  group('AuthorProfileCache Tests', () {
    test('AuthorProfileCache falls back gracefully when user is not cached', () {
      final cache = AuthorProfileCache();
      expect(cache.getPhoto('unknown_uid', fallback: 'default.png'), 'default.png');
      expect(cache.getName('unknown_uid', fallback: 'Anonymous'), 'Anonymous');
    });

    test('AuthorProfileCache returns pre-populated profile information', () {
      final cache = AuthorProfileCache();
      cache.setCachedProfileForTesting(
        'student_42',
        photoURL: 'https://cdn.example.com/student42.jpg',
        username: 'Alex Kiprono',
      );

      expect(cache.getPhoto('student_42', fallback: 'default.png'), 'https://cdn.example.com/student42.jpg');
      expect(cache.getName('student_42', fallback: 'Anonymous'), 'Alex Kiprono');
    });
  });

  group('Message Metadata & Comment Reporting Tests', () {
    test('Message model serializes and deserializes comment report metadata correctly', () {
      final metadata = {
        'reportType': 'comment_report',
        'materialId': 'mat_comp_101',
        'materialTitle': 'Data Structures Lecture 1',
        'commentId': 'comm_999',
        'commentAuthorId': 'bad_actor_1',
        'commentAuthor': 'Troll User',
        'commentText': 'Disruptive content',
        'reason': 'Spam or Advertising',
        'reportedBy': 'student_7',
      };

      final msg = Message(
        id: 'msg_rep_1',
        senderId: 'student_7',
        senderRole: 'user',
        text: '🚩 [COMMENT REPORT]\nMaterial: Data Structures Lecture 1\nReason: Spam',
        timestamp: DateTime(2026, 9, 29, 11, 0),
        isMe: true,
        metadata: metadata,
      );

      final json = msg.toJson();
      expect(json['metadata'], isNotNull);
      expect(json['metadata']['reportType'], 'comment_report');
      expect(json['metadata']['materialId'], 'mat_comp_101');
      expect(json['metadata']['commentId'], 'comm_999');
      expect(json['metadata']['reason'], 'Spam or Advertising');

      final restored = Message.fromJson(json);
      expect(restored.metadata, isNotNull);
      expect(restored.metadata!['reportType'], 'comment_report');
      expect(restored.metadata!['commentAuthor'], 'Troll User');

      final firestoreMap = msg.toFirestore();
      expect(firestoreMap['metadata']['reportType'], 'comment_report');
      expect(firestoreMap['metadata']['materialTitle'], 'Data Structures Lecture 1');
    });
  });

  group('CommentModal Widget & Moderation UI Tests', () {
    testWidgets('CommentModal displays moderated comment card with placeholder and shield icon', (tester) async {
      final moderatedComment = Comment(
        id: 'c_mod_1',
        authorId: 'user_troll',
        author: 'Offensive Author',
        text: 'This comment was reported to admin',
        timestamp: DateTime(2026, 9, 29, 9, 0),
        isModerated: true,
        moderationReason: 'Hate speech',
      );

      final normalComment = Comment(
        id: 'c_norm_2',
        authorId: 'user_good',
        author: 'Alice Student',
        text: 'Helpful discussion here!',
        timestamp: DateTime(2026, 9, 29, 9, 30),
        isModerated: false,
      );

      CommentService.setMockInstance(MockCommentService([moderatedComment, normalComment]));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => MockUserProfileNotifier(
                _createTestProfile(
                  uid: 'user_good',
                  email: 'good@example.com',
                  username: 'Alice Student',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CommentModal(
                resourceId: 'res_test_1',
                resourceTitle: 'Computer Science 101',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Moderated placeholder must be displayed
      expect(find.text('This comment was reported to admin'), findsOneWidget);

      // Normal comment must be displayed
      expect(find.text('Helpful discussion here!'), findsOneWidget);

      // Moderated comment renders shield icon
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('CommentModal displays missing/removed target alert banner when targetCommentId is not found', (tester) async {
      final comments = [
        Comment(
          id: 'c_active_1',
          authorId: 'u1',
          author: 'Regular User',
          text: 'Existing valid comment',
          timestamp: DateTime(2026, 9, 29, 10, 0),
        ),
      ];

      CommentService.setMockInstance(MockCommentService(comments));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => MockUserProfileNotifier(
                _createTestProfile(
                  uid: 'admin_1',
                  email: 'admin@mirrorlaikipia.ac.ke',
                  username: 'System Admin',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CommentModal(
                resourceId: 'res_test_2',
                resourceTitle: 'Linear Algebra Notes',
                targetCommentId: 'deleted_comment_999',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Missing target banner alert must appear
      expect(find.text('The reported comment is no longer available or was removed.'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('CommentModal highlights targetCommentId with cyan border', (tester) async {
      final comments = [
        Comment(
          id: 'target_comm_123',
          authorId: 'u1',
          author: 'Reported Author',
          text: 'This is the specific reported comment',
          timestamp: DateTime(2026, 9, 29, 10, 0),
        ),
      ];

      CommentService.setMockInstance(MockCommentService(comments));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => MockUserProfileNotifier(
                _createTestProfile(
                  uid: 'admin_1',
                  email: 'admin@mirrorlaikipia.ac.ke',
                  username: 'System Admin',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CommentModal(
                resourceId: 'res_test_3',
                resourceTitle: 'Discrete Math Lecture',
                targetCommentId: 'target_comm_123',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The target comment card should be highlighted
      expect(find.text('This is the specific reported comment'), findsOneWidget);

      // Verify the highlighted AnimatedContainer has cyan border styling
      final animatedContainers = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final hasCyanBorder = animatedContainers.any((c) {
        final deco = c.decoration as BoxDecoration?;
        final border = deco?.border;
        return border is Border && border.top.color == const Color(0xFF20C8FF);
      });
      expect(hasCyanBorder, isTrue);
    });
  });

  group('AdminChatDetailScreen Deep-Linking & Action Card Tests', () {
    testWidgets('AdminChatDetailScreen displays "Inspect Reported Comment" action card for comment reports', (tester) async {
      final reportMessage = Message(
        id: 'msg_rep_card_1',
        senderId: 'student_12',
        senderRole: 'user',
        text: '🚩 [COMMENT REPORT]\nMaterial: Biology 101\nReason: Harassment',
        timestamp: DateTime(2026, 9, 29, 12, 0),
        isMe: false,
        metadata: {
          'reportType': 'comment_report',
          'materialId': 'bio_101',
          'materialTitle': 'Biology 101 Notes',
          'commentId': 'bio_comm_456',
          'commentAuthorId': 'bad_student',
          'commentAuthor': 'Bad Student',
          'commentText': 'Disrespectful comment',
          'reason': 'Harassment / Inappropriate Language',
          'reportedBy': 'student_12',
        },
      );

      final normalMessage = Message(
        id: 'msg_norm_1',
        senderId: 'student_12',
        senderRole: 'user',
        text: 'Can you help me with enrollment?',
        timestamp: DateTime(2026, 9, 29, 12, 5),
        isMe: false,
      );

      final mockChatService = MockChatServiceForAdmin([reportMessage, normalMessage]);

      final conversation = ConversationSummary(
        userId: 'student_12',
        userName: 'Student Twelve',
        lastMessageText: 'Can you help me with enrollment?',
        lastMessageTimestamp: DateTime(2026, 9, 29, 12, 5),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWith((ref) => mockChatService),
            userProfileProvider.overrideWith(
              (ref) => MockUserProfileNotifier(
                _createTestProfile(
                  uid: 'admin_1',
                  email: 'admin@mirrorlaikipia.ac.ke',
                  username: 'System Admin',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: AdminChatDetailScreen(
              conversation: conversation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify REPORTED COMMENT banner is visible
      expect(find.text('REPORTED COMMENT'), findsOneWidget);

      // Verify "Inspect Reported Comment" button is visible
      expect(find.text('Inspect Reported Comment'), findsOneWidget);

      // Normal message does NOT have a report card
      expect(find.text('Can you help me with enrollment?'), findsOneWidget);
    });
  });
}
