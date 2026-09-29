import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/comment.dart';
import '../services/comment_service.dart';
import '../services/chat_service.dart';
import '../services/author_profile_cache.dart';
import '../providers/providers.dart';

class CommentModal extends ConsumerStatefulWidget {
  final String resourceId;
  final String resourceTitle;
  final String? targetCommentId;

  const CommentModal({
    super.key,
    required this.resourceId,
    required this.resourceTitle,
    this.targetCommentId,
  });

  @override
  ConsumerState<CommentModal> createState() => _CommentModalState();
}

class _CommentModalState extends ConsumerState<CommentModal> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = {};

  Comment? _replyingTo;
  Comment? _editingComment;
  String? _highlightedCommentId;
  Timer? _highlightTimer;
  bool _hasScrolledToTarget = false;

  @override
  void initState() {
    super.initState();
    if (widget.targetCommentId != null) {
      _highlightedCommentId = widget.targetCommentId;
      _highlightTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _highlightedCommentId = null);
        }
      });
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearHighlight() {
    if (_highlightedCommentId != null) {
      _highlightTimer?.cancel();
      setState(() => _highlightedCommentId = null);
    }
  }

  void _handleSend() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (_editingComment != null) {
      CommentService().editComment(widget.resourceId, _editingComment!.id, text);
      setState(() => _editingComment = null);
    } else {
      final userProfile = ref.read(userProfileProvider);

      CommentService().addComment(
        widget.resourceId,
        text,
        replyingTo: _replyingTo,
        authorId: userProfile.uid,
        authorName: userProfile.username,
        authorProfileImage: userProfile.profileImagePath ?? userProfile.photoURL,
      );
    }

    _commentController.clear();
    _focusNode.unfocus();
    setState(() => _replyingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthorProfileCache(),
      builder: (context, _) {
        return StreamBuilder<List<Comment>>(
          stream: CommentService().streamComments(widget.resourceId),
          builder: (context, snapshot) {
            final comments = snapshot.data ?? [];
            final totalCount = comments.length + comments.fold(0, (sum, c) => sum + c.replies.length);

            // Prefetch live profile photos for all commenters
            final authorUids = comments
                .expand((c) => [c.authorId, ...c.replies.map((r) => r.authorId)])
                .whereType<String>()
                .toSet();
            AuthorProfileCache().prefetchAll(authorUids);

            // Auto-scroll to target comment if specified
            final targetId = widget.targetCommentId;
            final bool targetExists = targetId == null ||
                comments.any((c) => c.id == targetId || c.replies.any((r) => r.id == targetId));

            if (targetId != null && !_hasScrolledToTarget && comments.isNotEmpty && targetExists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _hasScrolledToTarget) return;
                final targetKey = _commentKeys[targetId];
                if (targetKey?.currentContext != null) {
                  _hasScrolledToTarget = true;
                  Scrollable.ensureVisible(
                    targetKey!.currentContext!,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    alignment: 0.3,
                  );
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF141232),
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  // Header Grab Handle
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

                  // Missing/Moderated Target Comment Alert Banner
                  if (targetId != null && snapshot.hasData && !targetExists)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The reported comment is no longer available or was removed.',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Divider(color: Colors.white10, height: 1),

                  // Comments List
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
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
                      bottom: MediaQuery.of(context).viewInsets.bottom +
                          MediaQuery.of(context).padding.bottom +
                          16,
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
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      },
    );
  }

  Widget _buildCommentItem(Comment comment, {bool isReply = false}) {
    final userProfile = ref.watch(userProfileProvider);
    final bool isMe = comment.authorId == userProfile.uid;

    // Authoritative live profile picture and display name
    final String displayAuthor = isMe
        ? userProfile.username
        : (AuthorProfileCache().getName(comment.authorId ?? '', fallback: comment.author) ?? comment.author);

    final String? displayImage = isMe
        ? (userProfile.profileImagePath ?? userProfile.photoURL)
        : AuthorProfileCache().getPhoto(comment.authorId ?? '', fallback: comment.authorProfileImage);

    // Key for scrolling to target
    final GlobalKey itemKey = _commentKeys.putIfAbsent(comment.id, () => GlobalKey());
    final bool isHighlighted = _highlightedCommentId == comment.id;

    return Dismissible(
      key: Key('comment_${comment.id}'),
      direction: comment.isModerated ? DismissDirection.none : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (!comment.isModerated && direction == DismissDirection.startToEnd) {
          setState(() => _replyingTo = comment);
          _focusNode.requestFocus();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.reply, color: Color(0xFF20C8FF), size: 24),
      ),
      child: GestureDetector(
        onTap: () {
          if (isHighlighted) _clearHighlight();
        },
        onLongPress: () {
          if (isHighlighted) _clearHighlight();
          _showCommentOptions(comment, isMe);
        },
        child: AnimatedContainer(
          key: itemKey,
          duration: const Duration(milliseconds: 300),
          margin: EdgeInsets.only(bottom: 12.0, left: isReply ? 40 : 0, right: 16),
          padding: isHighlighted
              ? const EdgeInsets.all(10)
              : const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isHighlighted
                ? const Color(0xFF20C8FF).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isHighlighted
                ? Border.all(color: const Color(0xFF20C8FF), width: 1.8)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author Avatar
                  CircleAvatar(
                    radius: isReply ? 12 : 16,
                    backgroundColor: Colors.white12,
                    backgroundImage: displayImage != null && displayImage.isNotEmpty
                        ? (displayImage.startsWith('http')
                            ? CachedNetworkImageProvider(displayImage) as ImageProvider
                            : FileImage(File(displayImage)))
                        : null,
                    child: (displayImage == null || displayImage.isEmpty)
                        ? Text(
                            displayAuthor.isNotEmpty ? displayAuthor[0].toUpperCase() : '?',
                            style: TextStyle(color: Colors.white, fontSize: isReply ? 10 : 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author Display Name
                        Text(
                          displayAuthor,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Comment Text or Moderated Tag
                        if (comment.isModerated)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_outlined, size: 14, color: Colors.orangeAccent),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'This comment was reported to admin',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
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
                                    color: Colors.white.withValues(alpha: 0.08),
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
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),

                        // Timestamp & Reply Button
                        Row(
                          children: [
                            Text(
                              _formatTimestamp(comment.timestamp),
                              style: const TextStyle(color: Colors.white24, fontSize: 11),
                            ),
                            if (!comment.isModerated) ...[
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
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Likes Icon & Count (hidden on moderated comments)
                  if (!comment.isModerated)
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => CommentService().toggleCommentLike(widget.resourceId, comment),
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

              // Nested Replies (excluded if parent is moderated)
              if (!comment.isModerated && comment.replies.isNotEmpty)
                ...comment.replies.map((reply) => _buildCommentItem(reply, isReply: true)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCommentOptions(Comment comment, bool isMe) {
    final isAdmin = ref.read(adminServiceProvider).isAdmin;

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
              // Reaction Bar (only for active comments)
              if (!comment.isModerated) ...[
                _buildReactionRow(comment),
                const SizedBox(height: 10),
                const Text(
                  'React to this comment',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
              ],

              // Edit comment (own active comment)
              if (isMe && !comment.isModerated) ...[
                _buildOptionItem(Icons.edit, 'Edit comment', () {
                  Navigator.pop(context);
                  _startEditing(comment);
                }),
              ],

              // Reply (active comment)
              if (!comment.isModerated)
                _buildOptionItem(Icons.reply, 'Reply', () {
                  Navigator.pop(context);
                  setState(() => _replyingTo = comment);
                  _focusNode.requestFocus();
                }),

              // Copy (active comment)
              if (!comment.isModerated)
                _buildOptionItem(Icons.copy, 'Copy', () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: comment.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comment copied to clipboard')),
                  );
                }),

              // Author Delete (own comment)
              if (isMe) ...[
                _buildOptionItem(Icons.delete, 'Delete comment', () {
                  Navigator.pop(context);
                  CommentService().deleteComment(widget.resourceId, comment.id);
                }),
              ],

              // Admin Moderation (admin can moderate any comment)
              if (isAdmin && !comment.isModerated) ...[
                _buildOptionItem(Icons.gavel_rounded, 'Moderate / Remove comment', () {
                  Navigator.pop(context);
                  _showModerateDialog(comment);
                }),
              ],

              // User Reporting (non-author, active comment)
              if (!isMe && !comment.isModerated) ...[
                _buildOptionItem(Icons.close, 'Hide', () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Comment hidden')),
                  );
                }),
                _buildOptionItem(Icons.report_problem, 'Report comment', () {
                  Navigator.pop(context);
                  _showReportReasonDialog(comment);
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showReportReasonDialog(Comment comment) {
    const reasons = [
      'Inappropriate or offensive content',
      'Harassment or bullying',
      'Spam or advertising',
      'Academic dishonesty / Cheating',
      'Misleading or false information',
      'Other issue',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1A3F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.report_problem_rounded, color: Color(0xFF20C8FF)),
              SizedBox(width: 8),
              Text(
                'Report Comment',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please select a reason for reporting this comment to administrators:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...reasons.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.radio_button_unchecked, color: Color(0xFF20C8FF), size: 18),
                  title: Text(r, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () async {
                    Navigator.pop(dialogCtx);
                    await _submitReport(comment, r);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitReport(Comment comment, String reason) async {
    final userProfile = ref.read(userProfileProvider);
    try {
      await ChatService().sendCommentReport(
        userId: userProfile.uid,
        userName: userProfile.username,
        userPhotoUrl: userProfile.profileImagePath ?? userProfile.photoURL,
        resourceId: widget.resourceId,
        resourceTitle: widget.resourceTitle,
        commentId: comment.id,
        commentAuthorId: comment.authorId,
        commentAuthor: comment.author,
        commentText: comment.text,
        reason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF00E676), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Comment reported. Admins have received your report.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF141232),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error reporting comment: $e');
    }
  }

  void _showModerateDialog(Comment comment) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1A3F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                'Moderate Comment',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'This action will replace the comment with "This comment was reported to admin" and remove all of its replies. The material\'s comment count will be updated.\n\nProceed with moderation?',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final adminProfile = ref.read(userProfileProvider);
                try {
                  await CommentService().moderateComment(
                    widget.resourceId,
                    comment.id,
                    reason: 'Reported to admin',
                    adminUid: adminProfile.uid,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comment has been moderated')),
                    );
                  }
                } catch (e) {
                  debugPrint('Error moderating comment: $e');
                }
              },
              child: const Text('Moderate Comment', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!comment.isModerated)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          final isMe = comment.authorId == ref.read(userProfileProvider).uid;
                          _showCommentOptions(comment, isMe);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.add_reaction_outlined,
                              color: Colors.white54, size: 20),
                        ),
                      ),
                    ...comment.reactions.entries.map(
                      (entry) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(entry.key, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              '${entry.value}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
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
      children: reactions
          .map((r) => GestureDetector(
                onTap: () {
                  CommentService().updateReaction(widget.resourceId, comment.id, r);
                  Navigator.pop(context);
                },
                child: Text(r, style: const TextStyle(fontSize: 24)),
              ))
          .toList(),
    );
  }

  Widget _buildOptionItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
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
