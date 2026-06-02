import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/comment.dart';

class CommentService extends ChangeNotifier {
  static final CommentService _instance = CommentService._internal();
  factory CommentService() => _instance;
  CommentService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Comment>> streamComments(String resourceId) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return _firestore
        .collection('resources')
        .doc(resourceId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          final allComments = snapshot.docs.map((doc) {
            return Comment.fromMap(doc.data(), doc.id, currentUserId: currentUserId);
          }).toList();

          // Construct nesting replies
          final topLevel = allComments.where((c) => c.parentId == null).toList();
          
          for (var parent in topLevel) {
            parent.replies = allComments.where((c) => c.parentId == parent.id).toList();
            // Sort replies chronological (ascending)
            parent.replies.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          }

          // Top level comments are sorted descending (latest first)
          topLevel.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return topLevel;
        });
  }

  Future<void> addComment(
    String resourceId,
    String text, {
    Comment? replyingTo,
    required String authorName,
    String? authorProfileImage,
    String? authorId,
  }) async {
    final commentDocRef = _firestore
        .collection('resources')
        .doc(resourceId)
        .collection('comments')
        .doc();

    final commentData = {
      'authorId': authorId,
      'author': authorName,
      'authorProfileImage': authorProfileImage,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': 0,
      'likedBy': [],
      'parentId': replyingTo?.id,
      'reactions': {},
    };

    final resourceDocRef = _firestore.collection('resources').doc(resourceId);

    try {
      await _firestore.runTransaction((transaction) async {
        transaction.set(commentDocRef, commentData);
        transaction.update(resourceDocRef, {
          'comments': FieldValue.increment(1),
        });
      });
    } catch (e) {
      debugPrint('CommentService: [ERROR] Failed to add comment: $e');
    }
  }

  Future<void> deleteComment(String resourceId, String commentId) async {
    final commentDocRef = _firestore
        .collection('resources')
        .doc(resourceId)
        .collection('comments')
        .doc(commentId);

    final resourceDocRef = _firestore.collection('resources').doc(resourceId);

    try {
      await _firestore.runTransaction((transaction) async {
        transaction.delete(commentDocRef);
        transaction.update(resourceDocRef, {
          'comments': FieldValue.increment(-1),
        });
      });
    } catch (e) {
      debugPrint('CommentService: [ERROR] Failed to delete comment: $e');
    }
  }

  Future<void> editComment(String resourceId, String commentId, String newText) async {
    try {
      await _firestore
          .collection('resources')
          .doc(resourceId)
          .collection('comments')
          .doc(commentId)
          .update({'text': newText});
    } catch (e) {
      debugPrint('CommentService: [ERROR] Failed to edit comment: $e');
    }
  }

  Future<void> updateReaction(String resourceId, String commentId, String emoji) async {
    final commentDocRef = _firestore
        .collection('resources')
        .doc(resourceId)
        .collection('comments')
        .doc(commentId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(commentDocRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() ?? {};
        final reactions = Map<String, int>.from(data['reactions'] ?? {});
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;

        transaction.update(commentDocRef, {'reactions': reactions});
      });
    } catch (e) {
      debugPrint('CommentService: [ERROR] Failed to update reaction: $e');
    }
  }

  Future<void> toggleCommentLike(String resourceId, Comment comment) async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final commentDocRef = _firestore
        .collection('resources')
        .doc(resourceId)
        .collection('comments')
        .doc(comment.id);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(commentDocRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() ?? {};
        final likedByList = List<String>.from(data['likedBy'] ?? []);
        int likesCount = data['likes'] ?? 0;

        if (likedByList.contains(userId)) {
          likedByList.remove(userId);
          likesCount = (likesCount - 1).clamp(0, 999999).toInt();
        } else {
          likedByList.add(userId);
          likesCount += 1;
        }

        transaction.update(commentDocRef, {
          'likedBy': likedByList,
          'likes': likesCount,
        });
      });
    } catch (e) {
      debugPrint('CommentService: [ERROR] Failed to toggle comment like: $e');
    }
  }
}
