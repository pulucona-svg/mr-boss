import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/xp_transaction.dart';
import '../providers/service_providers.dart';
import '../services/top_notification_service.dart';

class XPPointsBottomSheet extends ConsumerStatefulWidget {
  final bool isDark;

  const XPPointsBottomSheet({
    super.key,
    required this.isDark,
  });

  @override
  ConsumerState<XPPointsBottomSheet> createState() => _XPPointsBottomSheetState();
}

class _XPPointsBottomSheetState extends ConsumerState<XPPointsBottomSheet> {
  String _selectedTab = 'all'; // 'all', 'donation', 'rewarded_ad'
  bool _isWatchingAd = false;
  String? _activeWatchingType;
  String? _feedbackMessage;
  bool _isSuccessFeedback = false;

  @override
  void initState() {
    super.initState();
    // Warm up ad services and sync authoritative remaining counts & cooldown from backend
    final xpService = ref.read(xpServiceProvider);
    xpService.initialize();
    xpService.syncRewardStatus();
  }

  void _watchAd(String rewardType) async {
    final xpService = ref.read(xpServiceProvider);
    if (_isWatchingAd) return;

    if (xpService.isCooldownActive) {
      final msg = 'You can watch another ad in ${xpService.cooldownSecondsRemaining} seconds.';
      setState(() {
        _feedbackMessage = msg;
        _isSuccessFeedback = false;
      });
      TopNotificationService().showNotification(
        context,
        msg,
        type: TopNotificationType.warning,
      );
      return;
    }

    setState(() {
      _isWatchingAd = true;
      _activeWatchingType = rewardType;
      _feedbackMessage = null;
    });

    await xpService.showRewardedAdForXP(
      rewardType: rewardType,
      onSuccess: (xpEarned, message) async {
        if (!mounted) return;

        setState(() {
          _isWatchingAd = false;
          _activeWatchingType = null;
          _feedbackMessage = message;
          _isSuccessFeedback = true;
        });

        // Refresh profile to reflect authoritative balance
        final userProfile = ref.read(userProfileProvider);
        if (userProfile.uid.isNotEmpty) {
          await ref.read(userProfileProvider.notifier).fetchProfileFromFirestore(userProfile.uid);
        }

        if (mounted) {
          TopNotificationService().showNotification(
            context,
            '+$xpEarned XP Earned from Rewarded Ad!',
            type: TopNotificationType.success,
          );
        }
      },
      onFailure: (errorMessage) {
        if (!mounted) return;

        setState(() {
          _isWatchingAd = false;
          _activeWatchingType = null;
          _feedbackMessage = errorMessage;
          _isSuccessFeedback = false;
        });

        TopNotificationService().showNotification(
          context,
          errorMessage,
          type: TopNotificationType.error,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);
    final xpService = ref.watch(xpServiceProvider);
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14142B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF20C8FF).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.stars_rounded, color: Color(0xFF20C8FF), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'XP Points & Rewards',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: subTextColor, size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.white12),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                children: [
                  // XP Balance Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF23144D), Color(0xFF0F1E4A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF20C8FF).withValues(alpha: 0.15),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'TOTAL BALANCE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              NumberFormat('#,###').format(userProfile.xpBalance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'XP',
                              style: TextStyle(
                                color: Color(0xFF20C8FF),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _balanceDetailItem(
                                title: 'Donations',
                                value: '+${NumberFormat('#,###').format(userProfile.donationXp)} XP',
                                icon: Icons.volunteer_activism_rounded,
                                color: const Color(0xFF00E676),
                              ),
                            ),
                            Container(width: 1, height: 32, color: Colors.white12),
                            Expanded(
                              child: _balanceDetailItem(
                                title: 'Ad Rewards',
                                value: '+${NumberFormat('#,###').format(userProfile.adRewardXp)} XP',
                                icon: Icons.play_circle_fill_rounded,
                                color: const Color(0xFF20C8FF),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Section Header
                  Row(
                    children: [
                      Icon(Icons.video_library_rounded, size: 16, color: subTextColor),
                      const SizedBox(width: 6),
                      Text(
                        'WATCH & EARN',
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      if (xpService.isCooldownActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Colors.amberAccent),
                              const SizedBox(width: 4),
                              Text(
                                'Cooldown: ${xpService.cooldownSecondsRemaining}s',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // =========================================================
                  // FIRST BUTTON: +7 XP Rewarded Interstitial
                  // =========================================================
                  _buildRewardOptionCard(
                    isDark: isDark,
                    title: 'Watch Rewarded Interstitial',
                    xpAmount: 7,
                    formatBadge: 'Rewarded Interstitial',
                    remainingCount: xpService.remainingInterstitialToday,
                    maxCount: 20,
                    icon: Icons.auto_awesome_rounded,
                    gradientColors: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                    accentColor: const Color(0xFFD47AFF),
                    isLoading: _isWatchingAd && _activeWatchingType == 'rewarded_interstitial',
                    isAdPreparing: !xpService.isInterstitialAdLoaded && xpService.isInterstitialAdLoading,
                    isCooldown: xpService.isCooldownActive,
                    cooldownSeconds: xpService.cooldownSecondsRemaining,
                    onTap: () => _watchAd('rewarded_interstitial'),
                  ),

                  const SizedBox(height: 12),

                  // =========================================================
                  // SECOND BUTTON: +5 XP Rewarded Video
                  // =========================================================
                  _buildRewardOptionCard(
                    isDark: isDark,
                    title: 'Watch Rewarded Video',
                    xpAmount: 5,
                    formatBadge: 'Rewarded Video',
                    remainingCount: xpService.remainingVideoToday,
                    maxCount: 20,
                    icon: Icons.play_circle_outline_rounded,
                    gradientColors: const [Color(0xFF1E3C72), Color(0xFF2A5298)],
                    accentColor: const Color(0xFF20C8FF),
                    isLoading: _isWatchingAd && _activeWatchingType == 'rewarded_video',
                    isAdPreparing: !xpService.isVideoAdLoaded && xpService.isVideoAdLoading,
                    isCooldown: xpService.isCooldownActive,
                    cooldownSeconds: xpService.cooldownSecondsRemaining,
                    onTap: () => _watchAd('rewarded_video'),
                  ),

                  // In-sheet Feedback Message
                  if (_feedbackMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isSuccessFeedback
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSuccessFeedback ? Colors.green : Colors.redAccent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isSuccessFeedback ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            size: 18,
                            color: _isSuccessFeedback ? Colors.greenAccent : Colors.redAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _feedbackMessage!,
                              style: TextStyle(
                                color: _isSuccessFeedback ? Colors.greenAccent : Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // History Header & Filters
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transaction History',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          _filterChip('all', 'All', isDark),
                          const SizedBox(width: 6),
                          _filterChip('donation', 'Donations', isDark),
                          const SizedBox(width: 6),
                          _filterChip('rewarded_ad', 'Ads', isDark),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // History Stream List
                  StreamBuilder<List<XPTransaction>>(
                    stream: xpService.streamTransactions(userProfile.uid),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final allTransactions = snapshot.data ?? [];
                      final filtered = allTransactions.where((t) {
                        if (_selectedTab == 'all') return true;
                        if (_selectedTab == 'donation') return t.isDonation;
                        if (_selectedTab == 'rewarded_ad') {
                          return t.isAdReward || t.type == 'rewarded_video' || t.type == 'rewarded_interstitial';
                        }
                        return t.type == _selectedTab;
                      }).toList();

                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 40,
                                color: subTextColor.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _selectedTab == 'all'
                                    ? 'No XP transactions yet.\nWatch ads or make a donation to earn points!'
                                    : (_selectedTab == 'donation' ? 'No donation transactions yet.' : 'No ad reward transactions yet.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tx = filtered[index];
                          return _transactionTile(tx, isDark, textColor, subTextColor);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardOptionCard({
    required bool isDark,
    required String title,
    required int xpAmount,
    required String formatBadge,
    required int remainingCount,
    required int maxCount,
    required IconData icon,
    required List<Color> gradientColors,
    required Color accentColor,
    required bool isLoading,
    required bool isAdPreparing,
    required bool isCooldown,
    required int cooldownSeconds,
    required VoidCallback onTap,
  }) {
    final isLimitReached = remainingCount <= 0;
    final isDisabled = _isWatchingAd || isLimitReached;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [gradientColors[0].withValues(alpha: 0.85), gradientColors[1].withValues(alpha: 0.85)]
              : gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradientColors[1].withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? (isCooldown ? onTap : null) : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon / Progress container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isLimitReached ? Icons.check_circle_outline_rounded : icon,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 14),
                // Titles and status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 0.8),
                            ),
                            child: Text(
                              '+$xpAmount XP',
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatBadge,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLimitReached
                            ? 'Daily limit reached (0/$maxCount remaining)'
                            : (isCooldown
                                ? 'Cooldown active ($cooldownSeconds seconds remaining)'
                                : (isAdPreparing
                                    ? 'Preparing advertisement...'
                                    : '$remainingCount/$maxCount remaining today')),
                        style: TextStyle(
                          color: isLimitReached
                              ? Colors.white54
                              : (isCooldown ? Colors.amberAccent : Colors.white70),
                          fontSize: 11,
                          fontWeight: isCooldown ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action indicator
                Icon(
                  isLimitReached
                      ? Icons.block_rounded
                      : (isCooldown ? Icons.timer_outlined : Icons.chevron_right_rounded),
                  color: isLimitReached ? Colors.white38 : (isCooldown ? Colors.amberAccent : Colors.white70),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceDetailItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String id, String label, bool isDark) {
    final isSelected = _selectedTab == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = id;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF20C8FF).withValues(alpha: 0.2)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF20C8FF) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF20C8FF) : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _transactionTile(XPTransaction tx, bool isDark, Color textColor, Color subTextColor) {
    final isDonation = tx.isDonation;
    final isInterstitial = tx.type == 'rewarded_interstitial';
    final dateStr = DateFormat('MMM d, y • h:mm a').format(tx.createdAt);

    final iconColor = isDonation
        ? const Color(0xFF00E676)
        : (isInterstitial ? const Color(0xFFD47AFF) : const Color(0xFF20C8FF));
    final iconData = isDonation
        ? Icons.volunteer_activism_rounded
        : (isInterstitial ? Icons.auto_awesome_rounded : Icons.play_arrow_rounded);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B38) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconData,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tx.description.isNotEmpty ? tx.description : dateStr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: subTextColor.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
            ),
            child: Text(
              '+${tx.xpAmount} XP',
              style: const TextStyle(
                color: Color(0xFF00E676),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
