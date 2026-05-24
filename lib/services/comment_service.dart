import 'package:flutter/material.dart';
import '../models/comment.dart';
import 'resource_service.dart';

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

  void addComment(String resourceTitle, String text, {Comment? replyingTo, required String authorName, String? authorProfileImage, String? authorId}) {
    final comments = getComments(resourceTitle);
    final newComment = Comment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      authorId: authorId,
      author: authorName,
      authorProfileImage: authorProfileImage,
      text: text,
      timestamp: DateTime.now(),
    );

    if (replyingTo != null) {
      replyingTo.replies.add(newComment);
    } else {
      comments.insert(0, newComment);
    }
    
    // Increment count and handle notifications via ResourceService
    ResourceService().incrementComments(resourceTitle);
    notifyListeners();
  }

  void deleteComment(String resourceTitle, String commentId) {
    final comments = getComments(resourceTitle);
    bool removed = _removeFromList(comments, commentId);
    if (removed) {
      notifyListeners();
    }
  }

  bool _removeFromList(List<Comment> list, String id) {
    for (int i = 0; i < list.length; i++) {
      if (list[i].id == id) {
        list.removeAt(i);
        return true;
      }
      if (_removeFromList(list[i].replies, id)) return true;
    }
    return false;
  }

  void editComment(String resourceTitle, String commentId, String newText) {
    final comment = _findInList(getComments(resourceTitle), commentId);
    if (comment != null) {
      comment.text = newText;
      notifyListeners();
    }
  }

  Comment? _findInList(List<Comment> list, String id) {
    for (var c in list) {
      if (c.id == id) return c;
      final found = _findInList(c.replies, id);
      if (found != null) return found;
    }
    return null;
  }

  void updateReaction(String resourceTitle, String commentId, String emoji) {
    final comment = _findInList(getComments(resourceTitle), commentId);
    if (comment != null) {
      comment.reactions[emoji] = (comment.reactions[emoji] ?? 0) + 1;
      notifyListeners();
    }
  }

  void toggleCommentLike(String resourceTitle, Comment comment) {
    comment.isLiked = !comment.isLiked;
    if (comment.isLiked) {
      comment.likes++;
      // We could add notification for comment likes too if needed
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
