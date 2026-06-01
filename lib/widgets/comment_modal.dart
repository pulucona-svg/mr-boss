import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/comment.dart';
import '../services/comment_service.dart';
import '../providers/user_provider.dart';

class CommentModal extends ConsumerStatefulWidget {
  final String resourceTitle;
  const CommentModal({super.key, required this.resourceTitle});

  @override
  ConsumerState<CommentModal> createState() => _CommentModalState();
}

class _CommentModalState extends ConsumerState<CommentModal> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Comment? _replyingTo;
  Comment? _editingComment;

  void _handleSend() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (_editingComment != null) {
      CommentService().editComment(widget.resourceTitle, _editingComment!.id, text);
      setState(() => _editingComment = null);
    } else {
      final userProfile = ref.read(userProfileProvider);

      CommentService().addComment(
        widget.resourceTitle,
        text,
        replyingTo: _replyingTo,
        authorId: userProfile.uid,
        authorName: userProfile.username,
        authorProfileImage: userProfile.profileImagePath,
      );
    }

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
                  bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16,
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
                            textCapitalization: TextCapitalization.sentences,
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
    final userProfile = ref.watch(userProfileProvider);
    // If it's the current user's comment, use dynamic profile data
    final bool isMe = comment.authorId == userProfile.uid;
    final String displayAuthor = isMe ? userProfile.username : comment.author;
    
    // For "Me", priority is local path then network URL
    final String? displayImage = isMe 
        ? (userProfile.profileImagePath ?? userProfile.photoURL) 
        : comment.authorProfileImage;

    return Dismissible(
      key: Key('comment_${comment.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          setState(() => _replyingTo = comment);
          _focusNode.requestFocus();
        }
        return false; // Don't actually dismiss
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.reply, color: Color(0xFF20C8FF), size: 24),
      ),
      child: GestureDetector(
        onLongPress: () => _showCommentOptions(comment, isMe),
        child: Padding(
          padding: EdgeInsets.only(bottom: 16.0, left: isReply ? 40 : 0, right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: isReply ? 12 : 16,
                    backgroundColor: Colors.white12,
                    backgroundImage: displayImage != null
                        ? (displayImage.startsWith('http') 
                            ? NetworkImage(displayImage) as ImageProvider
                            : FileImage(File(displayImage)))
                        : null,
                    child: displayImage == null
                        ? Text(
                            displayAuthor.isNotEmpty ? displayAuthor[0] : '?',
                            style: TextStyle(color: Colors.white, fontSize: isReply ? 10 : 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayAuthor,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment.text,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          if (comment.reactions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: GestureDetector(
                                onTap: () => _showReactionDetails(comment),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ...comment.reactions.keys.take(2).map((emoji) => Padding(
                                        padding: const EdgeInsets.only(right: 2.0),
                                        child: Text(emoji, style: const TextStyle(fontSize: 12)),
                                      )),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${comment.reactions.values.fold(0, (sum, count) => sum + count)}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
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
        ),
      ),
    );
  }

  void _showCommentOptions(Comment comment, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF1C1A3F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reaction Bar
              _buildReactionRow(comment),
              const SizedBox(height: 10),
              const Text(
                'React to this comment',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              
              if (isMe) ...[
                _buildOptionItem(Icons.edit, 'Edit comment', () {
                  Navigator.pop(context);
                  _startEditing(comment);
                }),
              ],
              
              _buildOptionItem(Icons.reply, 'Reply', () {
                Navigator.pop(context);
                setState(() => _replyingTo = comment);
                _focusNode.requestFocus();
              }),
              
              _buildOptionItem(Icons.copy, 'Copy', () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: comment.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Comment copied to clipboard')),
                );
              }),
              
              if (isMe) ...[
                _buildOptionItem(Icons.delete, 'Delete comment', () {
                  Navigator.pop(context);
                  CommentService().deleteComment(widget.resourceTitle, comment.id);
                }),
              ] else ...[
                _buildOptionItem(Icons.close, 'Hide', () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comment hidden')),
                  );
                }),
                _buildOptionItem(Icons.report_problem, 'Report comment', () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comment reported')),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showReactionDetails(Comment comment) {
    final int totalReactions = comment.reactions.values.fold(0, (sum, count) => sum + count);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF141232),
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$totalReactions reactions',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // Plus emoji button
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        final isMe = comment.authorId == ref.read(userProfileProvider).uid;
                        _showCommentOptions(comment, isMe);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.add_reaction_outlined, color: Colors.white54, size: 20),
                      ),
                    ),
                    // Reaction counts
                    ...comment.reactions.entries.map((entry) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.key, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _startEditing(Comment comment) {
    setState(() => _editingComment = comment);
    _commentController.text = comment.text;
    _focusNode.requestFocus();
  }

  Widget _buildReactionRow(Comment comment) {
    final reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: reactions.map((r) => GestureDetector(
        onTap: () {
          CommentService().updateReaction(widget.resourceTitle, comment.id, r);
          Navigator.pop(context);
        },
        child: Text(r, style: const TextStyle(fontSize: 24)),
      )).toList(),
    );
  }

  Widget _buildOptionItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: onTap,
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
