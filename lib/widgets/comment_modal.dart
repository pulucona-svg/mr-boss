import 'package:flutter/material.dart';
import '../models/comment.dart';
import '../services/comment_service.dart';

class CommentModal extends StatefulWidget {
  final String resourceTitle;
  const CommentModal({super.key, required this.resourceTitle});

  @override
  State<CommentModal> createState() => _CommentModalState();
}

class _CommentModalState extends State<CommentModal> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Comment? _replyingTo;

  void _handleSend() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    CommentService().addComment(
      widget.resourceTitle,
      text,
      replyingTo: _replyingTo,
    );

    _commentController.clear();
    _focusNode.unfocus();
    setState(() => _replyingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CommentService(),
      builder: (context, child) {
        final comments = CommentService().getComments(widget.resourceTitle);
        final totalCount = comments.length + comments.fold(0, (sum, c) => sum + c.replies.length);

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Color(0xFF141232),
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$totalCount Comments',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              // Comments List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    return _buildCommentItem(comments[index]);
                  },
                ),
              ),

              // Input Field
              Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  left: 16,
                  right: 16,
                  top: 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1A3F),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Text(
                              'Replying to ${_replyingTo!.author}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() => _replyingTo = null),
                              child: const Icon(Icons.close, color: Colors.white54, size: 16),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _focusNode,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _replyingTo != null ? 'Add a reply...' : 'Add a comment...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _handleSend,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF20C8FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentItem(Comment comment, {bool isReply = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.0, left: isReply ? 40 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 12 : 16,
                backgroundColor: Colors.white12,
                child: Text(
                  comment.author[0],
                  style: TextStyle(color: Colors.white, fontSize: isReply ? 10 : 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.author,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comment.text,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _formatTimestamp(comment.timestamp),
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () {
                            setState(() => _replyingTo = comment);
                            _focusNode.requestFocus();
                          },
                          child: const Text(
                            'Reply',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  GestureDetector(
                    onTap: () => CommentService().toggleCommentLike(widget.resourceTitle, comment),
                    child: Icon(
                      comment.isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: comment.isLiked ? const Color(0xFFFF8A00) : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${comment.likes}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          if (comment.replies.isNotEmpty)
            ...comment.replies.map((reply) => _buildCommentItem(reply, isReply: true)),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
