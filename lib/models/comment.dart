class Comment {
  final String id;
  final String author;
  final String text;
  final DateTime timestamp;
  int likes;
  bool isLiked;
  final List<Comment> replies;

  Comment({
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
    this.likes = 0,
    this.isLiked = false,
    List<Comment>? replies,
  }) : replies = replies ?? [];
}
