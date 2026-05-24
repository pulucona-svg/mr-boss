class Comment {
  final String id;
  final String? authorId;
  final String author;
  final String? authorProfileImage;
  String text;
  final DateTime timestamp;
  int likes;
  bool isLiked;
  Map<String, int> reactions;
  final List<Comment> replies;

  Comment({
    required this.id,
    this.authorId,
    required this.author,
    this.authorProfileImage,
    required this.text,
    required this.timestamp,
    this.likes = 0,
    this.isLiked = false,
    Map<String, int>? reactions,
    List<Comment>? replies,
  }) : replies = replies ?? [],
       reactions = reactions ?? {};
}
