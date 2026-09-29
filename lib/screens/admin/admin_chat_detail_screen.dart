import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/chat_service.dart';
import '../../widgets/comment_modal.dart';
import '../help_support_screen.dart';

class AdminChatDetailScreen extends ConsumerStatefulWidget {
  final ConversationSummary conversation;

  const AdminChatDetailScreen({
    super.key,
    required this.conversation,
  });

  @override
  ConsumerState<AdminChatDetailScreen> createState() => _AdminChatDetailScreenState();
}

class _AdminChatDetailScreenState extends ConsumerState<AdminChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  Message? _replyingTo;

  ChatService? _chatService;

  @override
  void initState() {
    super.initState();
    _chatService = ref.read(chatServiceProvider);

    // Mark conversation messages read by admin upon opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatService?.markAdminRead(widget.conversation.userId);
    });

    _messageController.addListener(_onAdminTextChanged);
  }

  void _onAdminTextChanged() {
    final text = _messageController.text;
    _chatService?.setAdminTyping(
      userId: widget.conversation.userId,
      isTyping: text.trim().isNotEmpty,
    );
  }

  @override
  void dispose() {
    _chatService?.setAdminTyping(
      userId: widget.conversation.userId,
      isTyping: false,
    );
    _messageController.removeListener(_onAdminTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final adminProfile = ref.read(userProfileProvider);
    _messageController.clear();
    final reply = _replyingTo;
    setState(() => _replyingTo = null);

    await ref.read(chatServiceProvider).adminSendMessage(
      userId: widget.conversation.userId,
      text: text,
      replyTo: reply,
      adminId: adminProfile.uid.isNotEmpty ? adminProfile.uid : 'admin',
    );

    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final adminProfile = ref.read(userProfileProvider);
      final reply = _replyingTo;
      setState(() => _replyingTo = null);

      await ref.read(chatServiceProvider).adminSendMessage(
        userId: widget.conversation.userId,
        text: '',
        imageFile: File(image.path),
        replyTo: reply,
        adminId: adminProfile.uid.isNotEmpty ? adminProfile.uid : 'admin',
      );

      _scrollToBottom();
    }
  }

  void _onMessageLongPress(Message message) {
    if (message.isDeleted) return;
    _showReactionAndActionMenu(message);
  }

  void _showReactionAndActionMenu(Message message) {
    final bool canDeleteEveryone = message.isMe &&
        DateTime.now().difference(message.timestamp).inMinutes <= 15;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji Reaction Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🙏', '⚽'].map((emoji) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        ref.read(chatServiceProvider).addReaction(message.id, emoji);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(color: Colors.white12),

              // Copy
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: Colors.white),
                title: const Text('Copy message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
              ),

              // Reply
              ListTile(
                leading: const Icon(Icons.reply, color: Color(0xFF20C8FF)),
                title: const Text('Reply to message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _replyingTo = message;
                  });
                  _focusNode.requestFocus();
                },
              ),

              // Delete
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete message', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteOptions(message, canDeleteEveryone);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteOptions(Message message, bool canDeleteEveryone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141232),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete message?', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          canDeleteEveryone
              ? 'Delete this message for everyone or for yourself only?'
              : 'Delete this message for yourself? The user will still be able to view it.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(chatServiceProvider).deleteMessageForMe(message.id);
            },
            child: const Text('Delete for me', style: TextStyle(color: Color(0xFF20C8FF))),
          ),
          if (canDeleteEveryone)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(chatServiceProvider).deleteMessageForEveryone(message.id);
              },
              child: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  String _formatMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (today.difference(messageDate).inDays == 1) {
      return 'Yesterday';
    } else if (today.difference(messageDate).inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMMM d, y').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final chatService = ref.watch(chatServiceProvider);
    final adminProfile = ref.watch(userProfileProvider);

    final bgColor = isDark ? const Color(0xFF0E0D24) : const Color(0xFFEFE7DE);
    final appBarColor = isDark ? const Color(0xFF141232) : const Color(0xFF1A1A2E);
    final myBubbleColor = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final otherBubbleColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF20C8FF).withValues(alpha: 0.2),
              backgroundImage: (widget.conversation.userPhotoUrl != null &&
                      widget.conversation.userPhotoUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(widget.conversation.userPhotoUrl!)
                  : null,
              child: (widget.conversation.userPhotoUrl == null ||
                      widget.conversation.userPhotoUrl!.isEmpty)
                  ? Text(
                      widget.conversation.userName.isNotEmpty
                          ? widget.conversation.userName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Color(0xFF20C8FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.conversation.isUserTyping)
                    const Row(
                      children: [
                        Text(
                          'typing',
                          style: TextStyle(
                            color: Color(0xFF25D366),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 3),
                        AnimatedTypingDots(dotColor: Color(0xFF25D366), dotSize: 3),
                      ],
                    )
                  else
                    Text(
                      widget.conversation.userEmail ?? 'User',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages Stream
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: chatService.streamConversationMessages(
                widget.conversation.userId,
                adminId: adminProfile.uid.isNotEmpty ? adminProfile.uid : 'admin',
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages in this conversation yet.',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final messageIndex = messages.length - 1 - index;
                    final message = messages[messageIndex];

                    bool showDateHeader = false;
                    if (messageIndex == 0) {
                      showDateHeader = true;
                    } else {
                      final prevMessage = messages[messageIndex - 1];
                      final currentDate = DateTime(
                          message.timestamp.year, message.timestamp.month, message.timestamp.day);
                      final prevDate = DateTime(prevMessage.timestamp.year,
                          prevMessage.timestamp.month, prevMessage.timestamp.day);
                      if (currentDate != prevDate) {
                        showDateHeader = true;
                      }
                    }

                    return Column(
                      children: [
                        if (showDateHeader)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _formatMessageDate(message.timestamp),
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        _buildMessageBubble(
                          message: message,
                          myBubbleColor: myBubbleColor,
                          otherBubbleColor: otherBubbleColor,
                          isDark: isDark,
                          textColor: textColor,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Replying Preview Banner
          if (_replyingTo != null) _buildReplyPreview(isDark),

          // Message Input Field
          _buildMessageInput(isDark),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141232) : Colors.grey.shade200,
        border: const Border(
          top: BorderSide(color: Color(0xFF20C8FF), width: 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingTo!.isMe ? 'Replying to yourself' : 'Replying to user',
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!.text.isNotEmpty ? _replyingTo!.text : '📷 Photo',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: isDark ? Colors.white70 : Colors.black54,
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required Message message,
    required Color myBubbleColor,
    required Color otherBubbleColor,
    required bool isDark,
    required Color textColor,
  }) {
    final isMe = message.isMe;
    final timeStr = DateFormat('h:mm a').format(message.timestamp);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _onMessageLongPress(message),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe ? myBubbleColor : otherBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Reply Quote Preview
              if (message.replyToId != null && message.replyText != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF20C8FF), width: 3),
                    ),
                  ),
                  child: Text(
                    message.replyText!,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // Image Message
              if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: message.imageUrl!,
                      placeholder: (context, url) => const SizedBox(
                        height: 140,
                        child: Center(
                          child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                    ),
                  ),
                ),

              // Text Message
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    color: message.isDeleted
                        ? (isDark ? Colors.white38 : Colors.black38)
                        : (isMe && isDark ? Colors.white : textColor),
                    fontSize: 14,
                    fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),

              // Comment Report Action Card
              if (message.metadata != null && message.metadata!['reportType'] == 'comment_report') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20C8FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.35), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.flag_rounded, size: 14, color: Color(0xFF20C8FF)),
                          SizedBox(width: 4),
                          Text(
                            'REPORTED COMMENT',
                            style: TextStyle(
                              color: Color(0xFF20C8FF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          final materialId = message.metadata!['materialId']?.toString() ?? '';
                          final materialTitle = message.metadata!['materialTitle']?.toString() ?? 'Material';
                          final commentId = message.metadata!['commentId']?.toString() ?? '';
                          if (materialId.isNotEmpty) {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => CommentModal(
                                resourceId: materialId,
                                resourceTitle: materialTitle,
                                targetCommentId: commentId,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20C8FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Inspect Reported Comment',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 4),

              // Time & Status Indicators
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: isMe && isDark ? Colors.white60 : Colors.black45,
                      fontSize: 10,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                  ],
                ],
              ),

              // Reaction Emoji Badge
              if (message.reaction != null)
                Transform.translate(
                  offset: const Offset(0, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(message.reaction!, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.white60);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white60);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF34B7F1));
    }
  }

  Widget _buildMessageInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141232) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attach Image Button
            IconButton(
              icon: const Icon(Icons.attach_file, color: Color(0xFF20C8FF)),
              onPressed: _pickImage,
            ),

            // Text Input Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1C38) : const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type your reply...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send Button
            Material(
              color: const Color(0xFF20C8FF),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _handleSend,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.send, color: Colors.black, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
