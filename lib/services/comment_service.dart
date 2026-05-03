import 'package:flutter/material.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import 'notification_service.dart';

class CommentService extends ChangeNotifier {
  static final CommentService _instance = CommentService._internal();
  factory CommentService() => _instance;
  CommentService._internal();

  final Map<String, List<Comment>> _resourceComments = {};

  List<Comment> getComments(String resourceTitle) {
    return _resourceComments.putIfAbsent(resourceTitle, () => _getInitialDummyData());
  }

  int getCommentCount(String resourceTitle) {
    final comments = getComments(resourceTitle);
    return _calculateTotal(comments);
  }

  int _calculateTotal(List<Comment> comments) {
    int total = comments.length;
    for (var comment in comments) {
      total += _calculateTotal(comment.replies);
    }
    return total;
  }

  void addComment(String resourceTitle, String text, {Comment? replyingTo}) {
    final comments = getComments(resourceTitle);
    final newComment = Comment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: 'Me',
      text: text,
      timestamp: DateTime.now(),
    );

    if (replyingTo != null) {
      replyingTo.replies.add(newComment);
      NotificationService().addNotification(
        type: NotificationType.reply,
        senderName: 'Me',
        resourceTitle: resourceTitle,
      );
    } else {
      comments.insert(0, newComment);
    }
    notifyListeners();
  }

  void toggleCommentLike(String resourceTitle, Comment comment) {
    comment.isLiked = !comment.isLiked;
    if (comment.isLiked) {
      comment.likes++;
      NotificationService().addNotification(
        type: NotificationType.like,
        senderName: 'Me',
        resourceTitle: resourceTitle,
      );
    } else {
      comment.likes--;
    }
    notifyListeners();
  }

  List<Comment> _getInitialDummyData() {
    return [
      Comment(
        id: '1',
        author: 'John Doe',
        text: 'This was very helpful! Thanks for sharing.',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        likes: 12,
      ),
      Comment(
        id: '2',
        author: 'Jane Smith',
        text: 'Are there more notes for this unit?',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        likes: 5,
        replies: [
          Comment(
            id: '3',
            author: 'Admin',
            text: 'Yes, check the library section.',
            timestamp: DateTime.now().subtract(const Duration(hours: 4)),
            likes: 2,
          ),
        ],
      ),
    ];
  }
}
