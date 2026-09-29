import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/chat_service.dart';
import 'admin_chat_detail_screen.dart';

class AdminMessagesScreen extends ConsumerStatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  ConsumerState<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends ConsumerState<AdminMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return DateFormat('h:mm a').format(timestamp);
    } else if (today.difference(messageDate).inDays == 1) {
      return 'Yesterday';
    } else if (today.difference(messageDate).inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final chatService = ref.watch(chatServiceProvider);

    final bgColor = isDark ? const Color(0xFF0E0D24) : const Color(0xFFF6F8FA);
    final cardColor = isDark ? const Color(0xFF1B1938) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141232) : Colors.white,
        elevation: 0,
        title: Text(
          'User Inquiries & Messages',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by username or email...',
                  hintStyle: TextStyle(color: subtitleColor, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: subtitleColor, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: subtitleColor, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),

          // Realtime Stream of Conversations
          Expanded(
            child: StreamBuilder<List<ConversationSummary>>(
              stream: chatService.streamAllConversations(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading conversations: ${snapshot.error}',
                      style: TextStyle(color: subtitleColor),
                    ),
                  );
                }

                final allConversations = snapshot.data ?? [];
                final filtered = allConversations.where((conv) {
                  if (_searchQuery.isEmpty) return true;
                  final matchName = conv.userName.toLowerCase().contains(_searchQuery);
                  final matchEmail = (conv.userEmail ?? '').toLowerCase().contains(_searchQuery);
                  final matchId = conv.userId.toLowerCase().contains(_searchQuery);
                  return matchName || matchEmail || matchId;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 56,
                          color: subtitleColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No conversations matching "$_searchQuery"'
                              : 'No conversations yet',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final conv = filtered[index];
                    return _buildConversationTile(
                      context: context,
                      conversation: conv,
                      isDark: isDark,
                      cardColor: cardColor,
                      textColor: textColor,
                      subtitleColor: subtitleColor,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile({
    required BuildContext context,
    required ConversationSummary conversation,
    required bool isDark,
    required Color cardColor,
    required Color textColor,
    required Color subtitleColor,
  }) {
    final hasUnread = conversation.adminUnreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminChatDetailScreen(conversation: conversation),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasUnread
                ? (isDark ? const Color(0xFF221F45) : const Color(0xFFEDF8FF))
                : cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasUnread
                  ? const Color(0xFF20C8FF).withOpacity(0.4)
                  : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
              width: hasUnread ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              // User Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF20C8FF).withOpacity(0.15),
                    backgroundImage: (conversation.userPhotoUrl != null &&
                            conversation.userPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(conversation.userPhotoUrl!)
                        : null,
                    child: (conversation.userPhotoUrl == null ||
                            conversation.userPhotoUrl!.isEmpty)
                        ? Text(
                            conversation.userName.isNotEmpty
                                ? conversation.userName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Color(0xFF20C8FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  if (conversation.isUserTyping)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Conversation Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            conversation.userName,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTimestamp(conversation.lastMessageTimestamp),
                          style: TextStyle(
                            color: hasUnread ? const Color(0xFF20C8FF) : subtitleColor,
                            fontSize: 11,
                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: conversation.isUserTyping
                              ? const Row(
                                  children: [
                                    Text(
                                      'typing...',
                                      style: TextStyle(
                                        color: Color(0xFF25D366),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  conversation.lastMessageText.isNotEmpty
                                      ? conversation.lastMessageText
                                      : 'No messages yet',
                                  style: TextStyle(
                                    color: hasUnread ? textColor : subtitleColor,
                                    fontSize: 13,
                                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        if (hasUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF20C8FF),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              conversation.adminUnreadCount > 9
                                  ? '9+'
                                  : conversation.adminUnreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
