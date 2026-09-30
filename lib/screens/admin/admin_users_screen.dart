import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/admin_user_model.dart';
import '../../services/admin_users_service.dart';
import 'admin_user_detail_screen.dart';

class AdminUsersScreen extends StatefulWidget {
  final AdminUsersService? usersService;

  const AdminUsersScreen({super.key, this.usersService});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminUsersService _usersService =
      widget.usersService ?? AdminUsersService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<AdminUserSummary> _users = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _nextPageToken;
  bool _isLoadingMore = false;

  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'active_subscribers', 'admins', 'disabled'

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
        });
        _fetchUsers();
      }
    });
  }

  Future<void> _fetchUsers({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (refresh) {
        _nextPageToken = null;
      }
    });

    try {
      final result = await _usersService.getUsersList(
        pageSize: 30,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        roleFilter: _selectedFilter,
      );

      setState(() {
        _users = result.users;
        _nextPageToken = result.nextPageToken;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst(RegExp(r'^[A-Za-z0-9_]+Exception: '), '');
      });
    }
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore || _nextPageToken == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await _usersService.getUsersList(
        pageSize: 30,
        pageToken: _nextPageToken,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        roleFilter: _selectedFilter,
      );

      setState(() {
        _users.addAll(result.users);
        _nextPageToken = result.nextPageToken;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (date == today) {
      return DateFormat('h:mm a').format(timestamp);
    } else if (today.difference(date).inDays == 1) {
      return 'Yesterday';
    } else if (today.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(timestamp);
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0C1D) : const Color(0xFFF6F8FA);
    final cardColor = isDark ? const Color(0xFF141232) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users Management',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_users.length} registered accounts',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textColor),
            onPressed: () => _fetchUsers(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // WhatsApp-style Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1938) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name, email, phone, or program...',
                  hintStyle: TextStyle(color: subtitleColor, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: subtitleColor, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: subtitleColor, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _fetchUsers();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('all', 'All Users', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('active_subscribers', 'Active Subscribers', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('admins', 'Admins', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('disabled', 'Disabled', isDark),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // User List View
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF20C8FF),
              backgroundColor: cardColor,
              onRefresh: () => _fetchUsers(refresh: true),
              child: _buildBody(cardColor, textColor, subtitleColor, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterId, String label, bool isDark) {
    final isSelected = _selectedFilter == filterId;
    return InkWell(
      onTap: () {
        if (_selectedFilter != filterId) {
          setState(() {
            _selectedFilter = filterId;
          });
          _fetchUsers(refresh: true);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF20C8FF).withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF20C8FF)
                : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF20C8FF) : (isDark ? Colors.white70 : Colors.black54),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Color cardColor, Color textColor, Color subtitleColor, bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                'Failed to load users',
                style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchUsers(refresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF20C8FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: subtitleColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No users matching "$_searchQuery"' : 'No registered users found',
              style: TextStyle(color: subtitleColor, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!_isLoadingMore &&
            _nextPageToken != null &&
            scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
          _loadMoreUsers();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _users.length + (_nextPageToken != null ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF20C8FF),
                  ),
                ),
              ),
            );
          }

          final user = _users[index];
          return _buildUserCard(user, cardColor, textColor, subtitleColor, isDark);
        },
      ),
    );
  }

  Widget _buildUserCard(
    AdminUserSummary user,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final timestampStr = _formatTimestamp(user.lastLogin ?? user.createdAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminUserDetailScreen(
                targetUid: user.uid,
                summary: user,
              ),
            ),
          ).then((_) {
            // Refresh on returning in case user status changed
            _fetchUsers();
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: user.disabled
                ? (isDark ? const Color(0xFF2C1318) : const Color(0xFFFDE8E8))
                : cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: user.disabled
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : user.isAdmin
                      ? Colors.amber.withValues(alpha: 0.3)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF20C8FF).withValues(alpha: 0.12),
                    backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty)
                        ? CachedNetworkImageProvider(user.photoURL!)
                        : null,
                    child: (user.photoURL == null || user.photoURL!.isEmpty)
                        ? Text(
                            user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Color(0xFF20C8FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  if (user.disabled)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 1.5),
                        ),
                        child: const Icon(Icons.block_rounded, size: 10, color: Colors.white),
                      ),
                    )
                  else if (user.hasActiveSubscription)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 1.5),
                        ),
                        child: const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Username & timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.username,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (user.emailVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF20C8FF)),
                              ],
                            ],
                          ),
                        ),
                        if (timestampStr.isNotEmpty)
                          Text(
                            timestampStr,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    // Middle row: Email
                    Text(
                      user.email.isNotEmpty ? user.email : 'No email address',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Bottom row: Program & Badges
                    Row(
                      children: [
                        if (user.programCode.isNotEmpty || user.year.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              '${user.programCode} ${user.year}'.trim(),
                              style: TextStyle(
                                color: subtitleColor.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        // Status Pills
                        if (user.isAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Admin',
                              style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          )
                        else if (user.hasActiveSubscription)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Subscribed',
                              style: TextStyle(color: Color(0xFF00E676), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: subtitleColor.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
