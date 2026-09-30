import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/admin_user_model.dart';
import '../../services/admin_users_service.dart';
import '../../services/chat_service.dart';
import 'admin_chat_detail_screen.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final String? targetUid;
  final String? userId;
  final AdminUserSummary? summary;
  final AdminUserSummary? initialSummary;
  final AdminUsersService? usersService;

  const AdminUserDetailScreen({
    super.key,
    this.targetUid,
    this.userId,
    this.summary,
    this.initialSummary,
    this.usersService,
  });

  String get effectiveUserId =>
      targetUid ?? userId ?? summary?.uid ?? initialSummary?.uid ?? '';
  AdminUserSummary? get effectiveSummary => summary ?? initialSummary;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AdminUsersService _usersService =
      widget.usersService ?? AdminUsersService();
  late TabController _tabController;

  bool _isLoading = true;
  String? _errorMessage;
  AdminUserFullProfile? _fullProfile;
  bool _isTogglingStatus = false;

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');
  final DateFormat _shortDateFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetail() async {
    final uid = widget.effectiveUserId;
    if (uid.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No valid User ID provided.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await _usersService.getUserDetail(uid);
      if (mounted) {
        setState(() {
          _fullProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmToggleAccountStatus() async {
    final fullProfile = _fullProfile;
    if (fullProfile == null) return;
    final user = fullProfile.user;

    final currentlyDisabled = user.disabled;
    final actionWord = currentlyDisabled ? 'Enable' : 'Disable';
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionWord User Account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentlyDisabled
                  ? 'Enabling this account will restore access to login and app features for ${user.username}.'
                  : 'Disabling this account will immediately revoke access and prevent ${user.username} from signing in.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for $actionWord (optional)',
                hintText: 'e.g. Terms violation, requested by user...',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyDisabled ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionWord),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isTogglingStatus = true);
      try {
        final newDisabledState = !currentlyDisabled;
        final res = await _usersService.toggleUserDisabled(
          user.uid,
          newDisabledState,
          reason: reasonController.text.trim().isNotEmpty
              ? reasonController.text.trim()
              : null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] as String? ??
                  'Account status updated successfully'),
              backgroundColor: newDisabledState ? Colors.red : Colors.green,
            ),
          );
          // Reload fresh details
          _loadUserDetail();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: ${e.toString().replaceAll('Exception: ', '')}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isTogglingStatus = false);
        }
      }
    }
  }

  void _navigateToChat() {
    final fullProfile = _fullProfile;
    if (fullProfile == null) return;
    final user = fullProfile.user;

    final conversation = ConversationSummary(
      userId: user.uid,
      userName: user.username.isNotEmpty ? user.username : 'User',
      userEmail: user.email.isNotEmpty ? user.email : null,
      userPhotoUrl: user.photoURL?.isNotEmpty == true ? user.photoURL : null,
      lastMessageText: '',
      lastMessageTimestamp: DateTime.now(),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdminChatDetailScreen(conversation: conversation),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayName = _fullProfile?.user.username.isNotEmpty == true
        ? _fullProfile!.user.username
        : (widget.effectiveSummary?.displayName.isNotEmpty == true
            ? widget.effectiveSummary!.displayName
            : 'User Details');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadUserDetail,
          ),
        ],
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (_isLoading && _fullProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _fullProfile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load user details',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadUserDetail,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final fullProfile = _fullProfile!;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: _buildHeader(fullProfile, theme, isDark),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                indicatorColor: theme.colorScheme.primary,
                indicatorWeight: 3,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Profile'),
                  Tab(
                    icon: const Icon(Icons.card_membership_outlined, size: 20),
                    text: 'Subscriptions (${fullProfile.subscriptions.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.upload_file_outlined, size: 20),
                    text: 'Materials (${fullProfile.materialsSummary.totalUploads})',
                  ),
                  Tab(
                    icon: const Icon(Icons.devices_outlined, size: 20),
                    text: 'Sessions (${fullProfile.sessions.length})',
                  ),
                ],
              ),
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProfileTab(fullProfile, theme, isDark),
          _buildSubscriptionsTab(fullProfile, theme, isDark),
          _buildMaterialsTab(fullProfile, theme, isDark),
          _buildSessionsTab(fullProfile, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(AdminUserFullProfile fullProfile, ThemeData theme, bool isDark) {
    final user = fullProfile.user;
    final initials = user.username.isNotEmpty
        ? user.username
            .split(' ')
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join()
        : 'U';

    final hasActiveSub = fullProfile.subscriptions.any((s) =>
        s.status.toLowerCase() == 'active' &&
        (s.expiryDate == null || s.expiryDate!.isAfter(DateTime.now())));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: isDark ? const Color(0xFF181818) : Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 34,
                backgroundColor: theme.colorScheme.primary.withAlpha(40),
                backgroundImage: user.photoURL?.isNotEmpty == true
                    ? NetworkImage(user.photoURL!)
                    : null,
                child: (user.photoURL == null || user.photoURL!.isEmpty)
                    ? Text(
                        initials,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Name and Email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username.isNotEmpty ? user.username : 'No Name Provided',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email.isNotEmpty ? user.email : 'No email address',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Badges row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (user.isAdmin)
                          _buildHeaderBadge(
                            'ADMIN',
                            Colors.purple.shade700,
                            Colors.purple.shade50,
                          ),
                        if (hasActiveSub)
                          _buildHeaderBadge(
                            'SUBSCRIBED',
                            Colors.green.shade700,
                            Colors.green.shade50,
                          )
                        else
                          _buildHeaderBadge(
                            'FREE TIER',
                            Colors.blueGrey.shade700,
                            Colors.blueGrey.shade50,
                          ),
                        if (user.disabled)
                          _buildHeaderBadge(
                            'DISABLED',
                            Colors.red.shade700,
                            Colors.red.shade50,
                          )
                        else
                          _buildHeaderBadge(
                            'ACTIVE',
                            Colors.teal.shade700,
                            Colors.teal.shade50,
                          ),
                        if (user.emailVerified)
                          _buildHeaderBadge(
                            'VERIFIED',
                            Colors.blue.shade700,
                            Colors.blue.shade50,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Quick Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _navigateToChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTogglingStatus ? null : _confirmToggleAccountStatus,
                  icon: _isTogglingStatus
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          user.disabled ? Icons.check_circle_outline : Icons.block,
                          size: 18,
                          color: user.disabled ? Colors.green : Colors.red,
                        ),
                  label: Text(
                    user.disabled ? 'Enable' : 'Disable',
                    style: TextStyle(
                      color: user.disabled ? Colors.green : Colors.red,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: user.disabled ? Colors.green.shade300 : Colors.red.shade300,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Copy User ID',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyToClipboard(user.uid, 'User ID'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withAlpha(80), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Profile & Academic
  // ---------------------------------------------------------------------------
  Widget _buildProfileTab(AdminUserFullProfile fullProfile, ThemeData theme, bool isDark) {
    final user = fullProfile.user;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            title: 'Authentication & Identity',
            icon: Icons.security,
            theme: theme,
            isDark: isDark,
            children: [
              _buildDetailRow('User ID', user.uid, canCopy: true),
              _buildDetailRow('Email Verified', user.emailVerified ? 'Yes' : 'No'),
              _buildDetailRow('Auth Provider', user.authProvider.isNotEmpty ? user.authProvider : 'email'),
              _buildDetailRow('Onboarding Completed', user.onboardingComplete ? 'Yes' : 'No'),
              _buildDetailRow(
                'Registered At',
                user.createdAt != null
                    ? _dateFormat.format(user.createdAt!)
                    : (user.joinDate != null ? _dateFormat.format(user.joinDate!) : 'Unknown'),
              ),
              _buildDetailRow(
                'Last Sign In',
                user.lastLogin != null ? _dateFormat.format(user.lastLogin!) : 'Unknown',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Academic & Personal Details',
            icon: Icons.school_outlined,
            theme: theme,
            isDark: isDark,
            children: [
              _buildDetailRow('Full Name', user.username.isNotEmpty ? user.username : '—'),
              _buildDetailRow('Email', user.email.isNotEmpty ? user.email : '—', canCopy: true),
              _buildDetailRow('Phone Number', user.phone.isNotEmpty ? user.phone : '—', canCopy: user.phone.isNotEmpty),
              _buildDetailRow('Institution', user.institution.isNotEmpty ? user.institution : '—'),
              _buildDetailRow('Campus', user.universityLocation.isNotEmpty ? user.universityLocation : '—'),
              _buildDetailRow('Program', user.program.isNotEmpty ? user.program : '—'),
              _buildDetailRow('Program Code', user.programCode.isNotEmpty ? user.programCode : '—'),
              _buildDetailRow('Year of Study', user.year.isNotEmpty ? 'Year ${user.year}' : '—'),
              _buildDetailRow('Semester', user.semester.isNotEmpty ? 'Semester ${user.semester}' : '—'),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: Subscriptions & Payment Audit
  // ---------------------------------------------------------------------------
  Widget _buildSubscriptionsTab(AdminUserFullProfile fullProfile, ThemeData theme, bool isDark) {
    final subscriptions = fullProfile.subscriptions;
    final payments = fullProfile.payments;

    final activeSubs = subscriptions.where((s) => s.status.toLowerCase() == 'active').toList();
    final queuedSubs = subscriptions.where((s) => s.status.toLowerCase() == 'queued').toList();
    final pastSubs = subscriptions.where((s) =>
        s.status.toLowerCase() != 'active' && s.status.toLowerCase() != 'queued').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Subscriptions
          Text(
            'Active Subscription',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (activeSubs.isEmpty)
            _buildEmptyCard('No active subscription found. User is currently on the free tier.')
          else
            ...activeSubs.map((sub) => _buildSubscriptionCard(sub, theme, isDark, isActive: true)),

          if (queuedSubs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Queued Subscriptions (${queuedSubs.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...queuedSubs.map((sub) => _buildSubscriptionCard(sub, theme, isDark, isQueued: true)),
          ],

          const SizedBox(height: 20),
          Text(
            'Subscription History (${pastSubs.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pastSubs.isEmpty)
            _buildEmptyCard('No past subscription history.')
          else
            ...pastSubs.map((sub) => _buildSubscriptionCard(sub, theme, isDark)),

          const SizedBox(height: 24),
          // Safe Payment Records
          Text(
            'Payment Audit Records (${payments.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            _buildEmptyCard('No payment records logged for this user.')
          else
            ...payments.map((p) => _buildPaymentCard(p, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(
    AdminUserSubscription sub,
    ThemeData theme,
    bool isDark, {
    bool isActive = false,
    bool isQueued = false,
  }) {
    Color statusColor = Colors.grey;
    if (isActive) {
      statusColor = Colors.green;
    } else if (isQueued) {
      statusColor = Colors.orange;
    } else if (sub.status.toLowerCase() == 'expired') {
      statusColor = Colors.red.shade400;
    }

    final daysRemaining = sub.expiryDate != null
        ? sub.expiryDate!.difference(DateTime.now()).inDays
        : 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isActive
              ? Colors.green.shade400
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    sub.packageTitle.isNotEmpty ? sub.packageTitle : 'Subscription Package',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor, width: 0.8),
                  ),
                  child: Text(
                    sub.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (sub.amount > 0)
                  Text(
                    'KES ${sub.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                if (sub.amount > 0 && daysRemaining > 0)
                  const Text('  •  ', style: TextStyle(color: Colors.grey)),
                if (daysRemaining > 0)
                  Text(
                    '$daysRemaining days remaining',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              'Valid Period',
              '${sub.activationDate != null ? _shortDateFormat.format(sub.activationDate!) : (sub.purchaseDate != null ? _shortDateFormat.format(sub.purchaseDate!) : '—')} → ${sub.expiryDate != null ? _shortDateFormat.format(sub.expiryDate!) : '—'}',
            ),
            if (sub.downloadCount >= 0)
              _buildDetailRow('Downloads Consumed', '${sub.downloadCount}'),
            if (sub.paystackReference != null && sub.paystackReference!.isNotEmpty)
              _buildDetailRow('Reference', sub.paystackReference!, canCopy: true),
            if (sub.transactionCode.isNotEmpty)
              _buildDetailRow('Transaction Code', sub.transactionCode, canCopy: true),
            if (sub.operatorReceiptNumber != null && sub.operatorReceiptNumber!.isNotEmpty)
              _buildDetailRow('Receipt Number', sub.operatorReceiptNumber!, canCopy: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(AdminUserPayment payment, ThemeData theme, bool isDark) {
    final isSuccess = payment.status.toLowerCase() == 'success';
    final statusColor = isSuccess ? Colors.green : Colors.red;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES ${payment.expectedAmountKes.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    payment.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildDetailRow('Reference', payment.reference, canCopy: true),
            _buildDetailRow('Package', payment.packageName.isNotEmpty ? payment.packageName : '—'),
            _buildDetailRow('Method', payment.paymentMethod.isNotEmpty ? payment.paymentMethod : '—'),
            _buildDetailRow(
              'Date',
              payment.createdAt != null ? _dateFormat.format(payment.createdAt!) : '—',
            ),
            if (payment.failureReason != null && payment.failureReason!.isNotEmpty)
              _buildDetailRow('Failure Reason', payment.failureReason!, isError: true),
            if (payment.operatorReceiptNumber != null && payment.operatorReceiptNumber!.isNotEmpty)
              _buildDetailRow('Receipt', payment.operatorReceiptNumber!, canCopy: true),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: Uploaded Materials
  // ---------------------------------------------------------------------------
  Widget _buildMaterialsTab(AdminUserFullProfile fullProfile, ThemeData theme, bool isDark) {
    final summary = fullProfile.materialsSummary;
    final materials = fullProfile.materials;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Counters Grid
          Text(
            'Upload Overview',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Total Uploads', '${summary.totalUploads}', Icons.cloud_upload_outlined, theme)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Approved', '${summary.approvedCount}', Icons.check_circle_outline, theme, color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Pending', '${summary.pendingCount}', Icons.hourglass_empty, theme, color: Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Rejected', '${summary.rejectedCount}', Icons.cancel_outlined, theme, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Modified', '${summary.modifiedCount}', Icons.edit_note, theme, color: Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Total Views', '${summary.totalViews}', Icons.visibility_outlined, theme)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Total Likes', '${summary.totalLikes}', Icons.thumb_up_outlined, theme)),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Comments', '${summary.totalComments}', Icons.chat_bubble_outline, theme)),
            ],
          ),
          const SizedBox(height: 24),

          // Uploaded Materials List
          Text(
            'Materials Uploaded (${materials.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (materials.isEmpty)
            _buildEmptyCard('This user has not uploaded any materials yet.')
          else
            ...materials.map((m) => _buildMaterialCard(m, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildMaterialCard(AdminUserMaterialItem m, ThemeData theme, bool isDark) {
    Color statusColor = Colors.grey;
    if (m.status.toLowerCase() == 'approved') {
      statusColor = Colors.green;
    } else if (m.status.toLowerCase() == 'pending') {
      statusColor = Colors.orange;
    } else if (m.status.toLowerCase() == 'rejected') {
      statusColor = Colors.red;
    } else if (m.status.toLowerCase() == 'modified') {
      statusColor = Colors.blue;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title.isNotEmpty ? m.title : 'Untitled Material',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${m.unitCode.isNotEmpty ? '${m.unitCode} • ' : ''}${m.unitName.isNotEmpty ? m.unitName : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor, width: 0.8),
                  ),
                  child: Text(
                    m.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (m.type.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.type,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  m.uploadDate != null
                      ? 'Uploaded ${_shortDateFormat.format(m.uploadDate!)}'
                      : '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.visibility_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('${m.views}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 8),
                    const Icon(Icons.thumb_up_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('${m.likes}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            if (m.declineReason != null && m.declineReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Decline reason: ${m.declineReason}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            ],
            if (m.rejectionReasons != null && m.rejectionReasons!.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...m.rejectionReasons!.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• $reason',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                  ),
                ),
              ),
            ],
            if (m.adminRemark != null && m.adminRemark!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Admin remark: ${m.adminRemark}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, ThemeData theme, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.primary).withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: Multi-Device Sessions
  // ---------------------------------------------------------------------------
  Widget _buildSessionsTab(AdminUserFullProfile fullProfile, ThemeData theme, bool isDark) {
    final sessions = fullProfile.sessions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Sessions (${sessions.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (sessions.isEmpty)
            _buildEmptyCard('No recorded device sessions.')
          else
            ...sessions.map((s) => _buildSessionCard(s, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildSessionCard(AdminUserSession session, ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  session.platform.toLowerCase().contains('ios')
                      ? Icons.phone_iphone
                      : Icons.phone_android,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.platform.isNotEmpty ? session.platform : 'Unknown Device',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (session.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Device ID', session.deviceId, canCopy: true),
            _buildDetailRow(
              'Last Active',
              session.lastLogin != null ? _dateFormat.format(session.lastLogin!) : '—',
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required ThemeData theme,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool canCopy = false,
    bool isError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isError ? Colors.red : null,
              ),
            ),
          ),
          if (canCopy && value != '—')
            InkWell(
              onTap: () => _copyToClipboard(value, label),
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.copy, size: 14, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this._bgColor);

  final TabBar _tabBar;
  final Color _bgColor;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _bgColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
