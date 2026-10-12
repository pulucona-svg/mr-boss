import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import '../services/deletion_service.dart';
import '../services/persistence_service.dart';
import '../services/top_notification_service.dart';
import 'login_screen.dart';

class AccountRestoreScreen extends ConsumerStatefulWidget {
  const AccountRestoreScreen({super.key});

  @override
  ConsumerState<AccountRestoreScreen> createState() => _AccountRestoreScreenState();
}

class _AccountRestoreScreenState extends ConsumerState<AccountRestoreScreen> {
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;
  bool _isActionInProgress = false;
  bool _isRestoringSequence = false;
  int _restorationStageIndex = 0;
  Timer? _stageTimer;

  final List<String> _restorationStages = const [
    'Restoring your account...',
    'Getting things ready...',
    'Refreshing your profile...',
    'Preparing your Mirror Digital experience...',
    'Almost there...',
    'Account restored successfully',
  ];

  @override
  void initState() {
    super.initState();
    _initCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stageTimer?.cancel();
    super.dispose();
  }

  void _initCountdown() {
    final profile = ref.read(userProfileProvider);
    final scheduledDate = profile.deletionScheduledAt ??
        (profile.deletionRequestedAt != null
            ? profile.deletionRequestedAt!.add(const Duration(days: 30))
            : DateTime.now().add(const Duration(days: 30)));

    _updateRemaining(scheduledDate);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateRemaining(scheduledDate);
      }
    });
  }

  void _updateRemaining(DateTime scheduledDate) {
    final diff = scheduledDate.difference(DateTime.now());
    setState(() {
      _remainingTime = diff.isNegative ? Duration.zero : diff;
    });
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return 'Grace period expired';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days day${days == 1 ? '' : 's'}');
    parts.add('$hours hr${hours == 1 ? '' : 's'}');
    parts.add('$minutes min${minutes == 1 ? '' : 's'}');
    parts.add('$seconds sec${seconds == 1 ? '' : 's'}');
    return parts.join(', ');
  }

  Future<void> _handleCancel() async {
    if (_isActionInProgress || _isRestoringSequence) return;
    setState(() => _isActionInProgress = true);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
      await PersistenceService().clearSession();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        TopNotificationService().showNotification(
          context,
          'Unable to sign out. Please check your internet connection.',
          type: TopNotificationType.error,
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_isActionInProgress || _isRestoringSequence) return;
    setState(() => _isActionInProgress = true);

    try {
      // 1. Authoritative backend restore first
      final result = await DeletionService().restoreUserAccount();

      if (!mounted) return;

      if (!result.success) {
        setState(() => _isActionInProgress = false);
        TopNotificationService().showNotification(
          context,
          result.errorMessage ?? 'Unable to restore account. Please try again.',
          type: TopNotificationType.error,
        );
        return;
      }

      // 2. Refresh local state
      final uid = ref.read(userProfileProvider).uid;
      ref.read(userProfileProvider.notifier).setDeletionStatus(status: 'none');
      if (uid.isNotEmpty) {
        await ref.read(userProfileProvider.notifier).fetchProfileFromFirestore(uid);
      }

      // 3. Initiate the intentional polished ~1-minute restoration presentation
      setState(() {
        _isRestoringSequence = true;
        _restorationStageIndex = 0;
      });

      _startRestorationSequence();
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        TopNotificationService().showNotification(
          context,
          'Restore failed. Please check your internet connection and try again.',
          type: TopNotificationType.error,
        );
      }
    }
  }

  void _startRestorationSequence() {
    // 5 stages at ~10 seconds each = 50s, then final green success state for 4s
    const stageDuration = Duration(milliseconds: 9500);

    _stageTimer = Timer.periodic(stageDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_restorationStageIndex < _restorationStages.length - 2) {
        setState(() {
          _restorationStageIndex++;
        });
      } else {
        // Reached final success state
        timer.cancel();
        setState(() {
          _restorationStageIndex = _restorationStages.length - 1;
        });

        // Conclude after 3.5 seconds on the success screen
        Future.delayed(const Duration(milliseconds: 3500), () {
          if (!mounted) return;
          TopNotificationService().showNotification(
            context,
            'Account restored successfully',
            type: TopNotificationType.success,
          );
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final profile = ref.watch(userProfileProvider);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    // Polished Fullscreen Restoration Experience
    if (_isRestoringSequence) {
      final isFinalStage = _restorationStageIndex == _restorationStages.length - 1;
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: isDark ? const Color(0xFF070716) : const Color(0xFFF7F8FA),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: isFinalStage
                        ? Container(
                            key: const ValueKey('success_icon'),
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE8F5E9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF2E7D32),
                              size: 56,
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('loading_spinner'),
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF20C8FF)),
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _restorationStages[_restorationStageIndex],
                      key: ValueKey(_restorationStageIndex),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isFinalStage ? 20 : 17,
                        fontWeight: FontWeight.bold,
                        color: isFinalStage
                            ? const Color(0xFF2E7D32)
                            : textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isFinalStage
                        ? 'Welcome back to Mirror Digital!'
                        : 'Please hold on while we finish setting up your session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: subTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final dateFormat = DateFormat('MMMM d, yyyy, h:mm a');
    final requestedStr = profile.deletionRequestedAt != null
        ? dateFormat.format(profile.deletionRequestedAt!)
        : 'Recently';
    final scheduledDate = profile.deletionScheduledAt ??
        (profile.deletionRequestedAt != null
            ? profile.deletionRequestedAt!.add(const Duration(days: 30))
            : DateTime.now().add(const Duration(days: 30)));
    final scheduledStr = dateFormat.format(scheduledDate);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleCancel();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF090914) : Colors.white,
        appBar: AppBar(
          title: const Text('Account Restoration'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: textColor,
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    // Warning / Pending Status Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFB74D), width: 1.2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 30),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Account Scheduled for Deletion',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFBF360C),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Your account is currently in the 30-day grace period. You can restore full access now or leave the deletion schedule active.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.brown.shade800,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Countdown Timer Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF13132B) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.timer_outlined, color: Color(0xFF20C8FF), size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Time Remaining in Grace Period',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _formatDuration(_remainingTime),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF20C8FF),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            label: 'Deletion Requested:',
                            value: requestedStr,
                            textColor: textColor,
                            subTextColor: subTextColor,
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow(
                            label: 'Permanent Deletion:',
                            value: scheduledStr,
                            textColor: textColor,
                            subTextColor: subTextColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Preserved Data Information Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF13132B) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'What Happens Next?',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '• Restoring your account cancels the deletion request and re-activates your profile immediately.\n'
                            '• If you choose not to restore, all private credentials, sessions, and personal identifying details will be permanently erased after the grace period.\n'
                            '• Shared academic materials and comments will remain available to other students under an anonymized identity to preserve educational context.',
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Actions: Restore Account (Green) / Cancel (Blue)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D0D1A) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Restore Account (Green)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isActionInProgress ? null : _handleRestore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isActionInProgress
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Restore Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Cancel (Blue)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isActionInProgress ? null : _handleCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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

  Widget _buildDetailRow({
    required String label,
    required String value,
    required Color textColor,
    required Color subTextColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: subTextColor, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
