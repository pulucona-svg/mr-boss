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
  final bool isModerated;
  final String? moderationReason;
  final DateTime? moderatedAt;
  final String? moderatedBy;

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
    this.isModerated = false,
    this.moderationReason,
    this.moderatedAt,
    this.moderatedBy,
  }) : replies = replies ?? [],
       reactions = reactions ?? {};

  factory Comment.fromMap(Map<String, dynamic> map, String docId, {String? currentUserId}) {
    final likedByList = List<String>.from(map['likedBy'] ?? []);
    final isModerated = map['isModerated'] == true;
    final moderatedAtVal = map['moderatedAt'];
    DateTime? moderatedAt;
    if (moderatedAtVal is Timestamp) {
      moderatedAt = moderatedAtVal.toDate();
    } else if (moderatedAtVal is DateTime) {
      moderatedAt = moderatedAtVal;
    } else if (moderatedAtVal is String) {
      moderatedAt = DateTime.tryParse(moderatedAtVal);
    }

    final rawTs = map['timestamp'];
    DateTime parsedTimestamp;
    if (rawTs is Timestamp) {
      parsedTimestamp = rawTs.toDate();
    } else if (rawTs is DateTime) {
      parsedTimestamp = rawTs;
    } else if (rawTs is String) {
      parsedTimestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }

    return Comment(
      id: docId,
      authorId: map['authorId'],
      author: map['author'] ?? '',
      authorProfileImage: map['authorProfileImage'],
      text: isModerated ? 'This comment was reported to admin' : (map['text'] ?? ''),
      timestamp: parsedTimestamp,
      likes: isModerated ? 0 : (map['likes'] ?? 0),
      isLiked: !isModerated && currentUserId != null ? likedByList.contains(currentUserId) : false,
      likedBy: isModerated ? const [] : likedByList,
      parentId: map['parentId'],
      reactions: isModerated ? {} : Map<String, int>.from(map['reactions'] ?? {}),
      isModerated: isModerated,
      moderationReason: map['moderationReason'] as String?,
      moderatedAt: moderatedAt,
      moderatedBy: map['moderatedBy'] as String?,
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
      'isModerated': isModerated,
      'moderationReason': moderationReason,
      'moderatedAt': moderatedAt != null ? Timestamp.fromDate(moderatedAt!) : null,
      'moderatedBy': moderatedBy,
    };
  }
}
