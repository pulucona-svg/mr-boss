import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String? authorId;
  final String author;
  final String? authorProfileImage;
  String text;
  final DateTime timestamp;
  int likes;
  bool isLiked;
  final List<String> likedBy;
  final String? parentId;
  Map<String, int> reactions;
  List<Comment> replies;

  Comment({
    required this.id,
    this.authorId,
    required this.author,
    this.authorProfileImage,
    required this.text,
    required this.timestamp,
    this.likes = 0,
    this.isLiked = false,
    this.likedBy = const [],
    this.parentId,
    Map<String, int>? reactions,
    List<Comment>? replies,
  }) : replies = replies ?? [],
       reactions = reactions ?? {};

  factory Comment.fromMap(Map<String, dynamic> map, String docId, {String? currentUserId}) {
    final likedByList = List<String>.from(map['likedBy'] ?? []);
    return Comment(
      id: docId,
      authorId: map['authorId'],
      author: map['author'] ?? '',
      authorProfileImage: map['authorProfileImage'],
      text: map['text'] ?? '',
      timestamp: map['timestamp'] != null ? (map['timestamp'] as Timestamp).toDate() : DateTime.now(),
      likes: map['likes'] ?? 0,
      isLiked: currentUserId != null ? likedByList.contains(currentUserId) : false,
      likedBy: likedByList,
      parentId: map['parentId'],
      reactions: Map<String, int>.from(map['reactions'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'author': author,
      'authorProfileImage': authorProfileImage,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
      'likes': likes,
      'likedBy': likedBy,
      'parentId': parentId,
      'reactions': reactions,
    };
  }
}
