import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import '../providers/theme_provider.dart';
import 'admin_profile_screen.dart';

class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class AnimatedTypingDots extends StatefulWidget {
  final Color dotColor;
  final double dotSize;

  const AnimatedTypingDots({super.key, required this.dotColor, this.dotSize = 4});

  @override
  State<AnimatedTypingDots> createState() => _AnimatedTypingDotsState();
}

class _AnimatedTypingDotsState extends State<AnimatedTypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double delay = index * 0.2;
            final double value = ( ( _controller.value + delay ) % 1.0 );
            final double translation = -4 * ( 1.0 - ( value - 0.5 ).abs() * 2 );
            return Transform.translate(
              offset: Offset(0, translation),
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: widget.dotColor.withOpacity(0.4 + (0.6 * (1.0 - (value - 0.5).abs() * 2))),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _menuKey = GlobalKey();
  Message? _replyingTo;
  Message? _selectedMessage;
  Message? _editingMessage;

  late AnimationController _bulgeController;
  late Animation<double> _bulgeAnimation;

  final String _adminImageUrl = 'assets/admin_pic.jpeg';

  @override
  void initState() {
    super.initState();
    
    // Mark messages as read when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatServiceProvider.notifier).markAllAsRead();
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Only scroll to bottom on focus if we are already near the bottom
        // or if it's a fresh focus (not returning from a dialog)
        if (_scrollController.hasClients && _scrollController.offset < 100) {
          _scrollToBottom();
        }
      }
    });

    _bulgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _bulgeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(_bulgeController);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _bulgeController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // In reversed list, 0.0 is the bottom (newest)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      ref.read(chatServiceProvider.notifier).sendMessage('', imageFile: File(image.path), replyTo: _replyingTo);
      setState(() => _replyingTo = null);
      _scrollToBottom();
    }
  }

  void _handleSend() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      if (_editingMessage != null) {
        ref.read(chatServiceProvider.notifier).editMessage(_editingMessage!.id, text);
        setState(() => _editingMessage = null);
      } else {
        ref.read(chatServiceProvider.notifier).sendMessage(text, replyTo: _replyingTo);
      }
      _messageController.clear();
      setState(() => _replyingTo = null);
      _scrollToBottom();
    }
  }

  void _onMessageLongPress(Message message) {
    if (message.isDeleted) return;
    setState(() {
      _selectedMessage = message;
      _bulgeController.forward(from: 0);
    });
    _showReactionPicker(message);
  }

  void _showSelectionMenu() {
    if (_selectedMessage == null) return;

    final bool canEditOrDelete = _selectedMessage!.isMe && 
        DateTime.now().difference(_selectedMessage!.timestamp).inMinutes < 15;

    final RenderBox? renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    
    // Position the menu just below the icon button
    final RelativeRect position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + renderBox.size.height,
      offset.dx + renderBox.size.width,
      offset.dy + renderBox.size.height,
    );

    showMenu(
      context: context,
      position: position,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        if (canEditOrDelete && _selectedMessage!.type == MessageType.text)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20, color: Color(0xFF00A884)),
                SizedBox(width: 12),
                Text('Edit'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 20),
              SizedBox(width: 12),
              Text('Copy'),
            ],
          ),
        ),
        if (canEditOrDelete)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.red, size: 20),
                SizedBox(width: 12),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'edit') {
        setState(() {
          _editingMessage = _selectedMessage;
          _messageController.text = _selectedMessage!.text;
          _selectedMessage = null;
          _focusNode.requestFocus();
        });
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: _selectedMessage!.text));
        setState(() => _selectedMessage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard')),
        );
      } else if (value == 'delete') {
        ref.read(chatServiceProvider.notifier).deleteMessage(_selectedMessage!.id);
        setState(() => _selectedMessage = null);
      }
    });
  }

  void _onSwipeReply(Message message) {
    setState(() {
      _replyingTo = message;
      _selectedMessage = null;
    });
    // Small delay to ensure the keyboard pops up after the swipe animation/logic
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  String _getDateFormat(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE').format(date); // e.g., Monday
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = ref.watch(chatServiceProvider);
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    
    // Scroll to bottom whenever messages list changes
    ref.listen(chatServiceProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });

    final appBarColor = isDark ? const Color(0xFF1F2C34) : const Color(0xFF008069);
    final bgColor = isDark ? const Color(0xFF0B141B) : const Color(0xFFE4DDD6);
    final myBubbleColor = isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB);
    final otherBubbleColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    final messages = chatService.messages;

    return PopScope(
      canPop: _selectedMessage == null && _editingMessage == null && _replyingTo == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _selectedMessage = null;
            _editingMessage = null;
            _replyingTo = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leadingWidth: _selectedMessage != null ? 50 : 90,
        leading: _selectedMessage != null
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _selectedMessage = null),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(maxWidth: 40),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminProfileScreen(
                            imageUrl: _adminImageUrl,
                            name: 'System Admin',
                            status: 'online',
                          ),
                        ),
                      );
                    },
                    child: Hero(
                      tag: 'admin_avatar',
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white24,
                        backgroundImage: AssetImage(_adminImageUrl),
                      ),
                    ),
                  ),
                ],
              ),
        title: _selectedMessage != null
            ? const Text('Selected Message', style: TextStyle(color: Colors.white, fontSize: 18))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('System Admin', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (chatService.isAdminTyping)
                    const Row(
                      children: [
                        Text('typing', style: TextStyle(color: Color(0xFF25D366), fontSize: 12, fontWeight: FontWeight.bold)),
                        SizedBox(width: 2),
                        AnimatedTypingDots(dotColor: Color(0xFF25D366), dotSize: 3),
                      ],
                    )
                  else
                    const Text('online', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
        actions: _selectedMessage != null
            ? [
                ScaleTransition(
                  scale: _bulgeAnimation,
                  child: IconButton(
                    key: _menuKey,
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: _showSelectionMenu,
                  ),
                ),
              ]
            : [
                IconButton(icon: const Icon(Icons.videocam, color: Colors.white), onPressed: () {}),
                IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
              ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const NetworkImage('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png'),
            fit: BoxFit.cover,
            opacity: isDark ? 0.15 : 0.2, // Increased visibility
            colorFilter: isDark 
                ? ColorFilter.mode(Colors.black.withOpacity(0.9), BlendMode.dstATop)
                : ColorFilter.mode(Colors.white.withOpacity(0.9), BlendMode.dstATop),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                itemCount: messages.length + (chatService.isAdminTyping ? 2 : 1),
                itemBuilder: (context, index) {
                  // Typing Indicator
                  if (chatService.isAdminTyping && index == 0) {
                    return _buildTypingIndicator(otherBubbleColor, isDark);
                  }

                  final actualIndex = chatService.isAdminTyping ? index - 1 : index;

                  // Disappearing Message Header (Top of Chat)
                  if (actualIndex == messages.length) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16, top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF182229) : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Messages are deleted after 7 days',
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                        ),
                      ),
                    );
                  }
                  
                  final messageIndex = messages.length - 1 - actualIndex;
                  final message = messages[messageIndex];
                  
                  // Logic to show date header
                  bool showDateHeader = false;
                  if (messageIndex == 0) {
                    showDateHeader = true;
                  } else {
                    final prevMessage = messages[messageIndex - 1];
                    final currentDate = DateTime(message.timestamp.year, message.timestamp.month, message.timestamp.day);
                    final prevDate = DateTime(prevMessage.timestamp.year, prevMessage.timestamp.month, prevMessage.timestamp.day);
                    if (currentDate != prevDate) {
                      showDateHeader = true;
                    }
                  }

                  return Column(
                    children: [
                      if (showDateHeader)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF182229) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 2,
                                )
                              ],
                            ),
                            child: Text(
                              _getDateFormat(message.timestamp),
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      TweenAnimationBuilder(
                        duration: const Duration(milliseconds: 300),
                        tween: Tween<double>(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Dismissible(
                          key: Key(message.id),
                          direction: DismissDirection.horizontal, // Support swipe in both directions
                          confirmDismiss: (direction) async {
                            _onSwipeReply(message);
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 16),
                            child: const Icon(Icons.reply, color: Colors.white54),
                          ),
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.reply, color: Colors.white54),
                          ),
                          child: _buildMessageBubble(message, myBubbleColor, otherBubbleColor, textColor, isDark),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _buildInputArea(isDark),
          ],
        ),
      ),
    ),
   );
  }

  Widget _buildTypingIndicator(Color color, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: AnimatedTypingDots(dotColor: isDark ? Colors.white70 : Colors.black45),
      ),
    );
  }

  void _showReactionPicker(Message message) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F2C34) : Colors.white,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...['👍', '❤️', '😂', '😮', '😢', '🙏', '⚽'].map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        ref.read(chatServiceProvider.notifier).addReaction(message.id, emoji);
                        setState(() => _selectedMessage = null);
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    );
                  }),
                  Container(
                    margin: const EdgeInsets.only(left: 4, right: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black45,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, Color myColor, Color otherColor, Color textColor, bool isDark) {
    final isSelected = _selectedMessage?.id == message.id;
    
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _onMessageLongPress(message),
        onTap: () {
          if (_selectedMessage != null) {
            setState(() => _selectedMessage = null);
          }
        },
        child: Container(
          width: double.infinity,
          color: isSelected ? Colors.blue.withOpacity(0.15) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 12), // Extra space for reaction
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: message.isMe ? myColor : otherColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: message.isMe ? const Radius.circular(12) : Radius.zero,
                      bottomRight: message.isMe ? Radius.zero : const Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToId != null && !message.isDeleted)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(6),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                            border: const Border(left: BorderSide(color: Color(0xFF00A884), width: 4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.replyIsImage == true ? 'Photo' : (message.replyText ?? ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      if (message.type == MessageType.image && !message.isDeleted)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: message.imageFile != null
                              ? Image.file(message.imageFile!, fit: BoxFit.cover)
                              : const SizedBox(),
                        ),
                      if (message.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.isDeleted)
                                Icon(
                                  Icons.block,
                                  size: 14,
                                  color: textColor.withOpacity(0.5),
                                ),
                              if (message.isDeleted) const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  message.text,
                                  style: TextStyle(
                                    color: message.isDeleted ? textColor.withOpacity(0.5) : textColor,
                                    fontSize: 16,
                                    fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(message.timestamp),
                            style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11),
                          ),
                          if (message.isMe) ...[
                            const SizedBox(width: 4),
                            _buildStatusTicks(message.status),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (message.reaction != null && !message.isDeleted)
                  Positioned(
                    bottom: 2,
                    right: message.isMe ? 0 : null,
                    left: message.isMe ? null : 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF232D36) : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: Text(
                        message.reaction!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTicks(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 16, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: Colors.white54);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Color(0xFF53BDEB));
    }
  }

  Widget _buildInputArea(bool isDark) {
    return SafeArea(
      child: Column(
        children: [
          if (_editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 20, color: Color(0xFF00A884)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit message',
                          style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          _editingMessage!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _editingMessage = null;
                        _messageController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Replying to',
                          style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          _replyingTo!.type == MessageType.image ? 'Photo' : _replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: (_replyingTo != null || _editingMessage != null) 
                          ? const BorderRadius.vertical(bottom: Radius.circular(25))
                          : BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.emoji_emotions_outlined, color: isDark ? Colors.white54 : Colors.grey),
                          onPressed: () {
                            _focusNode.requestFocus();
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black),
                            onChanged: (text) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.camera_alt, color: isDark ? Colors.white54 : Colors.grey),
                          onPressed: _pickImage,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _handleSend,
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00A884),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        _messageController.text.trim().isEmpty && _editingMessage == null ? Icons.mic : Icons.send,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
